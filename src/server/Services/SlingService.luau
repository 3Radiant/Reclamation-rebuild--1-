local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GunConfigs = require(Shared.Configs.GunConfigs)
local ItemConfigs = require(Shared.Configs.ItemConfigs)

local SlingService = {}

local FOLDER = "Slung"
local DROP = { Script = true, LocalScript = true, ModuleScript = true, Sound = true, Animation = true }

local function slingOf(tool: Tool): { Part: string, Offset: Vector3, Rotation: Vector3 }?
    local config = GunConfigs[tool:GetAttribute("GunId") or ""] or ItemConfigs[tool:GetAttribute("ItemId") or ""]
	local base = config and config.Sling
	local part = tool:GetAttribute("SlingPart") or (base and base.Part)
	if not part then
		return nil
	end
	return {
		Part = part,
		Offset = tool:GetAttribute("SlingOffset") or (base and base.Offset) or Vector3.zero,
		Rotation = tool:GetAttribute("SlingRotation") or (base and base.Rotation) or Vector3.zero,
	}
end

local function buildVisual(tool: Tool, character: Model, sling: any): Model?
	local body = character:FindFirstChild(sling.Part)
	local handle = tool:FindFirstChild("Handle")
	if not body or not body:IsA("BasePart") or not handle or not handle:IsA("BasePart") then
		return nil
	end

	local copy = tool:Clone()
	local model = Instance.new("Model")
	model.Name = "Sling_" .. tool.Name
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

	local newHandle = model:FindFirstChild("Handle") :: BasePart
	local offset: Vector3 = sling.Offset
	local rotation: Vector3 = sling.Rotation
	local weld = Instance.new("Weld")
	weld.Name = "SlingWeld"
	weld.Part0 = body
	weld.Part1 = newHandle
	weld.C0 = CFrame.new(offset) * CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
	weld.Parent = newHandle
	model.PrimaryPart = newHandle
	model.Parent = character
	return model
end

function SlingService.refresh(player: Player, character: Model)
	local old = character:FindFirstChild(FOLDER)
	if old then
		old:Destroy()
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack or character:GetAttribute("IsTitan") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER
	folder.Parent = character
	for _, tool in backpack:GetChildren() do
        if tool:IsA("Tool") and not tool:GetAttribute("Worn") then
			local sling = slingOf(tool)
			if sling then
				local visual = buildVisual(tool, character, sling)
				if visual then
					visual.Parent = folder
				end
			end
		end
	end
end

function SlingService.watch(player: Player, character: Model)
	local backpack = player:WaitForChild("Backpack", 5)
	if not backpack then
		return
	end
	local queued = false
	local function requestRefresh()
		if queued then
			return
		end
		queued = true
		task.defer(function()
			queued = false
			if character.Parent and player.Character == character then
				SlingService.refresh(player, character)
			end
		end)
	end

	local connections = {
		backpack.ChildAdded:Connect(requestRefresh),
		backpack.ChildRemoved:Connect(requestRefresh),
	}
	character.Destroying:Connect(function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end)
	requestRefresh()
end

-- :sling <Gun> <x> <y> <z> [rx ry rz] [Part]
function SlingService.tune(player: Player, args: string): string
	local clean = {}
	for _, piece in string.split(args, " ") do
		if piece ~= "" then
			table.insert(clean, piece)
		end
	end
	local gunName = clean[1]
	if not gunName then
		return "Usage: :sling <Gun> <x> <y> <z> [rx ry rz] [Part]   e.g. :sling Kar98k 0 0.3 0.7 0 90 0 Torso"
	end
	local tool: Tool? = nil
	local backpack = player:FindFirstChildOfClass("Backpack")
	for _, container in { backpack, player.Character } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and (child.Name:lower() == gunName:lower() or tostring(child:GetAttribute("GunId")):lower() == gunName:lower()) then
					tool = child
				end
			end
		end
	end
	if not tool then
		return ("I'm not carrying a gun called %s."):format(gunName)
	end

	local numbers = {}
	local partName: string? = nil
	for index = 2, #clean do
		local number = tonumber(clean[index])
		if number then
			table.insert(numbers, number)
		else
			partName = table.concat(clean, " ", index)
			break
		end
	end
	if #numbers < 3 then
		return "I need at least x y z."
	end
	local offset = Vector3.new(numbers[1], numbers[2], numbers[3])
	local rotation = Vector3.new(numbers[4] or 0, numbers[5] or 0, numbers[6] or 0)
	tool:SetAttribute("SlingOffset", offset)
	tool:SetAttribute("SlingRotation", rotation)
	local current = slingOf(tool)
	tool:SetAttribute("SlingPart", partName or (current and current.Part) or "Torso")
	if player.Character then
		SlingService.refresh(player, player.Character)
	end
	return ("Sling = { Part = %q, Offset = Vector3.new(%s, %s, %s), Rotation = Vector3.new(%s, %s, %s) }   (paste into the gun's config)"):format(
		tool:GetAttribute("SlingPart"), offset.X, offset.Y, offset.Z, rotation.X, rotation.Y, rotation.Z
	)
end

return SlingService