local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local Hitbox = require(Shared.Hitbox)

local AnxietyService = require(script.Parent.Parent.Services.AnxietyService)
local DamageService = require(script.Parent.Parent.Services.DamageService)
local ThoughtService = require(script.Parent.Parent.Services.ThoughtService)

local TitanHands = {}

local ARMS = { Left = true, Right = true }

function TitanHands.init(self: any)
	self.Mode = "Combat"
	self.Held = {} :: { [string]: Model }
	self.HeldInfo = {} :: { [string]: any }
	self.HandBusy = {} :: { [string]: boolean }
	self.HandReadyAt = {} :: { [string]: number }
end

local function alive(self: any): boolean
	local model: Model? = self.Model
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	return self.Shifted and not self.Transforming and model ~= nil and humanoid ~= nil and model.Parent ~= nil
end

local function setHand(self: any, arm: string, state: string)
	local model: Model? = self.Model
	if not model then
		return
	end
	model:SetAttribute("Hand_" .. arm, state)
	model:SetAttribute("HandT_" .. arm, Workspace:GetServerTimeNow())
end

local function burst(position: Vector3, size: number)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Position = position
	part.Parent = Workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(150, 12, 12))
	emitter.Size = NumberSequence.new(size * 0.5, 0)
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(size * 3, size * 8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -size * 8, 0)
	emitter.Rate = 0
	emitter.Parent = part
	emitter:Emit(40)
	Debris:AddItem(part, 2)
end

local function release(self: any, arm: string, keepFrozen: boolean?)
	local victim: Model? = self.Held[arm]
	local info = self.HeldInfo[arm]
	self.Held[arm] = nil
	self.HeldInfo[arm] = nil
	if not info then
		return
	end
	for _, connection in info.Connections do
		connection:Disconnect()
	end
	if info.Weld then
		info.Weld:Destroy()
	end
	if victim and victim.Parent then
		for part, saved in info.Saved do
			if part.Parent then
				part.CanCollide = saved.CanCollide
				part.Massless = saved.Massless
			end
		end
		victim:SetAttribute("GrabbedBy", nil)
		local humanoid = victim:FindFirstChildOfClass("Humanoid")
		local root = victim:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and not keepFrozen then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
		if root and root:IsA("BasePart") then
			pcall(root.SetNetworkOwnershipAuto, root)
		end
	end
end

function TitanHands.releaseAll(self: any)
	if not self.Held then
		return
	end
	for arm in ARMS do
		release(self, arm)
		self.HandBusy[arm] = false
		if self.Model then
			setHand(self, arm, "Idle")
		end
	end
end

local function findVictim(self: any, arm: string): Model?
	local settings = GameConfig.Titan.Grab
	local model: Model = self.Model
	local root = model.PrimaryPart
	local height: number = model:GetAttribute("TitanHeight") or 45
	if not root then
		return nil
	end
	local side = if arm == "Left" then -1 else 1
	local cframe = root.CFrame * CFrame.new(side * settings.HitSide * height, settings.HitY * height, -settings.HitForward * height)
	local size = settings.HitSize * height
	if GameConfig.DebugHitboxes then
		Hitbox.visualize(cframe, size, 0.4)
	end

	local best: Model? = nil
	local bestDistance = math.huge
	for _, candidate in Hitbox.getModels(cframe, size, { model }) do
		local humanoid = candidate:FindFirstChildOfClass("Humanoid")
		local candidateRoot = candidate:FindFirstChild("HumanoidRootPart")
		local other = Players:GetPlayerFromCharacter(candidate)
		local valid = humanoid ~= nil and humanoid.Health > 0 and candidateRoot ~= nil
			and not candidate:GetAttribute("GrabbedBy")
			and not candidate:GetAttribute("Eaten")
			and (settings.GrabTitans or not candidate:GetAttribute("IsTitan"))
			and (settings.GrabTeammates or not (other and self.Player.Team ~= nil and other.Team == self.Player.Team))
		if valid then
			local distance = (candidateRoot.Position - cframe.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = candidate, distance
			end
		end
	end
	return best
end

local function attach(self: any, arm: string, victim: Model): boolean
	local settings = GameConfig.Titan.Grab
	local model: Model = self.Model
	local hand = model:FindFirstChild(arm .. "Hand")
	local victimRoot = victim:FindFirstChild("HumanoidRootPart")
	local humanoid = victim:FindFirstChildOfClass("Humanoid")
	if not hand or not hand:IsA("BasePart") or not victimRoot or not victimRoot:IsA("BasePart") or not humanoid then
		return false
	end

	local saved = {}
	for _, descendant in victim:GetDescendants() do
		if descendant:IsA("BasePart") then
			saved[descendant] = { CanCollide = descendant.CanCollide, Massless = descendant.Massless }
			descendant.CanCollide = false
			descendant.Massless = true
		end
	end
	humanoid.PlatformStand = true

	local weld = Instance.new("Weld")
	weld.Name = "GrabWeld"
	weld.Part0 = hand
	weld.Part1 = victimRoot
	local offset: Vector3 = settings.HoldOffset
	local rotation: Vector3 = settings.HoldRotation
	weld.C0 = CFrame.new(offset * hand.Size)
		* CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
	weld.Parent = victimRoot

	victim:SetAttribute("GrabbedBy", self.Player.UserId)
	self.Held[arm] = victim
	local info = { Weld = weld, Saved = saved, Connections = {} }
	self.HeldInfo[arm] = info

	local titanRoot = model.PrimaryPart
	if titanRoot then
		pcall(titanRoot.SetNetworkOwner, titanRoot, self.Player)
	end

	table.insert(info.Connections, humanoid.Died:Connect(function()
		if self.Held[arm] == victim then
			release(self, arm, true)
			if alive(self) and not self.HandBusy[arm] then
				setHand(self, arm, "Idle")
			end
		end
	end))
	table.insert(info.Connections, victim.AncestryChanged:Connect(function(_, parent)
		if parent == nil and self.Held[arm] == victim then
			release(self, arm, true)
		end
	end))

	local victimPlayer = Players:GetPlayerFromCharacter(victim)
	if victimPlayer then
		AnxietyService.apply(victimPlayer, settings.AnxietyLevel, 8)
		ThoughtService.system(victimPlayer, "It has me... I can't move. *I can't move!*")
	end
	return true
end

function TitanHands.setMode(self: any, mode: string?)
	if not alive(self) then
		return
	end
	local newMode = mode or (if self.Mode == "Combat" then "Grab" else "Combat")
	if newMode ~= "Combat" and newMode ~= "Grab" then
		return
	end
	self.Mode = newMode
	self.Model:SetAttribute("TitanMode", newMode)
end

function TitanHands.grab(self: any, arm: string)
	local settings = GameConfig.Titan.Grab
	if not ARMS[arm] or not alive(self) or self.Mode ~= "Grab" then
		return
	end
	local now = os.clock()
	if self.Held[arm] or self.HandBusy[arm] or now < (self.HandReadyAt[arm] or 0) then
		return
	end
	local model: Model = self.Model
	self.HandBusy[arm] = true
	self.HandReadyAt[arm] = now + settings.Cooldown
	setHand(self, arm, "Reach")

	task.delay(settings.ReachTime * settings.ReachHit, function()
		if not alive(self) or self.Model ~= model then
			return
		end
		local victim = findVictim(self, arm)
		if victim then
			attach(self, arm, victim)
		end
	end)
	task.delay(settings.ReachTime, function()
		self.HandBusy[arm] = false
		if self.Model == model and alive(self) then
			setHand(self, arm, if self.Held[arm] then "Hold" else "Idle")
		end
	end)
end

function TitanHands.use(self: any, arm: string)
	local settings = GameConfig.Titan.Grab
	if not ARMS[arm] or not alive(self) then
		return
	end
	local victim: Model? = self.Held[arm]
	if not victim or self.HandBusy[arm] then
		return
	end
	local model: Model = self.Model
	local eating = self.Mode == "Grab"
	self.HandBusy[arm] = true
	setHand(self, arm, if eating then "Eat" else "Crush")

	local total = if eating then settings.EatTime else settings.CrushTime
	local hitAt = total * (if eating then settings.EatBite else settings.CrushHit)

	task.delay(hitAt, function()
		if self.Model ~= model or self.Held[arm] ~= victim then
			return
		end
		local hand = model:FindFirstChild(arm .. "Hand")
		local position = if hand and hand:IsA("BasePart") then hand.Position else victim:GetPivot().Position
		local height: number = model:GetAttribute("TitanHeight") or 45
		local victimHumanoid = victim:FindFirstChildOfClass("Humanoid")

		if eating then
			victim:SetAttribute("Eaten", true)
			release(self, arm, true)
			DamageService.damage(self.Player, victim, 1e6, { Source = "TitanEat" })
			for _, descendant in victim:GetDescendants() do
				if descendant:IsA("BasePart") or descendant:IsA("Decal") then
					descendant.Transparency = 1
				end
			end
			Debris:AddItem(victim, 1.5)
			local titanHumanoid = model:FindFirstChildOfClass("Humanoid")
			if titanHumanoid then
				titanHumanoid.Health = math.min(titanHumanoid.MaxHealth, titanHumanoid.Health + titanHumanoid.MaxHealth * settings.EatHeal)
			end
			burst(position, height * 0.03)
		else
			release(self, arm, true)
			DamageService.damage(self.Player, victim, 1e6, { Source = "TitanCrush" })
			burst(position, height * 0.04)
		end
		if victimHumanoid and victimHumanoid.Health > 0 then
			victimHumanoid.Health = 0
		end
	end)
	task.delay(total, function()
		self.HandBusy[arm] = false
		if self.Model == model and alive(self) then
			setHand(self, arm, if self.Held[arm] then "Hold" else "Idle")
		end
	end)
end

return TitanHands