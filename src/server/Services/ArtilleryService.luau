--[[
	ArtilleryService (server)
	The artillery signal tool. The client only says "fire at this spot"; the server checks
	range + cooldown, drops a flare marker, then lands the shells and applies damage.

	Drop a Tool named after the config (e.g. "FieldArtillery") into assets/tools to use
	your own model instead of the placeholder.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtilleryConfigs = require(Shared.Configs.ArtilleryConfigs)
local Hitbox = require(Shared.Hitbox)
local Remotes = require(Shared.Remotes)

local AnxietyService = require(script.Parent.AnxietyService)
local DamageService = require(script.Parent.DamageService)
local ThoughtService = require(script.Parent.ThoughtService)

local ArtilleryService = {}

local rng = Random.new()

local function markerFolder(): Folder
	local folder = Workspace:FindFirstChild("ArtilleryEffects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ArtilleryEffects"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

----------------------------------------------------------------------
-- Tool
----------------------------------------------------------------------

local function buildPlaceholderTool(config: any): Tool
	local tool = Instance.new("Tool")
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.Name = config.DisplayName
	tool.ToolTip = "Aim with the mouse, click to call a barrage"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 0.5, 1.6)
	handle.Color = Color3.fromRGB(70, 80, 55)
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local tip = Instance.new("Part")
	tip.Name = "Tip"
	tip.Size = Vector3.new(0.35, 0.35, 0.4)
	tip.Color = Color3.fromRGB(220, 50, 40)
	tip.Material = Enum.Material.Neon
	tip.CanCollide = false
	tip.Massless = true
	tip.CFrame = handle.CFrame * CFrame.new(0, 0, -1)
	tip.Parent = tool
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = tip
	weld.Parent = tip

	return tool
end

function ArtilleryService.createTool(artilleryId: string): Tool
	local config = ArtilleryConfigs[artilleryId]
	assert(config, "Unknown artillery id: " .. tostring(artilleryId))

	local toolsFolder = ServerStorage:FindFirstChild("Tools")
	local custom = toolsFolder and toolsFolder:FindFirstChild(artilleryId)
	local tool: Tool
	if custom and custom:IsA("Tool") then
		tool = custom:Clone()
	else
		tool = buildPlaceholderTool(config)
	end

	tool:SetAttribute("ArtilleryId", artilleryId)
	tool:SetAttribute("ReadyAt", 0) -- Workspace:GetServerTimeNow() when it can be used again
	return tool
end

function ArtilleryService.giveTool(player: Player, artilleryId: string)
	local backpack = player:WaitForChild("Backpack")
	ArtilleryService.createTool(artilleryId).Parent = backpack
end

----------------------------------------------------------------------
-- The strike
----------------------------------------------------------------------

local function groundAt(position: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local result = Workspace:Raycast(position + Vector3.new(0, 300, 0), Vector3.new(0, -700, 0), params)
	return result and result.Position or position
end

-- Only a drifting flare marks the spot (no circle on the ground: the danger zone is unknown,
-- and its size changes every strike).
local function makeMarker(center: Vector3, config: any, lifetime: number)
	if config.Flare == false then
		return
	end
	local folder = markerFolder()

	local flare = Instance.new("Part")
	flare.Name = "ArtilleryFlare"
	flare.Size = Vector3.one
	flare.Transparency = 1
	flare.Anchored = true
	flare.CanCollide = false
	flare.CanQuery = false
	flare.CanTouch = false
	flare.Position = center + Vector3.new(0, 1, 0)

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(235, 50, 40))
	smoke.Size = NumberSequence.new(3, 11)
	smoke.Lifetime = NumberRange.new(3, 5)
	smoke.Speed = NumberRange.new(10, 18)
	smoke.SpreadAngle = Vector2.new(8, 8)
	smoke.Rate = 24
	smoke.LightEmission = 0.4
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Parent = flare

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 60, 40)
	light.Range = 30
	light.Brightness = 3
	light.Parent = flare
	flare.Parent = folder

	Debris:AddItem(flare, lifetime)
end

local function streak(impact: Vector3, config: any, origin: Vector3?)
	local start = origin or (impact + Vector3.new(rng:NextNumber(-60, 60), 420, rng:NextNumber(-60, 60)))
	-- Every client plays the descending whistle (see ArtilleryEffects)
	Remotes.ArtilleryFx:FireAllClients({
		Kind = "Incoming",
		Id = config.Id,
		Position = impact,
		Start = start,
		Time = config.FallTime,
	})

	local part = Instance.new("Part")
	part.Name = "ArtilleryShell"
	part.Size = Vector3.new(0.6, 0.6, 7)
	part.Color = Color3.fromRGB(255, 210, 140)
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.lookAt(start, impact)
	part.Parent = markerFolder()
	TweenService:Create(part, TweenInfo.new(config.FallTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = CFrame.lookAt(impact, impact + (impact - start)),
	}):Play()
	Debris:AddItem(part, config.FallTime + 0.1)
end

local function explode(attacker: Player?, impact: Vector3, config: any, blast: number)
	-- The look and sound of the blast is drawn on every client (ArtilleryEffects); this
	-- function only does the gameplay: damage, knockback and fear.
	Remotes.ArtilleryFx:FireAllClients({
		Kind = "Impact",
		Id = config.Id,
		Position = impact,
		Time = blast,
	})
	local fear = config.Anxiety
	if fear then
		AnxietyService.applyRadius(impact, blast * fear.ImpactRadiusScale, fear.ImpactLevel, fear.ImpactDuration, 0.3)
	end

	for _, hit in Hitbox.getModelsInRadius(impact, blast) do
		local model = hit.Model
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			local falloff = 1 - math.clamp(hit.Distance / blast, 0, 1)
			local damage
			if model:GetAttribute("IsTitan") then
				damage = config.TitanDamage * (0.4 + 0.6 * falloff)
			else
				damage = config.DamageEdge + (config.DamageCenter - config.DamageEdge) * falloff
			end
			DamageService.damage(attacker, model, damage, { Source = "Artillery" })

			local victim = Players:GetPlayerFromCharacter(model)
			local root = model:FindFirstChild("HumanoidRootPart")
			if victim and root and root:IsA("BasePart") and not model:GetAttribute("IsTitan") then
				local away = (root.Position - impact) * Vector3.new(1, 0, 1)
				away = away.Magnitude > 0.1 and away.Unit or Vector3.zero
				local push = config.Knockback * falloff
				Remotes.Knockback:FireClient(victim, away * push + Vector3.new(0, push * 0.45, 0))
			end
		end
	end
end

local function pick(range: any): number
	if not range then
		return 1
	end
	return rng:NextNumber(range.Min, range.Max)
end

-- attacker may be nil (blimps): then nobody is credited and no team is spared.
-- origin: where the shells come from (a blimp's muzzle); nil = the sky above the target.
local function runStrike(attacker: Player?, config: any, center: Vector3, ignore: { Instance }, origin: Vector3?)
	-- Each strike gets its own random size: the whole pattern can be tight or sprawling, and
	-- every shell's blast is bigger or smaller than the nominal BlastRadius.
	local spread = config.SpreadRadius * pick(config.RadiusScale)
	local maxSpread = config.SpreadRadius * (config.RadiusScale and config.RadiusScale.Max or 1)
	local maxBlast = config.BlastRadius * (config.BlastScale and config.BlastScale.Max or 1)
	local total = config.Delay + config.Shells * config.ShellInterval + 2

	makeMarker(center, config, total)

	-- Warn everyone who could be in the danger zone, and start the dread building
	local dangerRadius = maxSpread + maxBlast + config.WarnExtraRadius
	for _, other in Players:GetPlayers() do
		local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - center).Magnitude <= dangerRadius then
			ThoughtService.system(other, config.WarnThoughts[rng:NextInteger(1, #config.WarnThoughts)])
		end
	end
	if config.Anxiety then
		AnxietyService.applyRadius(center, dangerRadius, config.Anxiety.WarnLevel, total, 0.5)
	end

	for i = 1, config.Shells do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = spread * math.sqrt(rng:NextNumber())
		local target = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local impact = groundAt(target, ignore)
		local blast = config.BlastRadius * pick(config.BlastScale)
		local landsAt = config.Delay + (i - 1) * config.ShellInterval

		task.spawn(function()
			task.wait(math.max(0, landsAt - config.FallTime))
			streak(impact, config, origin)
			task.wait(config.FallTime)
			explode(attacker, impact, config, blast)
		end)
	end
end

----------------------------------------------------------------------
-- Remote
----------------------------------------------------------------------

local function onCall(player: Player, tool: any, position: any)
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") or typeof(position) ~= "Vector3" then
		return
	end
	local config = ArtilleryConfigs[tool:GetAttribute("ArtilleryId")]
	local character = player.Character
	if not config or not character or tool.Parent ~= character or character:GetAttribute("IsTitan") then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	if position ~= position or position.Magnitude > 1e5 then -- NaN / absurd values
		return
	end

	local now = Workspace:GetServerTimeNow()
	if now < (tool:GetAttribute("ReadyAt") or 0) then
		return
	end
	local distance = ((position - root.Position) * Vector3.new(1, 0, 1)).Magnitude
	if distance < config.MinRange or distance > config.MaxRange then
		return
	end

	tool:SetAttribute("ReadyAt", now + config.Cooldown)
	local center = groundAt(position, { character })
	task.spawn(runStrike, player, config, center, { character })
end

-- Call a barrage from code (also used by the /strike admin command)
function ArtilleryService.strike(attacker: Player, artilleryId: string, position: Vector3, ignore: Instance?)
	local config = ArtilleryConfigs[artilleryId]
	if not config then
		return
	end
	local ignoreList = if ignore then { ignore } else {}
	local center = groundAt(position, ignoreList)
	task.spawn(runStrike, attacker, config, center, ignoreList)
end

-- A barrage with no caller (blimps, events). options: Origin (Vector3, where shells are fired
-- from), Shells (override the config's count), Attacker (Player, optional credit).
function ArtilleryService.barrage(artilleryId: string, position: Vector3, options: { Origin: Vector3?, Shells: number?, Attacker: Player? }?)
	local config = ArtilleryConfigs[artilleryId]
	if not config then
		return
	end
	options = options or {}
	if options.Shells then
		config = table.clone(config)
		config.Shells = options.Shells
	end
	local center = groundAt(position, {})
	task.spawn(runStrike, options.Attacker, config, center, {}, options.Origin)
end

function ArtilleryService.start()
	Remotes.ArtilleryCall.OnServerEvent:Connect(onCall)
end

return ArtilleryService
