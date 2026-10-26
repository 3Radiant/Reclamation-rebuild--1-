--[[
	PlayerService (server)
	Joins, spawns and loadouts.

	Every spawn gets a rifle and an artillery signal. Admin chat commands (including
	/titan) live in ChatService.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local PlayerState = require(Shared.PlayerState)

local AdminService = require(script.Parent.AdminService)
local ArtilleryService = require(script.Parent.ArtilleryService)
local ChatService = require(script.Parent.ChatService)
local GunService = require(script.Parent.GunService)
local MorphService = require(script.Parent.MorphService)
local RigService = require(script.Parent.RigService)
local RoundService = require(script.Parent.RoundService)
local TeamService = require(script.Parent.TeamService)
local ShifterService = require(script.Parent.ShifterService)
local SpawnOverride = require(script.Parent.SpawnOverride)
local HitFilter = require(script.Parent.HitFilter)
local RagdollService = require(script.Parent.RagdollService)
local SlingService = require(script.Parent.SlingService)
local HelmetService = require(script.Parent.HelmetService)

local PlayerService = {}

local function onCharacterAdded(player: Player, character: Model)
	-- Shifting swaps Player.Character to a Titan. Only fresh human bodies get a loadout.
	if character:GetAttribute("IsTitan") or character:GetAttribute("LoadoutGiven") then
		return
	end

	HitFilter.protect(character)
	-- Normal players are R6 (Titans/shifters are R15). If we had to swap the body,
	-- CharacterAdded fires again for the R6 one and the loadout is given then.
	if RigService.ensureR6(player, character) then
		return
	end
	character:SetAttribute("LoadoutGiven", true)
	PlayerState.set(player, "Respawning", false)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and not humanoid:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = humanoid -- made on the server so animations replicate
	end

	-- Returning from Titan form: respawn where the Titan stood
	local override = SpawnOverride.take(player)
	if override then
		character:PivotTo(override.CFrame)
		if humanoid and override.HealthFraction then
			humanoid.Health = math.max(1, humanoid.MaxHealth * override.HealthFraction)
		end
	end

	RagdollService.watch(character)
	-- Human deaths cost the team a life (RoundService)
	if humanoid then
		humanoid.Died:Connect(function()
			RoundService.onHumanDied(player)
		end)
	end

	task.spawn(MorphService.onSpawn, player, character) -- remembered /shirt /pants

	GunService.giveGun(player, "Kar98k")
	local team = player.Team

	for _, gunId in (team and GameConfig.TeamGuns[team.Name]) or {} do
		GunService.giveGun(player, gunId)
	end

	for _, itemId in (team and GameConfig.TeamItems[team.Name]) or {} do
		HelmetService.give(player, itemId)
	end
	HelmetService.watch(character)

	if player.UserId == 69306753 then -- replace with your UserId
		ArtilleryService.giveTool(player, "FieldArtillery")
	end

	SlingService.watch(player, character)
end

local function onPlayerAdded(player: Player)
	AdminService.init(player)
	ChatService.initPlayer(player)

	player.CharacterAdded:Connect(function(character)
		task.spawn(onCharacterAdded, player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

function PlayerService.start()
	Players.CharacterAutoLoads = false -- RoundService decides when people spawn
	TeamService.start()
	RoundService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		ShifterService.remove(player)
		MorphService.remove(player)
	end)
end

return PlayerService
