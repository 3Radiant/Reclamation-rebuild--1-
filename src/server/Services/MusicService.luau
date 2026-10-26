--[[
	MusicService (server)
	A global music player for the whole server. Admin controlled, everyone hears it.

	How it works
	  * ONE Sound ("GlobalMusic", in SoundService, in the "Music" SoundGroup) is played by the
	    server, so every player hears it with the same properties (volume, speed...).
	  * The server owns the queue and the clock. Every change is published as JSON in
	    ReplicatedStorage/MusicState (attribute "State"). Clients use it to show the panel and
	    to re-sync the playback position (late joiners start in the right place).
	  * Players can lower or mute it for themselves (/mymusic <0-100>) without affecting anyone else.

	Controls (admins): the /music chat/command-bar command, or the panel. Both call the same functions:
	  play(id|name)  add(id|name ...)  skip  pause  resume  stop  clear  remove(n)
	  volume(0-100)  speed(x)  loop(off|track|queue)  shuffle  seek(seconds)

	Library for the panel: Shared/Configs/MusicLibrary.luau
]]

local ContentProvider = game:GetService("ContentProvider")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local MusicLibrary = require(Shared.Configs.MusicLibrary)
local MusicParse = require(Shared.MusicParse)
local Remotes = require(Shared.Remotes)

local AdminService = require(script.Parent.AdminService)
local ThoughtService = require(script.Parent.ThoughtService)

local settings = GameConfig.Music
local rng = Random.new()

local MusicService = {}

type Track = { Id: number, Title: string, By: string, Length: number? }

local sound: Sound
local stateValue: Configuration

local queue: { Track } = {}
local current: Track? = nil
local basePosition = 0 -- seconds into the track at baseTime
local baseTime = 0 -- Workspace:GetServerTimeNow() when basePosition was true
local paused = false
local volume = settings.DefaultVolume
local speed = 1
local loopMode = "Off" -- "Off" | "Track" | "Queue"
local shuffle = false
local revision = 0
local playToken = 0 -- bumps whenever a load is cancelled/replaced
local busy = false -- a track is loading

local titleCache: { [number]: string } = {}

----------------------------------------------------------------------
-- State publishing
----------------------------------------------------------------------

local function position(): number
	if not current then
		return 0
	end
	if paused then
		return basePosition
	end
	return basePosition + (Workspace:GetServerTimeNow() - baseTime) * speed
end

local function publish()
	revision += 1
	local state = {
		Rev = revision,
		Queue = queue,
		Current = current,
		BasePosition = basePosition,
		BaseTime = baseTime,
		Paused = paused,
		Volume = volume,
		Speed = speed,
		Loop = loopMode,
		Shuffle = shuffle,
	}
	stateValue:SetAttribute("State", HttpService:JSONEncode(state))
end

local function rebase(newPosition: number)
	basePosition = newPosition
	baseTime = Workspace:GetServerTimeNow()
end

local function tell(player: Player?, text: string)
	if player and player.Parent == Players then
		ThoughtService.system(player, text)
	end
end

local function announce(track: Track)
	if not settings.AnnounceTrack then
		return
	end
	for _, player in Players:GetPlayers() do
		ThoughtService.system(player, ("Now playing: **%s**"):format(track.Title))
	end
end

----------------------------------------------------------------------
-- Track info
----------------------------------------------------------------------

local function libraryTitle(id: number): string?
	for _, entry in MusicLibrary do
		if entry.Id == id then
			return entry.Title
		end
	end
	return nil
end

-- Yields. Returns the title, or nil + reason if it isn't an audio asset.
local function resolveTitle(id: number): (string?, string?)
	local fromLibrary = libraryTitle(id)
	if fromLibrary then
		return fromLibrary, nil
	end
	if titleCache[id] then
		return titleCache[id], nil
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(id, Enum.InfoType.Asset)
	end)
	if not ok or type(info) ~= "table" then
		return nil, "I couldn't find that asset."
	end
	if info.AssetTypeId ~= 3 then
		return nil, "That id isn't an audio asset."
	end
	titleCache[id] = info.Name
	return info.Name, nil
end

local function makeTrack(id: number, by: Player?): (Track?, string?)
	local title, reason = resolveTitle(id)
	if not title then
		return nil, reason
	end
	return { Id = id, Title = title, By = by and by.DisplayName or "Server" }, nil
end

----------------------------------------------------------------------
-- Playback core
----------------------------------------------------------------------

local startNext: () -> ()

-- Loads and starts `track` now. Skips on failure.
local function startTrack(track: Track, requester: Player?)
	playToken += 1
	local token = playToken
	busy = true

	sound:Stop()
	sound.SoundId = "rbxassetid://" .. track.Id
	sound.TimePosition = 0

	-- Wait for it to load (and learn its length)
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ sound })
		end)
	end)
	local started = os.clock()
	while token == playToken and not (sound.IsLoaded and sound.TimeLength > 0) and os.clock() - started < settings.LoadTimeout do
		task.wait(0.1)
	end
	if token ~= playToken then
		return -- something else took over while loading
	end
	if not (sound.IsLoaded and sound.TimeLength > 0) then
		tell(requester, ("'%s' wouldn't load (private audio?). Skipping."):format(track.Title))
		busy = false
		current = nil
		startNext()
		return
	end

	busy = false
	track.Length = sound.TimeLength
	current = track
	paused = false
	sound.PlaybackSpeed = speed
	sound.Volume = volume
	rebase(0)
	sound.TimePosition = 0
	sound:Play()
	publish()
	announce(track)
end

-- Finishes the current track (per loop mode) and moves on
startNext = function()
	if current and loopMode == "Queue" and #queue < settings.MaxQueue then
		table.insert(queue, { Id = current.Id, Title = current.Title, By = current.By })
	end
	if #queue == 0 then
		playToken += 1
		busy = false
		sound:Stop()
		current = nil
		paused = false
		basePosition = 0
		publish()
		return
	end
	local index = if shuffle then rng:NextInteger(1, #queue) else 1
	local nextTrack = table.remove(queue, index) :: Track
	startTrack(nextTrack, nil)
end

local function onTrackEnded()
	if current and loopMode == "Track" then
		rebase(0)
		sound.TimePosition = 0
		sound:Play()
		publish()
		return
	end
	startNext()
end

----------------------------------------------------------------------
-- Public controls. Each returns a message for the caller.
----------------------------------------------------------------------

-- target: a number, or text to look up in the library
local function resolveTarget(text: string): ({ number }, string?)
	local ids = MusicParse.ids(text, settings.MaxIdsPerCommand)
	if #ids > 0 then
		return ids, nil
	end
	local entry = MusicParse.search(MusicLibrary, text)
	if entry then
		return { entry.Id }, nil
	end
	return {}, "Give me an audio id (or part of a library title)."
end

function MusicService.add(by: Player?, text: string): string
	local ids, problem = resolveTarget(text)
	if problem then
		return problem
	end
	local added = {}
	for _, id in ids do
		if #queue >= settings.MaxQueue then
			break
		end
		local track, reason = makeTrack(id, by)
		if not track then
			tell(by, ("%d: %s"):format(id, reason or "failed"))
			continue
		end
		table.insert(queue, track)
		table.insert(added, track.Title)
	end
	if #added == 0 then
		return "Nothing was added."
	end
	if not current and not busy then
		task.spawn(startNext) -- nothing playing: the first queued track starts now
	else
		publish()
	end
	return "Queued: " .. table.concat(added, ", ")
end

function MusicService.play(by: Player?, text: string): string
	local ids, problem = resolveTarget(text)
	if problem then
		return problem
	end
	local track, reason = makeTrack(ids[1], by)
	if not track then
		return reason or "Couldn't play that."
	end
	-- Extra ids go to the front of the queue, in order
	for i = #ids, 2, -1 do
		local extra = makeTrack(ids[i], by)
		if extra then
			table.insert(queue, 1, extra)
		end
	end
	task.spawn(startTrack, track, by)
	return "Playing: " .. track.Title
end

function MusicService.skip(): string
	if not current then
		return "Nothing is playing."
	end
	local title = current.Title
	local keepLoop = loopMode
	if keepLoop == "Track" then
		loopMode = "Off" -- skipping should leave the looped track
	end
	startNext()
	loopMode = keepLoop
	publish()
	return "Skipped " .. title
end

function MusicService.pause(): string
	if not current or paused then
		return "Nothing to pause."
	end
	basePosition = position()
	paused = true
	sound:Pause()
	publish()
	return "Paused."
end

function MusicService.resume(): string
	if not current or not paused then
		return "Nothing to resume."
	end
	paused = false
	baseTime = Workspace:GetServerTimeNow()
	sound:Resume()
	publish()
	return "Resumed."
end

function MusicService.stop(): string
	table.clear(queue)
	playToken += 1
	busy = false
	sound:Stop()
	current = nil
	paused = false
	basePosition = 0
	publish()
	return "Music stopped and the queue cleared."
end

function MusicService.clear(): string
	table.clear(queue)
	publish()
	return "Queue cleared."
end

function MusicService.remove(index: number): string
	local removed = table.remove(queue, index)
	publish()
	return if removed then ("Removed %s from the queue."):format(removed.Title) else "No track at that position."
end

function MusicService.setVolume(percent: number): string
	volume = math.clamp(percent, 0, 100) / 100
	sound.Volume = volume
	publish()
	return ("Volume %d%%."):format(volume * 100)
end

function MusicService.setSpeed(value: number): string
	value = math.clamp(value, 0.5, 2)
	if current and not paused then
		rebase(position()) -- keep the clock continuous across the change
	end
	speed = value
	sound.PlaybackSpeed = value
	publish()
	return ("Speed %.2fx."):format(value)
end

function MusicService.setLoop(mode: string): string
	local lowered = mode:lower()
	if lowered == "track" or lowered == "song" or lowered == "one" then
		loopMode = "Track"
	elseif lowered == "queue" or lowered == "all" then
		loopMode = "Queue"
	else
		loopMode = "Off"
	end
	publish()
	return "Loop: " .. loopMode
end

function MusicService.toggleShuffle(): string
	shuffle = not shuffle
	publish()
	return "Shuffle " .. (if shuffle then "on." else "off.")
end

function MusicService.seek(seconds: number): string
	if not current or not current.Length then
		return "Nothing is playing."
	end
	seconds = math.clamp(seconds, 0, math.max(0, current.Length - 0.5))
	sound.TimePosition = seconds
	rebase(seconds)
	publish()
	return ("Seeked to %s."):format(MusicParse.time(seconds))
end

function MusicService.describeQueue(): string
	local lines = {}
	if current then
		table.insert(lines, ("Now: %s"):format(current.Title))
	end
	for i, track in queue do
		if i > 6 then
			table.insert(lines, ("...and %d more"):format(#queue - 6))
			break
		end
		table.insert(lines, ("%d. %s"):format(i, track.Title))
	end
	return if #lines > 0 then table.concat(lines, "  |  ") else "The queue is empty."
end

----------------------------------------------------------------------
-- Text command: /music <action> ...
----------------------------------------------------------------------

local USAGE =
	"/music play <id|name> | add <id|name ...> | skip | pause | resume | stop | clear | remove <n> | volume <0-100> | speed <0.5-2> | loop <off|track|queue> | shuffle | seek <secs> | queue | ui"

function MusicService.runCommand(player: Player, text: string): string
	local action, rest = text:match("^%s*(%S+)%s*(.*)$")
	if not action then
		return USAGE
	end
	action = action:lower()

	if action == "play" then
		return MusicService.play(player, rest)
	elseif action == "add" or action == "queue" and rest ~= "" then
		return MusicService.add(player, rest)
	elseif action == "queue" or action == "list" then
		return MusicService.describeQueue()
	elseif action == "skip" or action == "next" then
		return MusicService.skip()
	elseif action == "pause" then
		return MusicService.pause()
	elseif action == "resume" or action == "unpause" then
		return MusicService.resume()
	elseif action == "stop" then
		return MusicService.stop()
	elseif action == "clear" then
		return MusicService.clear()
	elseif action == "remove" or action == "rm" then
		return MusicService.remove(math.floor(tonumber(rest) or 0))
	elseif action == "volume" or action == "vol" then
		local value = tonumber(rest)
		return if value then MusicService.setVolume(value) else "Usage: /music volume <0-100>"
	elseif action == "speed" or action == "pitch" then
		local value = tonumber(rest)
		return if value then MusicService.setSpeed(value) else "Usage: /music speed <0.5-2>"
	elseif action == "loop" then
		return MusicService.setLoop(rest)
	elseif action == "shuffle" then
		return MusicService.toggleShuffle()
	elseif action == "seek" then
		local value = tonumber(rest)
		return if value then MusicService.seek(value) else "Usage: /music seek <seconds>"
	end

	-- Bare ids / names: "/music 123456789" queues it
	if #MusicParse.ids(text, 1) > 0 or MusicParse.search(MusicLibrary, text) then
		return MusicService.add(player, text)
	end
	return USAGE
end

----------------------------------------------------------------------

local function onControl(player: Player, action: any, a: any, b: any)
	if not AdminService.isAdmin(player) or typeof(action) ~= "string" then
		return
	end
	local message: string? = nil
	if action == "PlayId" and typeof(a) == "string" and #a < 300 then
		message = MusicService.play(player, a)
	elseif action == "AddId" and typeof(a) == "string" and #a < 300 then
		message = MusicService.add(player, a)
	elseif action == "Skip" then
		message = MusicService.skip()
	elseif action == "Pause" then
		message = MusicService.pause()
	elseif action == "Resume" then
		message = MusicService.resume()
	elseif action == "Stop" then
		message = MusicService.stop()
	elseif action == "Clear" then
		message = MusicService.clear()
	elseif action == "Remove" and typeof(a) == "number" then
		message = MusicService.remove(math.floor(a))
	elseif action == "Volume" and typeof(a) == "number" and a == a then
		MusicService.setVolume(a)
	elseif action == "Speed" and typeof(a) == "number" and a == a then
		MusicService.setSpeed(a)
	elseif action == "Loop" and typeof(a) == "string" then
		MusicService.setLoop(a)
	elseif action == "Shuffle" then
		MusicService.toggleShuffle()
	elseif action == "Seek" and typeof(a) == "number" and a == a then
		MusicService.seek(a)
	end
	if message then
		tell(player, message)
	end
end

function MusicService.start()
	local group = SoundService:FindFirstChild("Music")
	if not group then
		group = Instance.new("SoundGroup")
		group.Name = "Music"
		group.Volume = 1 -- players adjust their own copy of this (/mymusic)
		group.Parent = SoundService
	end

	sound = Instance.new("Sound")
	sound.Name = "GlobalMusic"
	sound.Volume = volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.SoundGroup = group :: SoundGroup
	sound.Parent = SoundService

	stateValue = ReplicatedStorage:FindFirstChild("MusicState") :: Configuration
	if not stateValue then
		stateValue = Instance.new("Configuration")
		stateValue.Name = "MusicState"
		stateValue.Parent = ReplicatedStorage
	end
	publish()

	Remotes.MusicControl.OnServerEvent:Connect(onControl)

	-- The clock: move on when the track has played to its end
	task.spawn(function()
		while true do
			task.wait(0.25)
			if current and current.Length and not paused and position() >= current.Length - 0.05 then
				onTrackEnded()
			end
		end
	end)
end

return MusicService
