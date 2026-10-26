--[[
	AdminService (server)
	Who is an admin, and finding players by name for admin commands.

	Admin = the game owner (or owner of the owning group), anyone in Config.Admins,
	and EVERYONE while testing in Studio (Config.AdminsInStudio).
	The result is stored on the Player as the "IsAdmin" attribute so clients can see it
	(for display only - the server always re-checks before doing anything).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local PlayerState = require(Shared.PlayerState)

local AdminService = {}

local GROUP_OWNER_RANK = 255

local function compute(player: Player): boolean
	if RunService:IsStudio() and GameConfig.AdminsInStudio then
		return true
	end
	if table.find(GameConfig.Admins, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	elseif game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(function()
			return player:GetRankInGroup(game.CreatorId)
		end)
		return ok and rank >= GROUP_OWNER_RANK
	end
	return false
end

-- Call once when a player joins (may yield for group lookups)
function AdminService.init(player: Player)
	PlayerState.set(player, "IsAdmin", compute(player))
end

function AdminService.isAdmin(player: Player): boolean
	return PlayerState.get(player, "IsAdmin") == true
end

-- "me" | "all" | a name / display-name prefix. Returns every match.
function AdminService.resolveTargets(requester: Player, text: string): { Player }
	local query = text:lower()
	if query == "me" then
		return { requester }
	elseif query == "all" then
		return Players:GetPlayers()
	end

	local matches = {}
	for _, candidate in Players:GetPlayers() do
		if candidate.Name:lower():sub(1, #query) == query or candidate.DisplayName:lower():sub(1, #query) == query then
			table.insert(matches, candidate)
		end
	end
	return matches
end

return AdminService
