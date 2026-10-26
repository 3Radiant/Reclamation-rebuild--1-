--[[
	GunService (server)
	Authority on ammo, stance legality, fire rate, reloading, the real bullet
	simulation and damage. The client only requests things.

	Drop your own gun Tool into ServerStorage/Guns (assets/guns/ in the repo) named
	after the gun id (e.g. "Kar98k") and it'll be used instead of the placeholder.
	Give it a Handle with a "Muzzle" Attachment.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GunConfigs = require(Shared.Configs.GunConfigs)
local GunStates = require(Shared.Gun.GunStates)
local Ballistics = require(Shared.Gun.Ballistics)
local Spread = require(Shared.Gun.Spread)
local Remotes = require(Shared.Remotes)

local DamageService = require(script.Parent.DamageService)

local Stance = GunStates.Stance

local MAX_ORIGIN_DISTANCE = 12 -- muzzle must be this close to the shooter
local FIRE_INTERVAL_TOLERANCE = 0.9 -- forgive a little network jitter

local GunService = {}

local toolState = setmetatable({}, { __mode = "k" }) :: { [Tool]: { LastFire: number, ReloadToken: number } }
local activeBullets: { any } = {}

----------------------------------------------------------------------
-- Tools
----------------------------------------------------------------------

local function buildPlaceholderTool(config: any): Tool
	local tool = Instance.new("Tool")
	tool.RequiresHandle = true
	tool.CanBeDropped = false

	local look = config.Placeholder -- optional per-gun look (FlareGun); the default is a rifle
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = if look then look.Size else Vector3.new(0.3, 0.4, 3.5)
	handle.Color = if look then look.Color else Color3.fromRGB(60, 45, 35)
	handle.Material = if look then look.Material else Enum.Material.Wood
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0, -handle.Size.Z / 2)
	muzzle.Parent = handle

	tool.Name = config.DisplayName
	return tool
end

function GunService.createTool(gunId: string): Tool
	local config = GunConfigs[gunId]
	assert(config, "Unknown gun id: " .. tostring(gunId))

	local gunsFolder = ServerStorage:FindFirstChild("Guns")
	local custom = gunsFolder and gunsFolder:FindFirstChild(gunId)
	local tool: Tool
	if custom and custom:IsA("Tool") then
		tool = custom:Clone()
	else
		tool = buildPlaceholderTool(config)
	end

	tool:SetAttribute("GunId", gunId)
	tool:SetAttribute("Ammo", config.Ammo)
	tool:SetAttribute("Stance", Stance.Idle)
	tool:SetAttribute("Reloading", false)
	if config.Colors then
		tool:SetAttribute("FlareColor", config.DefaultColor)
	end

	toolState[tool] = { LastFire = 0, ReloadToken = 0 }

	-- Unequipping resets everything and cancels any reload in progress
	tool.Unequipped:Connect(function()
		local state = toolState[tool]
		if state then
			state.ReloadToken += 1
		end
		tool:SetAttribute("Reloading", false)
		tool:SetAttribute("Stance", Stance.Idle)
	end)

	return tool
end

function GunService.giveGun(player: Player, gunId: string)
	local backpack = player:WaitForChild("Backpack")
	GunService.createTool(gunId).Parent = backpack
end

----------------------------------------------------------------------
-- Validation: never trust the client
----------------------------------------------------------------------

local function validate(player: Player, tool: any): (Model?, BasePart?, any?, any?)
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") then
		return nil, nil, nil, nil
	end
	local character = player.Character
	if not character or tool.Parent ~= character or character:GetAttribute("IsTitan") then
		return nil, nil, nil, nil
	end
	local state = toolState[tool]
	local config = GunConfigs[tool:GetAttribute("GunId")]
	if not state or not config then
		return nil, nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil, nil
	end
	return character, root, config, state
end

----------------------------------------------------------------------
-- Damage
----------------------------------------------------------------------

local function baseDamage(config: any, part: BasePart): number
	local name = part.Name
	if name == "Head" then
		return config.HeadshotDamage
	end
	if name:find("Arm") or name:find("Leg") or name:find("Hand") or name:find("Foot") then
		return config.LimbDamage
	end
	return config.BodyDamage
end

local function applyHit(entry: any, result: RaycastResult)
	local model = result.Instance:FindFirstAncestorOfClass("Model")

	if not model then
		return
	end

	local damage = baseDamage(entry.Config, result.Instance)
	local falloff = entry.Config.DamageFalloff

	if falloff then
		local distance = (result.Position - entry.Origin).Magnitude
		local t = math.clamp((distance - falloff.Start) / math.max(1e-3, falloff.End - falloff.Start), 0, 1)
		damage *= 1 - (1 - falloff.MinScale) * t
	end
	
	local dealt = DamageService.damage(entry.Player, model, damage, {
		Source = "Gun",
		HitPart = result.Instance,
	})

	if dealt > 0 then
		Remotes.HitConfirm:FireClient(entry.Player, model) -- only the shooter sees it
	end
end

----------------------------------------------------------------------
-- Remote handlers
----------------------------------------------------------------------

local function onSetStance(player: Player, tool: any, requested: any)
	local character = validate(player, tool)
	if not character or typeof(requested) ~= "string" then
		return
	end
	if tool:GetAttribute("Reloading") then
		return
	end
	if not GunStates.canTransition(tool:GetAttribute("Stance"), requested) then
		return
	end
	tool:SetAttribute("Stance", requested)
end

local function onReload(player: Player, tool: any)
	local character, _, config, state = validate(player, tool)
	if not character then
		return
	end

	-- Shell-by-shell guns: pressing reload / clicking again while loading STOPS the reload
	if tool:GetAttribute("Reloading") then
		if config.ReloadStyle == "Single" and tool:GetAttribute("Ammo") > 0 then
			state.ReloadToken += 1
			tool:SetAttribute("Reloading", false)
		end
		return
	end
	if tool:GetAttribute("Ammo") >= config.Ammo then
		return
	end

	state.ReloadToken += 1
	local token = state.ReloadToken

	tool:SetAttribute("Stance", Stance.Idle)
	tool:SetAttribute("Reloading", true)

	if config.ReloadStyle == "Single" then
		task.spawn(function()
			local start = config.ReloadStartTime or 0
			tool:SetAttribute("ReloadEndsAt", Workspace:GetServerTimeNow() + start + config.ReloadShellTime)
			task.wait(start)
			while state.ReloadToken == token and tool.Parent and tool:GetAttribute("Ammo") < config.Ammo do
				tool:SetAttribute("ReloadEndsAt", Workspace:GetServerTimeNow() + config.ReloadShellTime)
				task.wait(config.ReloadShellTime)
				if state.ReloadToken ~= token or not tool.Parent then
					return -- stopped / unequipped / died
				end
				tool:SetAttribute("Ammo", tool:GetAttribute("Ammo") + 1)
			end
			if state.ReloadToken == token then
				tool:SetAttribute("Reloading", false)
			end
		end)
		return
	end

	tool:SetAttribute("ReloadEndsAt", Workspace:GetServerTimeNow() + config.ReloadTime)
	task.delay(config.ReloadTime, function()
		if state.ReloadToken ~= token or not tool.Parent then
			return
		end
		tool:SetAttribute("Ammo", config.Ammo)
		tool:SetAttribute("Reloading", false)
	end)
end

local function onFire(player: Player, tool: any, origin: any, direction: any, seed: any)
	local character, root, config, state = validate(player, tool)
	if not character or not root then
		return
	end
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	if direction.Magnitude < 0.01 or direction.Magnitude ~= direction.Magnitude then -- zero / NaN
		return
	end

	-- Design rules: only while Aiming, not reloading, with ammo
	if tool:GetAttribute("Stance") ~= Stance.Aiming then
		return
	end
	if tool:GetAttribute("Reloading") or tool:GetAttribute("Ammo") <= 0 then
		return
	end

	local now = os.clock()
	if now - state.LastFire < (60 / config.RPM) * FIRE_INTERVAL_TOLERANCE then
		return
	end
	if (origin - root.Position).Magnitude > MAX_ORIGIN_DISTANCE then
		return
	end

	state.LastFire = now
	tool:SetAttribute("Ammo", math.max(0, tool:GetAttribute("Ammo") - (config.AmmoPerShot or 1)))

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local unit = direction.Unit
	
	local shotSeed = if typeof(seed) == "number" and seed == seed and math.abs(seed) < 2 ^ 31 then math.floor(seed) else 0
	for _, pellet in Spread.pellets(config, unit, shotSeed) do
		table.insert(activeBullets, {
		Bullet = Ballistics.new(origin, pellet.Direction, config, params, pellet.SpeedScale),
			Config = config,
			Player = player,
			Origin = origin,
		})
	end

	-- Everyone else sees the shot (the shooter predicted theirs locally)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Remotes.GunBulletReplicate:FireClient(other, character, tool:GetAttribute("GunId"), origin, unit, tool:GetAttribute("FlareColor"), shotSeed)
		end
	end
end

-- Flare gun colour (V / /flare on the client)
local function onSetColor(player: Player, tool: any, colorName: any)
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") or typeof(colorName) ~= "string" then
		return
	end
	local config = GunConfigs[tool:GetAttribute("GunId")]
	if not config or not config.Colors or not config.Colors[colorName] then
		return
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if tool.Parent ~= player.Character and tool.Parent ~= backpack then
		return
	end
	tool:SetAttribute("FlareColor", colorName)
end

----------------------------------------------------------------------

function GunService.start()
	Remotes.GunSetColor.OnServerEvent:Connect(onSetColor)
	Remotes.GunSetStance.OnServerEvent:Connect(onSetStance)
	Remotes.GunReload.OnServerEvent:Connect(onReload)
	Remotes.GunFire.OnServerEvent:Connect(onFire)

	RunService.Heartbeat:Connect(function(dt)
		for i = #activeBullets, 1, -1 do
			local entry = activeBullets[i]
			local result = entry.Bullet:Step(dt)
			if result then
				applyHit(entry, result)
			end
			if entry.Bullet.Finished then
				table.remove(activeBullets, i)
			end
		end
	end)
end

return GunService
