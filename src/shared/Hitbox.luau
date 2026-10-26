--[[
	Hitbox (shared)
	Box overlap queries for melee. Works with any model that has a Humanoid.
]]

local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Hitbox = {}

-- Returns every Model with a Humanoid overlapping the box (each model once).
function Hitbox.getModels(cframe: CFrame, size: Vector3, ignore: { Instance }?): { Model }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}

	local models = {}
	local seen = {}
	for _, part in Workspace:GetPartBoundsInBox(cframe, size, params) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not seen[model] and model:FindFirstChildOfClass("Humanoid") then
			seen[model] = true
			table.insert(models, model)
		end
	end
	return models
end

-- Every Model with a Humanoid within `radius` of a point, with the distance from the
-- point to that model's NEAREST surface (so a huge Titan is "close" when you hit its foot).
function Hitbox.getModelsInRadius(position: Vector3, radius: number, ignore: { Instance }?): { { Model: Model, Distance: number } }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}

	local nearest: { [Model]: number } = {}
	for _, part in Workspace:GetPartBoundsInRadius(position, radius, params) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			local localPoint = part.CFrame:PointToObjectSpace(position)
			local half = part.Size / 2
			local clamped = Vector3.new(
				math.clamp(localPoint.X, -half.X, half.X),
				math.clamp(localPoint.Y, -half.Y, half.Y),
				math.clamp(localPoint.Z, -half.Z, half.Z)
			)
			local distance = (localPoint - clamped).Magnitude
			if nearest[model] == nil or distance < nearest[model] then
				nearest[model] = distance
			end
		end
	end

	local list = {}
	for model, distance in nearest do
		table.insert(list, { Model = model, Distance = distance })
	end
	return list
end

-- Debug helper: draws the box for a moment (turn on with Config.DebugHitboxes)
function Hitbox.visualize(cframe: CFrame, size: Vector3, lifetime: number?)
	local folder = Workspace:FindFirstChild("Hitboxes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Hitboxes"
		folder.Parent = Workspace
	end

	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cframe
	part.Color = Color3.fromRGB(255, 60, 60)
	part.Transparency = 0.7
	part.Parent = folder
	Debris:AddItem(part, lifetime or 0.3)
end

return Hitbox
