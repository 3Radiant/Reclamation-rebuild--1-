--[[
	BossBarService (server)
	Boss bars: a big health bar at the top centre of EVERY player's screen, showing the
	live health of a player, a Titan, or any NPC with a Humanoid.

		BossBarService.add(target, "Arrax, The Plated Sentinel")   -- target: Player or Model
		BossBarService.remove(target)
		BossBarService.clear()

	A bar bound to a Player follows them across respawns and shifting (it always shows
	whatever body they are in). Bars are stored as ObjectValues in ReplicatedStorage/BossBars,
	so players who join later see them automatically. Removed when the target is destroyed or leaves.
	Chat: /bossbar <player|npc name> [title], /bossbar off [name|all]
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BossBarService = {}

local folder: Folder
local byTarget: { [Instance]: ObjectValue } = {}
local nextId = 0

local function getFolder(): Folder
	if not folder then
		folder = ReplicatedStorage:FindFirstChild("BossBars") :: Folder
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "BossBars"
			folder.Parent = ReplicatedStorage
		end
	end
	return folder
end

function BossBarService.remove(target: Instance): boolean
	local value = byTarget[target]
	if not value then
		return false
	end
	byTarget[target] = nil
	value:Destroy()
	return true
end

function BossBarService.clear()
	for target in byTarget do
		BossBarService.remove(target)
	end
end

function BossBarService.has(target: Instance): boolean
	return byTarget[target] ~= nil
end

function BossBarService.add(target: Instance, title: string?)
	assert(target:IsA("Player") or target:IsA("Model"), "Boss bar target must be a Player or a Model")
	BossBarService.remove(target) -- re-adding just retitles it

	nextId += 1
	local value = Instance.new("ObjectValue")
	value.Name = tostring(nextId) -- names sort bars in the order they were added
	value.Value = target
	value:SetAttribute("Title", title)
	value.Parent = getFolder()
	byTarget[target] = value

	-- Models: drop the bar when the model is destroyed. Players: when they leave (see below).
	if target:IsA("Model") then
		target.AncestryChanged:Connect(function()
			if not target:IsDescendantOf(game) then
				BossBarService.remove(target)
			end
		end)
	end
end

-- "me"-style lookup used by the chat command: players first, then NPC/Titan models by name
function BossBarService.find(name: string): Instance?
	local lowered = name:lower()
	for _, player in Players:GetPlayers() do
		if player.Name:lower():sub(1, #lowered) == lowered or player.DisplayName:lower():sub(1, #lowered) == lowered then
			return player
		end
	end
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("Model") and descendant.Name:lower() == lowered and descendant:FindFirstChildOfClass("Humanoid") then
			return descendant
		end
	end
	return nil
end

function BossBarService.start()
	getFolder()
	Players.PlayerRemoving:Connect(function(player)
		BossBarService.remove(player)
	end)
end

return BossBarService
