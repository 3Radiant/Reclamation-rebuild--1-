--[[
	ThoughtService (server)
	Sends inner-thought pop-ups to clients.

	  system(player, text)               text written by US (no filtering needed)
	  sendFiltered(author, text, targets) text typed by a PLAYER. Roblox requires player
	                                      text to be filtered before others can see it, so
	                                      it's filtered per recipient.
	kind: "Thought" (your own), "System" (info), "Overheard" (an admin seeing a player's /t)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local ThoughtService = {}

export type Target = { Player: Player, Kind: string, Source: string? }

function ThoughtService.system(player: Player, text: string)
	Remotes.Thought:FireClient(player, text, "System")
end

function ThoughtService.sendFiltered(author: Player, text: string, targets: { Target }): boolean
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, author.UserId, Enum.TextFilterContext.PrivateChat)
	end)

	local filterResult = nil
	if ok then
		filterResult = result
	elseif RunService:IsStudio() then
		warn("[ThoughtService] Text filtering unavailable in Studio, showing raw text:", result)
	else
		return false -- never show unfiltered player text in a live game
	end

	for _, target in targets do
		local shown = text
		if filterResult then
			local okFilter, filtered = pcall(function()
				return filterResult:GetNonChatStringForUserAsync(target.Player.UserId)
			end)
			if not okFilter then
				continue
			end
			shown = filtered
		end
		Remotes.Thought:FireClient(target.Player, shown, target.Kind, target.Source)
	end
	return true
end

return ThoughtService
