--[[
	TeamService (server)
	Creates the Eldian and Marleyan Teams (Config.Teams) and moves players between them.

	  TeamService.set(player, "Eldian")   -> ok, reason   (balance rule: Config.Teams.MaxImbalance)
	  TeamService.getName(player)         -> "Eldian" | "Marleyan" | nil
	  TeamService.members("Marleyan")     -> { Player }
	  TeamService.opposite("Eldian")      -> "Marleyan"
	  TeamService.setRank(player, "Lieutenant")

	Spawns: any SpawnLocation (Neutral = false) whose TeamColor matches a team is that team's
	spawn - the project file creates EldianSpawn / MarleyanSpawn; add or move your own.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local PlayerState = require(Shared.PlayerState)
local Remotes = require(Shared.Remotes)

local ThoughtService = require(script.Parent.ThoughtService)
local MorphService = require(script.Parent.MorphService)

local TeamService = {}

local settings = GameConfig.Teams
local teams: { [string]: Team } = {}

function TeamService.getName(player: Player): string?
	local team = player.Team
	if team and teams[team.Name] == team then
		return team.Name
	end
	return nil
end

function TeamService.getTeam(name: string): Team?
	return teams[name]
end

function TeamService.members(name: string): { Player }
	local result = {}
	for _, player in Players:GetPlayers() do
		if TeamService.getName(player) == name then
			table.insert(result, player)
		end
	end
	return result
end

function TeamService.opposite(name: string): string
	for _, other in settings.Order do
		if other ~= name then
			return other
		end
	end
	return name
end

function TeamService.defaultRank(name: string): string
	local ranks = GameConfig.Ranks[name]
	return if ranks then ranks[#ranks] else ""
end

-- Case-insensitive match against the team's rank list. Returns the canonical rank or nil.
function TeamService.setRank(player: Player, text: string): string?
	local name = TeamService.getName(player)
	local ranks = name and GameConfig.Ranks[name]
	if not ranks then
		return nil
	end
	local wanted = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
	for _, rank in ranks do
		if rank:lower() == wanted then
			PlayerState.set(player, "Rank", rank)
			return rank
		end
	end
	return nil
end

function TeamService.set(player: Player, name: string): (boolean, string?)
	local team = teams[name]
	if not team then
		return false, "That isn't a side you can join."
	end
	if TeamService.getName(player) == name then
		return true, nil
	end

	-- Keep the sides roughly even
	local joining = #TeamService.members(name)
	local other = #TeamService.members(TeamService.opposite(name))
	if TeamService.getName(player) == TeamService.opposite(name) then
		other -= 1 -- they're leaving the other side
	end
	if joining - other >= settings.MaxImbalance then
		return false, ("%s has too many players right now. Join the other side."):format(settings[name].Display)
	end

	player.Team = team
	PlayerState.set(player, "Rank", TeamService.defaultRank(name))
	PlayerState.set(player, "Eliminated", false)

	MorphService.onTeamChanged(player, name)

	if settings.SetSpeakLanguage then
		PlayerState.set(player, "SpeakLanguage", settings[name].Language)
	end
	if settings.OnlyKnowOwnLanguage then
		PlayerState.set(player, "KnownLanguages", settings[name].Language)
	end
	return true, nil
end

function TeamService.start()
	for _, name in settings.Order do
		local config = settings[name]
		local team = Instance.new("Team")
		team.Name = name
		team.TeamColor = BrickColor.new(config.BrickColor)
		team.AutoAssignable = false
		team:SetAttribute("Lives", GameConfig.Round.Lives)
		team.Parent = Teams
		teams[name] = team

		-- Make sure each side has somewhere to spawn: any SpawnLocation (Neutral = false) with the
		-- team's colour counts. If the map has none, a pad is created at Config.Teams.<Name>.SpawnPosition.
		local hasSpawn = false
		for _, descendant in Workspace:GetDescendants() do
			if descendant:IsA("SpawnLocation") and not descendant.Neutral and descendant.TeamColor == team.TeamColor then
				hasSpawn = true
				break
			end
		end
		if not hasSpawn then
			local pad = Instance.new("SpawnLocation")
			pad.Name = name .. "Spawn"
			pad.Anchored = true
			pad.Neutral = false
			pad.TeamColor = team.TeamColor
			pad.AllowTeamChangeOnTouch = false
			pad.Size = Vector3.new(14, 1, 14)
			pad.Position = config.SpawnPosition
			pad.Transparency = 0.6
			pad.Parent = Workspace
		end
	end

	-- A leftover neutral spawn would let anyone spawn there; team spawns should win
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") and descendant.Neutral and descendant.Name == "SpawnLocation" then
			descendant:Destroy()
		end
	end

	-- The join menu / /team send the player's choice here. RoundService is told afterwards
	-- (it needs to spawn them), so it registers its callback instead of being required here.
	Remotes.TeamSelect.OnServerEvent:Connect(function(player: Player, name: any)
		if typeof(name) ~= "string" then
			return
		end
		local allowed = TeamService.canSwitch == nil or TeamService.canSwitch(player)
		if not allowed then
			ThoughtService.system(player, "I can't change sides in the middle of a battle.")
			return
		end
		local ok, reason = TeamService.set(player, name)
		if not ok then
			ThoughtService.system(player, reason or "I can't join that side.")
			return
		end
		if TeamService.onTeamChosen then
			TeamService.onTeamChosen(player)
		end
	end)
end

-- Set by RoundService
TeamService.canSwitch = nil :: ((Player) -> boolean)?
TeamService.onTeamChosen = nil :: ((Player) -> ())?

return TeamService
