local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfigs = require(Shared.Configs.ItemConfigs)

local HelmetService = {}

type Worn = { Visual: Model, ItemId: string, Tool: Tool }
local worn: { [Model]: Worn } = {}

local DROP = { Script = true, LocalScript = true, ModuleScript = true, Sound = true, Animation = true }
local rng = Random.new()

local function buildPlaceholder(config: any): Tool
	local tool = Instance.new("Tool")
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	local look = config.Placeholder
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Shape = Enum.PartType.Ball
	handle.Size = look.Size
	handle.Color = look.Color
	handle.Material = look.Material
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	return tool
end

local function hasItem(player: Player, itemId: string): boolean
	local character = player.Character
	if character and worn[character] and worn[character].ItemId == itemId then
		return true
	end
	for _, container in { player:FindFirstChildOfClass("Backpack"), character } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("ItemId") == itemId then
					return true
				end
			end
		end
	end
	return false
end

-- Turn a tool's parts into a loose model (scripts removed, never blocks bullets)
local function cloneVisual(tool: Tool, name: string): Model?
	if not tool:FindFirstChild("Handle") then
		return nil
	end
	local copy = tool:Clone()
	local model = Instance.new("Model")
	model.Name = name
	for _, child in copy:GetChildren() do
		if DROP[child.ClassName] then
			child:Destroy()
		else
			child.Parent = model
		end
	end
	copy:Destroy()
	for _, descendant in model:GetDescendants() do
		if DROP[descendant.ClassName] then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
	model.PrimaryPart = model:FindFirstChild("Handle") :: BasePart
	return model
end

local function setToolVisible(tool: Tool, visible: boolean)
	for _, part in tool:GetDescendants() do
		if part:IsA("BasePart") then
			if visible then
				local original = part:GetAttribute("OrigTransparency")
				if original ~= nil then
					part.Transparency = original
					part:SetAttribute("OrigTransparency", nil)
				end
			else
				if part:GetAttribute("OrigTransparency") == nil then
					part:SetAttribute("OrigTransparency", part.Transparency)
				end
				part.Transparency = 1
			end
		end
	end
end

local function playAnimation(humanoid: Humanoid, id: string)
	if id == "" then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action2
	track:Play(0.1)
	track.Stopped:Once(function()
		animation:Destroy()
	end)
end

local function toggle(tool: Tool)
	local itemId: string = tool:GetAttribute("ItemId")
	local config = ItemConfigs[itemId]
	local character = tool.Parent
	if not config or not character or not character:IsA("Model") then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not player or not humanoid or humanoid.Health <= 0 or character:GetAttribute("IsTitan") then
		return
	end
	if tool:GetAttribute("Busy") then
		return
	end
	local entry = worn[character]

	-- take off
	if entry then
		if entry.Tool ~= tool then
			return
		end
		tool:SetAttribute("Busy", true)
		playAnimation(humanoid, config.TakeOffAnimation)
		task.wait(config.TakeOffTime)
		if worn[character] == entry then -- (a headshot may have knocked it off meanwhile)
			worn[character] = nil
			character:SetAttribute("HelmetOn", nil)
			entry.Visual:Destroy()
			tool:SetAttribute("Worn", nil)
			setToolVisible(tool, true)
		end
		tool:SetAttribute("Busy", nil)
		return
	end

	-- put on
	tool:SetAttribute("Busy", true)
	playAnimation(humanoid, config.EquipAnimation)
	task.wait(config.EquipTime)

	if tool.Parent ~= character or humanoid.Health <= 0 or worn[character] then
		tool:SetAttribute("Busy", nil)
		return
	end
	local spec = config.Worn
	local head = character:FindFirstChild(spec.Part)
	local visual = cloneVisual(tool, "WornHelmet")
	if not visual or not head or not head:IsA("BasePart") then
		tool:SetAttribute("Busy", nil)
		return
	end
	local handle = visual.PrimaryPart :: BasePart
	local weld = Instance.new("Weld")
	weld.Name = "WornWeld"
	weld.Part0 = head
	weld.Part1 = handle
	local r: Vector3 = spec.Rotation
	weld.C0 = CFrame.new(spec.Offset) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
	weld.Parent = handle
	visual.Parent = character

	worn[character] = { Visual = visual, ItemId = itemId, Tool = tool }
	character:SetAttribute("HelmetOn", true)
	tool:SetAttribute("Worn", true)
	tool:SetAttribute("Busy", nil)
	setToolVisible(tool, false)
	humanoid:UnequipTools() -- back to the inventory; click it again to take the helmet off
end

function HelmetService.createTool(itemId: string): Tool
	local config = ItemConfigs[itemId]
	assert(config, "Unknown item id: " .. tostring(itemId))
	local folder = ServerStorage:FindFirstChild("Tools")
	local custom = folder and folder:FindFirstChild(itemId)
	local tool: Tool = if custom and custom:IsA("Tool") then custom:Clone() else buildPlaceholder(config)
	tool.Name = config.DisplayName
	tool.CanBeDropped = false
	tool:SetAttribute("ItemId", itemId)
    tool.Activated:Connect(function()
		toggle(tool)
	end)
	tool.Equipped:Connect(function()
		setToolVisible(tool, tool:GetAttribute("Worn") ~= true)
	end)
	return tool
end

function HelmetService.give(player: Player, itemId: string)
	if hasItem(player, itemId) then
		return
	end
	HelmetService.createTool(itemId).Parent = player:WaitForChild("Backpack")
end

local function drop(character: Model, knocked: boolean)
	local entry = worn[character]
	if not entry then
		return
	end
	worn[character] = nil
	character:SetAttribute("HelmetOn", nil)
    if entry.Tool then
		entry.Tool:Destroy() -- the helmet is on the ground now; picking it up gives the Tool back
	end

	local config = ItemConfigs[entry.ItemId]
	local visual = entry.Visual
	local handle = visual.PrimaryPart
	if not handle or not visual.Parent then
		return
	end
	local weld = handle:FindFirstChild("WornWeld")
	if weld then
		weld:Destroy()
	end
	visual.Name = "DroppedHelmet"
	visual.Parent = Workspace
	for _, part in visual:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = part == handle
			part.Massless = false
		end
	end
	pcall(handle.SetNetworkOwner, handle, nil)

	local head = character:FindFirstChild("Head")
	local away = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
	if head and head:IsA("BasePart") and character.PrimaryPart then
		local flat = (head.Position - character.PrimaryPart.Position) * Vector3.new(1, 0, 1)
		if flat.Magnitude > 0.1 then
			away = flat.Unit + away * 0.5
		end
	end
	local speed = if knocked then config.KnockSpeed else 6
	handle.AssemblyLinearVelocity = away.Unit * speed + Vector3.new(0, speed * 0.6, 0)
	handle.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12))

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = config.DisplayName
	prompt.HoldDuration = config.PickupHold
	prompt.MaxActivationDistance = config.PickupDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = handle
	prompt.Triggered:Connect(function(picker)
		local pickerCharacter = picker.Character
		local humanoid = pickerCharacter and pickerCharacter:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or pickerCharacter:GetAttribute("IsTitan") then
			return
		end
		if hasItem(picker, entry.ItemId) then
			return
		end
		HelmetService.give(picker, entry.ItemId)
		visual:Destroy()
	end)
	Debris:AddItem(visual, config.DropLifetime)
end

-- DamageService asks this for every headshot on a human. true = the helmet took it.
function HelmetService.absorb(character: Model): boolean
	if not worn[character] then
		return false
	end
	drop(character, true)
	return true
end

function HelmetService.watch(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			drop(character, false)
		end)
	end
	character.Destroying:Connect(function()
		worn[character] = nil
	end)
end

return HelmetService