--[[
	PlayerState (shared) - the "global state table".
	Server-owned facts about a player live as attributes on the Player, so they
	replicate to everyone automatically. The server writes, anyone reads/observes.

	Keys
	  Shifted       bool    currently in Titan form
	  Transforming  bool    mid-transformation (biting hand); movement is locked
	  ShifterName   string  which Titan this player wields ("" = none)
	  ShiftReadyAt  number  workspace:GetServerTimeNow() when they can shift again
	  ShiftsLeft    number  transformations remaining
	  SpeakLanguage string  language your chat messages are written in
	  KnownLanguages string comma list of languages you understand, e.g. "Eldian,Marleyan"
	  IsAdmin       bool    set by the server (AdminService)
	  Rank          string  leaderboard rank, set by TeamService / the /rank command
	  Kills/Deaths  number  leaderboard stats
	  Eliminated    bool    this round your team has no lives left and you are out
	  Respawning    bool    the server is loading your next body
]]

local PlayerState = {}

PlayerState.Defaults = {
	Shifted = false,
	Transforming = false,
	ShifterName = "",
	ShiftReadyAt = 0,
	ShiftsLeft = 0,
	SpeakLanguage = "Eldian",
	KnownLanguages = "Eldian,Marleyan",
	IsAdmin = false,
	Rank = "",
	Kills = 0,
	Deaths = 0,
	Eliminated = false, -- your team ran out of lives this round
	Respawning = false, -- server is loading your next body (so you don't count as dead)
}

function PlayerState.get(player: Player, key: string): any
	local value = player:GetAttribute(key)
	if value == nil then
		return PlayerState.Defaults[key]
	end
	return value
end

-- Server only (client-side attributes don't replicate)
function PlayerState.set(player: Player, key: string, value: any)
	player:SetAttribute(key, value)
end

-- Calls callback now and whenever the key changes. Returns the connection.
function PlayerState.observe(player: Player, key: string, callback: (any) -> ())
	task.spawn(callback, PlayerState.get(player, key))
	return player:GetAttributeChangedSignal(key):Connect(function()
		callback(PlayerState.get(player, key))
	end)
end

return PlayerState
