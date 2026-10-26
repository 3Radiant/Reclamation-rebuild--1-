--[[
	ShifterBase (server)
	One instance per player. Handles:
	  Shift()      bite -> build Titan -> Player.Character = Titan (human body removed)
	  Deshift()    the Titan evaporates and the player genuinely RESPAWNS as a human
	               (Player:LoadCharacter) where the Titan stood - fresh body, fresh loadout
	  M1()         server-authoritative melee combo with box hitboxes
	  UseAbility() overridden by Titan subclasses (see Titans/ArmoredTitan)
	  Tick()       Titan regeneration
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local TitanConfigs = require(Shared.Configs.TitanConfigs)
local Hitbox = require(Shared.Hitbox)
local PlayerState = require(Shared.PlayerState)
local Remotes = require(Shared.Remotes)

local DamageService = require(script.Parent.Parent.Services.DamageService)
local SpawnOverride = require(script.Parent.Parent.Services.SpawnOverride)
local Effects = require(script.Parent.Effects)
local TitanFactory = require(script.Parent.TitanFactory)

local TitanHands = require(script.Parent.TitanHands)

local ShifterBase = {}
ShifterBase.__index = ShifterBase

function ShifterBase.new(player: Player, titanName: string)
	local self = setmetatable({
		Player = player,
		TitanName = titanName,
		Config = TitanConfigs[titanName],

		ShiftCount = 0,
		MaxShifts = GameConfig.Shifting.MaxShifts,
		Shifted = false,
		Transforming = false,
		ReadyAt = 0, -- os.clock() time you may shift again

		Model = nil :: Model?, -- the Titan

		Combo = 0,
		LastM1 = 0,
		NextM1 = 0,
		AbilityReadyAt = {} :: { [string]: number },
		Connections = {} :: { RBXScriptConnection },
	}, ShifterBase)
	TitanHands.init(self)
	return self
end

function ShifterBase.SetMode(self: any, mode: string?)
	TitanHands.setMode(self, mode)
end
function ShifterBase.Grab(self: any, arm: string)
	TitanHands.grab(self, arm)
end
function ShifterBase.UseHand(self: any, arm: string)
	TitanHands.use(self, arm)
end

----------------------------------------------------------------------
-- Shifting
----------------------------------------------------------------------

function ShifterBase.CanShift(self: any): (boolean, string?)
	if self.Shifted or self.Transforming then
		return false, "Busy"
	end
	if self.ShiftCount >= self.MaxShifts then
		return false, "NoShiftsLeft"
	end
	if os.clock() < self.ReadyAt then
		return false, "Cooldown"
	end
	local character = self.Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 or character:GetAttribute("IsTitan") then
		return false, "NoCharacter"
	end
	return true, nil
end

function ShifterBase._endTransform(self: any)
	self.Transforming = false
	PlayerState.set(self.Player, "Transforming", false)
end

-- Yields (the bite animation plays on the client during BiteTime)
function ShifterBase.Shift(self: any): boolean
	if not self:CanShift() then
		return false
	end

	local player: Player = self.Player
	self.Transforming = true
	PlayerState.set(player, "Transforming", true) -- client plays the bite animation + locks movement

	task.wait(GameConfig.Shifting.BiteTime)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if player.Parent ~= Players or not character or not humanoid or humanoid.Health <= 0 or not root then
		self:_endTransform()
		return false
	end

	local ok, titan = pcall(TitanFactory.create, self.TitanName, player)
	if not ok then
		warn("[ShifterBase] Failed to build Titan:", titan)
		self:_endTransform()
		return false
	end

	-- We yielded; make sure nothing changed while the model was built
	if player.Parent ~= Players or player.Character ~= character or humanoid.Health <= 0 then
		titan:Destroy()
		self:_endTransform()
		return false
	end

	-- Place the Titan standing on the ground where the human was, same facing
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, titan }
	local ground = Workspace:Raycast(root.Position, Vector3.new(0, -200, 0), params)
	local groundY = ground and ground.Position.Y or (root.Position.Y - 3)

	local boxCFrame, boxSize = titan:GetBoundingBox()
	local feetOffset = titan:GetPivot().Position.Y - (boxCFrame.Position.Y - boxSize.Y / 2)
	local yaw = select(2, root.CFrame:ToOrientation())
	titan:PivotTo(CFrame.new(root.Position.X, groundY + feetOffset + 0.5, root.Position.Z) * CFrame.fromOrientation(0, yaw, 0))

	-- The swap
	local heightStuds: number = titan:GetAttribute("TitanHeight")
	Effects.shift(root.Position, heightStuds)
	Remotes.ShiftFx:FireAllClients({ Position = root.Position, Height = heightStuds, UserId = player.UserId })

	-- The human body and its gear are consumed by the transformation (you respawn fresh later)
	humanoid:UnequipTools()
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		backpack:ClearAllChildren()
	end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") then
			child:Destroy()
		end
	end

	titan.Parent = Workspace
	player.Character = titan
	pcall(function()
		titan.PrimaryPart:SetNetworkOwner(player)
	end)
	character:Destroy()

	self.Model = titan
	self.Mode = "Combat"
	titan:SetAttribute("TitanMode", "Combat")
	titan:SetAttribute("Hand_Left", "Idle")
	titan:SetAttribute("Hand_Right", "Idle")
	self.Shifted = true
	self.ShiftCount += 1
	self.Combo = 0

	local titanHumanoid = titan:FindFirstChildOfClass("Humanoid")
	if titanHumanoid then
		table.insert(
			self.Connections,
			titanHumanoid.Died:Connect(function()
				task.spawn(self.Deshift, self, "Died")
			end)
		)
	end

	PlayerState.set(player, "ShiftsLeft", self.MaxShifts - self.ShiftCount)
	PlayerState.set(player, "Shifted", true)
	self:_endTransform()
	return true
end

-- reason: "Manual" | "Defeated" | "Died". Yields while the new body loads.
function ShifterBase.Deshift(self: any, reason: string?): boolean
	if not self.Shifted or not self.Model then
		return false
	end
	self.Shifted = false

	TitanHands.releaseAll(self)
	self.Mode = "Combat"

	local player: Player = self.Player
	local titan: Model = self.Model
	self.Model = nil

	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)

	local heightStuds: number = titan:GetAttribute("TitanHeight") or 45
	local titanRoot = titan.PrimaryPart
	local nape = titan:FindFirstChild("Nape", true)
	local emergePosition: Vector3 = (nape and nape:IsA("BasePart") and nape.Position + Vector3.new(0, 3, 0))
		or (titanRoot and titanRoot.Position)
		or Vector3.new(0, 10, 0)
	local yaw = titanRoot and select(2, titanRoot.CFrame:ToOrientation()) or 0

	-- Cooldown + state first, so everything is consistent even if the respawn fails
	self.ReadyAt = os.clock() + GameConfig.Shifting.Cooldown
	PlayerState.set(player, "ShiftReadyAt", Workspace:GetServerTimeNow() + GameConfig.Shifting.Cooldown)
	PlayerState.set(player, "Shifted", false)

	-- The Titan evaporates. Detach it from the player FIRST so LoadCharacter doesn't
	-- destroy it before the effect plays.
	Effects.evaporate(titanRoot and titanRoot.Position or emergePosition, heightStuds)
	titan:SetAttribute("IsTitan", nil) -- no longer a valid target
	local titanHumanoid = titan:FindFirstChildOfClass("Humanoid")
	if titanHumanoid then
		titanHumanoid.WalkSpeed = 0
	end
	for _, descendant in titan:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			TweenService:Create(descendant, TweenInfo.new(2.5), { Transparency = 1 }):Play()
		end
	end
	if player.Character == titan then
		player.Character = nil
	end
	task.delay(3, function()
		titan:Destroy()
	end)

	-- Respawn the player as a human where the Titan stood
	if player.Parent == Players then
		SpawnOverride.set(player, {
			CFrame = CFrame.new(emergePosition) * CFrame.fromOrientation(0, yaw, 0),
			HealthFraction = if reason == "Manual" then 1 else GameConfig.Damage.HumanHealthAfterDefeat,
		})
		PlayerState.set(player, "Respawning", true) -- so round logic doesn't count you as dead
		local ok, err = pcall(player.LoadCharacter, player)
		if not ok then
			warn("[ShifterBase] Respawn after Titan failed:", err)
			PlayerState.set(player, "Respawning", false)
			SpawnOverride.clear(player)
		end
	end
	return true
end

----------------------------------------------------------------------
-- Combat
----------------------------------------------------------------------

function ShifterBase.M1(self: any)
	if not self.Shifted or self.Transforming or not self.Model or self.Mode == "Grab" then
		return
	end

	local m1 = self.Config.Combat.M1
	local now = os.clock()
	if now < self.NextM1 then
		return
	end
	if now - self.LastM1 > m1.ComboReset then
		self.Combo = 0
	end

	self.Combo = self.Combo % #m1.Hits + 1
	local hit = m1.Hits[self.Combo]
	self.LastM1 = now
	self.NextM1 = now + (hit.Cooldown or m1.Cooldown)

	-- Clients watch these attributes to play the swing animation
	local model: Model = self.Model
	model:SetAttribute("AttackCombo", self.Combo)
	model:SetAttribute("AttackSerial", (model:GetAttribute("AttackSerial") or 0) + 1)

	task.delay(hit.Windup, function()
		self:_resolveHit(model, hit)
	end)
end

function ShifterBase._resolveHit(self: any, model: Model, hit: any)
	if not self.Shifted or self.Model ~= model or not model.PrimaryPart then
		return
	end

	local root = model.PrimaryPart
	local height: number = model:GetAttribute("TitanHeight")
	local size: Vector3 = hit.Size * height
	local cframe = root.CFrame * CFrame.new(0, 0, -(hit.Forward * height))

	if GameConfig.DebugHitboxes then
		Hitbox.visualize(cframe, size, 0.3)
	end

	for _, victim in Hitbox.getModels(cframe, size, { model }) do
		local damage = victim:GetAttribute("IsTitan") and hit.DamageTitan or hit.DamageHuman
		DamageService.damage(self.Player, victim, damage, { Source = "TitanMelee" })

		local victimPlayer = Players:GetPlayerFromCharacter(victim)
		local victimRoot = victim:FindFirstChild("HumanoidRootPart")
		if victimPlayer and victimRoot and victimRoot:IsA("BasePart") and hit.Knockback then
			local away = (victimRoot.Position - root.Position) * Vector3.new(1, 0, 1)
			away = away.Magnitude > 0 and away.Unit or Vector3.zero
			Remotes.Knockback:FireClient(victimPlayer, away * hit.Knockback + Vector3.new(0, hit.Knockback * 0.3, 0))
		end
	end
end

-- Subclasses override this
function ShifterBase.UseAbility(self: any, _abilityName: string): boolean
	return false
end

----------------------------------------------------------------------
-- Regeneration + cleanup
----------------------------------------------------------------------

function ShifterBase.Tick(self: any, dt: number)
	local model: Model? = self.Model
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not model or not humanoid then
		return
	end
	local regen = self.Config.Regen
	local sinceHit = Workspace:GetServerTimeNow() - (model:GetAttribute("LastDamaged") or 0)
	if regen and sinceHit >= regen.Delay and humanoid.Health < humanoid.MaxHealth then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + regen.PerSecond * dt)
	end
end

function ShifterBase.Destroy(self: any)
	TitanHands.releaseAll(self)
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	if self.Model then
		self.Model:Destroy()
	end
	self.Model = nil
	self.Shifted = false
end

return ShifterBase
