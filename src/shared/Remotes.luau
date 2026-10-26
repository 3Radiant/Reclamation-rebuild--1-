--[[
	Remotes (shared)
	Every RemoteEvent in the game is listed here. The server creates them the first
	time this module is required; the client waits for them. Both sides just:
		local Remotes = require(Shared.Remotes)
		Remotes.GunFire:FireServer(...)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	-- Guns
	"GunSetStance", -- client -> server (tool, stance)
	"GunFire", -- client -> server (tool, origin, direction)
	"GunReload", -- client -> server (tool)
	"GunSetColor", -- client -> server (tool, colourName): flare gun colour
	"GunBulletReplicate", -- server -> clients (shooterCharacter, gunId, origin, direction, colorName)

	-- Shifters
	"ShiftToggle", -- client -> server: shift / deshift
	"TitanM1", -- client -> server: melee swing
	"TitanAbility", -- client -> server (abilityName)
	"TitanLook", -- client -> server (pitchRadians): so everyone sees the Titan tilt its torso / head
	"TitanMode", -- client -> server: toggle Combat / Grab
	"TitanHand", -- client -> server (action "Grab" | "Use", arm "Left" | "Right")

	-- Combat feedback
	"Knockback", -- server -> client (velocity)
	"KillConfirm", -- server -> attacker (kind: "Human" | "Titan")
	"HitConfirm", -- server -> shooter (model): a valid hit landed, so flash it on their screen

	-- Artillery
	"ArtilleryCall", -- client -> server (tool, targetPosition)
	"ArtilleryFx", -- server -> all clients ({ Kind = "Incoming" | "Impact", Id, Position, Start, Time })

	-- Music
	"MusicControl", -- client -> server (action, a, b): admin music panel buttons

	-- Yells (text + portrait card at the bottom of the screen)
	"Yell", -- server -> client ({ Text, Name, UserId, Language })

	-- Shifting visuals
	"ShiftFx", -- server -> all clients ({ Position, Height, UserId }): lightning, flash, sound

	-- Teams / rounds / announcements
	"TeamSelect", -- client -> server (teamName)
	"ServerMessage", -- server -> clients ({ Lines = {string}, Hold = seconds, Style = "Round" | "Alert" })

	-- Cinematic intros (typewriter text + camera), see IntroController
	"Intro", -- server -> all clients ({ Id, HolderUserId })

	-- Anxiety effect
	"Anxiety", -- server -> client (level 0..1, durationSeconds). level 0 = clear

	-- Inner thoughts / chat
	"Thought", -- server -> client (text, kind, source)
	"ChatCommand", -- client -> server (commandName, argsText)
}

local folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

local remotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	remotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return remotes
