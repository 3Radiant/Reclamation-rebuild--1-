--[[
	RoundService (server)
	Rounds, team lives, spawning and win conditions.

	Flow:  Intermission (pick teams, spawn in)  ->  Active (slow-mo intro, battle)  ->  Ending  ->  repeat

	  * Every team starts a round with Config.Round.Lives lives (300).
	  * A human death during a round costs the dead player's team one life, then they respawn
	    after RespawnTime - unless the team is at 0 lives: then they're eliminated for the round.
	  * A team LOSES when it has 0 lives AND everyone left on it is dead. The other team wins.
	    (Also: a team whose players all left, or time running out -> more lives wins.)
	  * Dying as a Titan costs nothing - you just turn back into a human (see ShifterBase).

	Spawning: CharacterAutoLoads is OFF; this service calls Player:LoadCharacter when allowed.

	State for clients (ReplicatedStorage/RoundState attributes):
	  Phase ("Intermission" | "Active" | "Ending" | "Disabled"), Round, PhaseEndsAt, SlowMoUntil,
	  Winner. Team lives live on the Team instances (attribute "Lives").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local PlayerState = require(Shared.PlayerState)

local MessageService = require(script.Parent.MessageService)
local ShifterService = require(script.Parent.ShifterService)
local TeamService = require(script.Parent.TeamService)
local ThoughtService = require(script.Parent.ThoughtService)

local settings = GameConfig.Round
local rng = Random.new()

local RoundService = {}

local stateValue: Configuration
local phase = "Intermission"
local roundNumber = 0
local startedWithBothTeams = false
local forcedStart = false
local forcedWinner: string? = nil -- "Eldian" | "Marleyan" | "Draw"
local respawnToken: { [Player]: number } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function setPhase(newPhase: string, duration: number?)
	phase = newPhase
	stateValue:SetAttribute("Phase", newPhase)
	stateValue:SetAttribute("PhaseEndsAt", if duration then now() + duration else 0)
end

local function lives(name: string): number
	local team = TeamService.getTeam(name)
	return if team then (team:GetAttribute("Lives") or 0) else 0
end

local function setLives(name: string, value: number)
	local team = TeamService.getTeam(name)
	if team then
		team:SetAttribute("Lives", math.max(0, math.floor(value)))
	end
end

local function isAlive(player: Player): boolean
	if PlayerState.get(player, "Respawning") == true then
		return true -- a new body is being loaded (e.g. after turning back from a Titan)
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function teamedPlayers(): { Player }
	local result = {}
	for _, player in Players:GetPlayers() do
		if TeamService.getName(player) then
			table.insert(result, player)
		end
	end
	return result
end

----------------------------------------------------------------------
-- Spawning
----------------------------------------------------------------------

local function load(player: Player)
	if player.Parent ~= Players or not TeamService.getName(player) then
		return
	end
	PlayerState.set(player, "Respawning", true)
	local ok, err = pcall(player.LoadCharacter, player)
	if not ok then
		warn("[RoundService] LoadCharacter failed:", err)
		PlayerState.set(player, "Respawning", false)
	end
end

local function canSpawnNow(player: Player): boolean
	local team = TeamService.getName(player)
	if not team then
		return false
	end
	if phase == "Active" and lives(team) <= 0 then
		return false -- eliminated
	end
	return true
end

-- Spawn now if the rules allow (used when someone picks a team / joins)
function RoundService.requestSpawn(player: Player)
	if isAlive(player) and player.Character then
		return
	end
	if canSpawnNow(player) then
		PlayerState.set(player, "Eliminated", false)
		task.spawn(load, player)
	else
		PlayerState.set(player, "Eliminated", true)
		ThoughtService.system(player, "My side has no lives left. I'll have to wait for the next battle.")
	end
end

local function scheduleRespawn(player: Player)
	respawnToken[player] = (respawnToken[player] or 0) + 1
	local token = respawnToken[player]
	task.delay(settings.RespawnTime, function()
		if respawnToken[player] ~= token or player.Parent ~= Players then
			return
		end
		if isAlive(player) and player.Character then
			return
		end
		RoundService.requestSpawn(player)
	end)
end

----------------------------------------------------------------------
-- Win conditions
----------------------------------------------------------------------

local winner: (string?) -> ()

local function checkWin()
	if phase ~= "Active" then
		return
	end
	local order = GameConfig.Teams.Order
	local out = {} -- teams that have lost
	for _, name in order do
		local members = TeamService.members(name)
		local anyAlive = false
		for _, player in members do
			if isAlive(player) and PlayerState.get(player, "Eliminated") ~= true then
				anyAlive = true
				break
			end
		end
		local noLivesAndDead = lives(name) <= 0 and not anyAlive
		local abandoned = startedWithBothTeams and #members == 0
		if noLivesAndDead or abandoned then
			table.insert(out, name)
		end
	end
	if #out == 0 then
		return
	elseif #out >= #order then
		winner("Draw")
	else
		winner(TeamService.opposite(out[1]))
	end
end

function RoundService.onHumanDied(player: Player)
	local team = TeamService.getName(player)
	PlayerState.set(player, "Deaths", PlayerState.get(player, "Deaths") + 1)
	if not team then
		return
	end

	if phase == "Active" then
		setLives(team, lives(team) - 1)
		if lives(team) <= 0 then
			PlayerState.set(player, "Eliminated", true)
			ThoughtService.system(player, "My side has no lives left... it's up to the others now.")
			checkWin()
			return
		end
	end
	scheduleRespawn(player)
end

----------------------------------------------------------------------
-- Round flow
----------------------------------------------------------------------

local function pickIntro(): { string }
	return settings.Intros[rng:NextInteger(1, #settings.Intros)]
end

local function beginRound()
	roundNumber += 1
	stateValue:SetAttribute("Round", roundNumber)
	stateValue:SetAttribute("Winner", "")
	forcedWinner = nil

	for _, name in GameConfig.Teams.Order do
		setLives(name, settings.Lives)
	end
	for _, player in Players:GetPlayers() do
		PlayerState.set(player, "Eliminated", false)
	end

	startedWithBothTeams = true
	for _, name in GameConfig.Teams.Order do
		if #TeamService.members(name) == 0 then
			startedWithBothTeams = false
		end
	end

	setPhase("Active", settings.MaxTime)
	stateValue:SetAttribute("SlowMoUntil", now() + settings.SlowMoDuration)

	-- Everyone starts fresh at their team's spawn (shifters are reset too)
	for _, player in teamedPlayers() do
		ShifterService.reset(player)
		task.spawn(load, player)
	end
	MessageService.broadcast(pickIntro(), { Style = "Round", Hold = 2.2 })
end

winner = function(name: string?)
	if phase ~= "Active" then
		return
	end
	local result = name or "Draw"
	stateValue:SetAttribute("Winner", result)
	setPhase("Ending", settings.EndScreenTime)
	MessageService.broadcast(settings.Victory[result] or settings.Victory.Draw, { Style = "Round", Hold = 2.8 })
end

local function leader(): string
	local a, b = GameConfig.Teams.Order[1], GameConfig.Teams.Order[2]
	if lives(a) > lives(b) then
		return a
	elseif lives(b) > lives(a) then
		return b
	end
	return "Draw"
end

local function loop()
	while true do
		-- Intermission: wait out the timer AND for enough players
		setPhase("Intermission", settings.IntermissionTime)
		stateValue:SetAttribute("SlowMoUntil", 0)
		forcedStart = false
		while true do
			task.wait(0.5)
			local ready = #teamedPlayers() >= settings.MinPlayers
			if forcedStart or (now() >= stateValue:GetAttribute("PhaseEndsAt") and ready) then
				break
			end
			if not ready then
				stateValue:SetAttribute("PhaseEndsAt", now() + settings.IntermissionTime) -- keep waiting
			end
		end

		beginRound()
		while phase == "Active" do
			task.wait(0.5)
			if forcedWinner then
				winner(forcedWinner)
			elseif now() >= stateValue:GetAttribute("PhaseEndsAt") then
				winner(leader())
			else
				checkWin()
			end
		end
		task.wait(settings.EndScreenTime)
	end
end

----------------------------------------------------------------------
-- Admin helpers (used by /round)
----------------------------------------------------------------------

function RoundService.forceStart()
	forcedStart = true
end

function RoundService.forceEnd(result: string)
	forcedWinner = result
end

function RoundService.setLives(name: string, value: number): boolean
	if not TeamService.getTeam(name) then
		return false
	end
	setLives(name, value)
	return true
end

function RoundService.status(): string
	local parts = {}
	for _, name in GameConfig.Teams.Order do
		table.insert(parts, ("%s %d lives (%d players)"):format(name, lives(name), #TeamService.members(name)))
	end
	return ("Round %d, %s. %s"):format(roundNumber, phase, table.concat(parts, " | "))
end

----------------------------------------------------------------------

function RoundService.start()
	stateValue = Instance.new("Configuration")
	stateValue.Name = "RoundState"
	stateValue:SetAttribute("Phase", "Intermission")
	stateValue:SetAttribute("Round", 0)
	stateValue:SetAttribute("PhaseEndsAt", 0)
	stateValue:SetAttribute("SlowMoUntil", 0)
	stateValue:SetAttribute("Winner", "")
	stateValue.Parent = ReplicatedStorage

	-- Joining a team spawns you (if allowed). Switching sides mid-battle is not.
	TeamService.canSwitch = function(player: Player): boolean
		if phase ~= "Active" then
			return true
		end
		return not (isAlive(player) and player.Character ~= nil and TeamService.getName(player) ~= nil)
	end
	TeamService.onTeamChosen = function(player: Player)
		-- Changed sides while alive in the lobby: start over at the new team's spawn
		if player.Character and phase ~= "Active" then
			task.spawn(load, player)
		else
			RoundService.requestSpawn(player)
		end
	end

	if not settings.Enabled then
		setPhase("Disabled", nil)
		return -- free respawns handled in onHumanDied -> scheduleRespawn
	end

	Players.PlayerRemoving:Connect(function(player)
		respawnToken[player] = nil
		task.defer(checkWin)
	end)
	task.spawn(loop)
end

return RoundService
