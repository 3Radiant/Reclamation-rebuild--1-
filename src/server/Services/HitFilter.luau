local HitFilter = {}

local function isDecoration(part: BasePart): boolean
	return part:FindFirstAncestorWhichIsA("Accessory") ~= nil or part:FindFirstAncestorWhichIsA("Tool") ~= nil
end

function HitFilter.protect(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and isDecoration(descendant) then
			descendant.CanQuery = false
		end
	end
	-- Appearance loads a moment after the character appears, and tools come and go
	model.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			task.defer(function()
				if descendant.Parent and isDecoration(descendant) then
					descendant.CanQuery = false
				end
			end)
		end
	end)
end

return HitFilter