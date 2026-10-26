--[[
	TitanFactory (server)
	Builds the Titan model for a shifter.

	1. CUSTOM MODEL: if ServerStorage/Titans/<TitanName> exists (drop models in assets/titans/,
	   named exactly like the TitanConfigs file) it is cloned and prepared: unanchored, scripts
	   stripped, Animator added, Nape added if missing, scaled to the canon height, and the
	   Humanoid's HipHeight + body scale values fixed so it stands on the floor. See
	   docs/CUSTOM_TITANS.md for how to build one.
	2. PLACEHOLDER: otherwise an R15 rig is built from a HumanoidDescription, recoloured and
	   scaled to the canon height (config.HeightMeters * StudsPerMeter), with a hidden Nape.

	Both paths end in the same finish step, so scaling behaves identically.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local TitanConfigs = require(Shared.Configs.TitanConfigs)

local TitanFactory = {}

----------------------------------------------------------------------
-- Scaling helpers
----------------------------------------------------------------------

-- Height (studs) of a part in world Y
local function halfWorldY(part: BasePart): number
	local _, _, _, _, _, _, r10, r11, r12 = part.CFrame:GetComponents()
	local s = part.Size
	return (math.abs(r10) * s.X + math.abs(r11) * s.Y + math.abs(r12) * s.Z) / 2
end

-- An R15 Humanoid stands on the floor using HipHeight = the gap between the BOTTOM of the
-- HumanoidRootPart (the hips) and the ground. After scaling we measure that gap from the
-- model itself: root bottom -> the soles of the feet. Only the feet count (stray low parts such
-- as a dangling accessory are ignored). Without this a scaled R15 sinks while it walks.
local function fixHipHeight(model: Model, humanoid: Humanoid)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local lowest = math.huge
	for _, name in { "LeftFoot", "RightFoot" } do
		local foot = model:FindFirstChild(name)
		if foot and foot:IsA("BasePart") then
			lowest = math.min(lowest, foot.Position.Y - halfWorldY(foot))
		end
	end
	if lowest == math.huge then -- no feet: fall back to the lowest solid part
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part ~= root and part.Name ~= "Nape" then
				lowest = math.min(lowest, part.Position.Y - halfWorldY(part))
			end
		end
	end
	if lowest == math.huge then
		return
	end
	local rootBottom = root.Position.Y - halfWorldY(root)
	humanoid.HipHeight = math.max(0, rootBottom - lowest)
end

local SCALE_VALUES = { "BodyDepthScale", "BodyHeightScale", "BodyWidthScale", "HeadScale" }

-- Make sure the Humanoid's scale NumberValues exist and record the scale we applied.
-- AutomaticScalingEnabled is turned OFF first so changing them can't rescale the model a
-- second time (we already scaled it with Model:ScaleTo).
local function writeScaleValues(humanoid: Humanoid, scale: number)
	humanoid.AutomaticScalingEnabled = false
	for _, name in SCALE_VALUES do
		local value = humanoid:FindFirstChild(name)
		if not value then
			value = Instance.new("NumberValue")
			value.Name = name
			value.Value = 1
			value.Parent = humanoid
		end
		if value:IsA("NumberValue") then
			value.Value = scale
		end
	end
	for _, name in { "BodyProportionScale", "BodyTypeScale" } do
		if not humanoid:FindFirstChild(name) then
			local value = Instance.new("NumberValue")
			value.Name = name
			value.Value = 0
			value.Parent = humanoid
		end
	end
end

local function addNape(model: Model)
	if model:FindFirstChild("Nape", true) then
		return
	end
	-- Nape weak point, welded behind the neck (model faces -Z, so back is +Z)
	local anchor = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model.PrimaryPart
	assert(anchor and anchor:IsA("BasePart"), "Titan has no torso to attach a Nape to")
	local offset = CFrame.new(0, anchor.Size.Y * 0.42, anchor.Size.Z * 0.5) -- proportional, so any scale works
	local nape = Instance.new("Part")
	nape.Name = "Nape"
	nape.Size = Vector3.new(anchor.Size.X * 0.7, anchor.Size.Y * 0.68, anchor.Size.Z * 0.8)
	nape.Transparency = 1
	nape.CanCollide = false
	nape.Massless = true
	nape.CFrame = anchor.CFrame * offset
	local weld = Instance.new("Weld") -- Weld (not WeldConstraint) so ScaleTo scales the offset
	weld.Part0 = anchor
	weld.Part1 = nape
	weld.C0 = offset
	weld.Parent = nape
	nape.Parent = model
end

-- Problems with a custom model, as readable strings (empty = good to go)
function TitanFactory.validate(model: Model): { string }
	local problems = {}
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		table.insert(problems, "no Humanoid")
	elseif humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		table.insert(problems, "Humanoid.RigType must be R15")
	end
	if not model:FindFirstChild("HumanoidRootPart") then
		table.insert(problems, "no HumanoidRootPart")
	end
	for _, name in { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg" } do
		if not model:FindFirstChild(name) then
			table.insert(problems, "missing R15 part " .. name)
		end
	end
	local upper = model:FindFirstChild("UpperTorso")
	if upper and not upper:FindFirstChild("Waist") then
		table.insert(problems, "UpperTorso has no Waist Motor6D (torso tilt will be skipped)")
	end
	local head = model:FindFirstChild("Head")
	if head and not head:FindFirstChild("Neck") then
		table.insert(problems, "Head has no Neck Motor6D (head tilt will be skipped)")
	end
	if not model:FindFirstChild("Nape", true) and not GameConfig.Shifting.CustomModels.AutoNape then
		table.insert(problems, "no part named Nape")
	end
	return problems
end

-- Logs the state of every custom model at server start
function TitanFactory.checkTemplates()
	local folder = ServerStorage:FindFirstChild("Titans")
	if not folder then
		return
	end
	for _, template in folder:GetChildren() do
		if template:IsA("Model") then
			local problems = TitanFactory.validate(template)
			if not TitanConfigs[template.Name] then
				table.insert(problems, "no TitanConfigs/" .. template.Name .. ".luau with that exact name, so it will never be used")
			end
			if #problems == 0 then
				print(("[TitanFactory] custom model '%s' OK"):format(template.Name))
			else
				warn(("[TitanFactory] custom model '%s': %s"):format(template.Name, table.concat(problems, "; ")))
			end
		end
	end
end

-- Shared by both paths: scale to the canon height, then make the Humanoid match.
local function finish(model: Model, config: any, fit: boolean)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.AutomaticScalingEnabled = false
	local before = model:GetScale()
	if fit then
		local targetHeight = config.HeightMeters * GameConfig.StudsPerMeter
		model:ScaleTo(before * targetHeight / model:GetExtentsSize().Y)
	end
	writeScaleValues(humanoid, model:GetScale())
	fixHipHeight(model, humanoid)
	humanoid.HipHeight += config.HipHeightOffset or 0
end

-- Very crude model used only if the R15 builder fails (no animations)
local function buildFallback(name: string): Model
	local model = Instance.new("Model")
	model.Name = name

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.Parent = model

	local body = Instance.new("Part")
	body.Name = "UpperTorso"
	body.Size = Vector3.new(2, 3, 1)
	body.CFrame = root.CFrame * CFrame.new(0, 1, 0)
	body.Parent = model
	local weld = Instance.new("Weld")
	weld.Part0, weld.Part1, weld.C0 = root, body, CFrame.new(0, 1, 0)
	weld.Parent = body

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.5, 1.5, 1.5)
	head.CFrame = root.CFrame * CFrame.new(0, 3, 0)
	head.Parent = model
	local headWeld = Instance.new("Weld")
	headWeld.Part0, headWeld.Part1, headWeld.C0 = root, head, CFrame.new(0, 3, 0)
	headWeld.Parent = head

	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = 2
	humanoid.Parent = model
	model.PrimaryPart = root
	return model
end

local function buildPlaceholder(config: any, name: string): Model
	local description = Instance.new("HumanoidDescription")
	description.Face = 0
	description.HeadColor = config.SkinColor
	description.TorsoColor = config.SkinColor
	description.LeftArmColor = config.SkinColor
	description.RightArmColor = config.SkinColor
	description.LeftLegColor = config.SkinColor
	description.RightLegColor = config.SkinColor

	local ok, built = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	local model: Model
	if ok and built then
		model = built
	else
		warn("[TitanFactory] R15 builder failed, using crude fallback:", built)
		model = buildFallback(name)
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant.Name ~= "HumanoidRootPart" then
				descendant.Color = config.SkinColor
				descendant.Material = config.Material
			end
		elseif descendant:IsA("Decal") or descendant:IsA("BaseScript") then
			descendant:Destroy() -- face decal / any default scripts
		end
	end

	addNape(model)

	return model
end

-- Returns a Titan Model (not parented). Yields.
function TitanFactory.create(titanName: string, player: Player): Model
	local config = TitanConfigs[titanName]
	assert(config, "Unknown Titan: " .. tostring(titanName))

	local titansFolder = ServerStorage:FindFirstChild("Titans")
	local template = titansFolder and titansFolder:FindFirstChild(titanName)
	local model: Model
	local custom = GameConfig.Shifting.CustomModels
	if template and template:IsA("Model") then
		model = template:Clone()
		if not model.PrimaryPart then
			model.PrimaryPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		end
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = false -- models saved while anchored would never move
			elseif custom.StripScripts and (descendant:IsA("Script") or descendant:IsA("LocalScript")) then
				descendant:Destroy()
			end
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		assert(humanoid and model.PrimaryPart, titanName .. " custom model needs a Humanoid and a HumanoidRootPart")
		assert(humanoid.RigType == Enum.HumanoidRigType.R15, titanName .. " must be an R15 model (set Humanoid.RigType = R15).")
		finish(model, config, custom.FitHeight)
		if custom.AutoNape then
			addNape(model)
		end
	else
		model = buildPlaceholder(config, player.Name)
		local placeholderHumanoid = model:FindFirstChildOfClass("Humanoid")
		if placeholderHumanoid then
			placeholderHumanoid.AutomaticScalingEnabled = false
		end
		finish(model, config, true)
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	assert(humanoid and model.PrimaryPart, "Titan model needs a Humanoid and a PrimaryPart (HumanoidRootPart)")
	assert(
		humanoid.RigType == Enum.HumanoidRigType.R15,
		titanName .. " must be an R15 model (set Humanoid.RigType = R15). Only normal players are R6."
	)

	if not humanoid:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = humanoid -- created on the server so animations replicate
	end
	humanoid.MaxHealth = config.MaxHealth
	humanoid.Health = config.MaxHealth
	humanoid.WalkSpeed = config.WalkSpeed
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = config.JumpHeight
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false

	if not model:FindFirstChild("Nape", true) then
		warn("[TitanFactory] " .. titanName .. " has no part named 'Nape' - nape hits won't register")
	end

	model.Name = player.Name
	model:SetAttribute("IsTitan", true)
	model:SetAttribute("TitanName", titanName)
	model:SetAttribute("TitanHeight", model:GetExtentsSize().Y)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("LastDamaged", 0)
	model:SetAttribute("DamageMultiplier", 1)
	return model
end

return TitanFactory
