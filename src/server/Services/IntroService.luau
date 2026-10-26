--[[
	IntroService (server)
	Starts cinematic intros (see Config.Intros and the client IntroController).
	  /armoredtitanintro      (also  :armoredtitanintro  typed in chat)
The server only picks the subject - whoever holds the intro's Titan - and tells every client to play it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local PlayerState = require(Shared.PlayerState)
local Remotes = require(Shared.Remotes)

local IntroService = {}

-- The holder of a Titan: a shifted player first, otherwise anyone assigned that Titan
local function findHolder(titanName: string): Player?
	local fallback: Player? = nil
	for _, player in Players:GetPlayers() do
		if PlayerState.get(player, "ShifterName") == titanName then
			if PlayerState.get(player, "Shifted") == true then
				return player
			end
			fallback = fallback or player
		end
	end
	return fallback
end

-- Returns (played, holderName?)
function IntroService.play(id: string): (boolean, string?)
	local config = GameConfig.Intros[id]
	if not config then
		return false, nil
	end
	local holder = findHolder(config.Titan)
	Remotes.Intro:FireAllClients({ Id = id, HolderUserId = if holder then holder.UserId else 0 })
	return true, if holder then holder.DisplayName else nil
end

return IntroService
