--[[
	MusicController (client)
	Keeps this player's copy of the global music in sync with the server (MusicService).

	  * Reads the queue/playback state the server publishes (ReplicatedStorage/MusicState).
	  * Re-syncs the replicated "GlobalMusic" Sound if it drifts, so players who join mid-song
	    start at the right second.
	  * Personal volume: /mymusic <0-100> only changes YOUR "Music" SoundGroup.

	MusicController.getState()      latest state table (or nil)
	MusicController.getPosition()   seconds into the current track, right now
	MusicController.onChanged(cb)   cb(state) on every server update
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local MusicController = {}

local state: any = nil
local listeners: { (any) -> () } = {}
local sound: Sound? = nil
local group: SoundGroup? = nil
local personalVolume = 1

function MusicController.getState(): any
	return state
end

function MusicController.getPosition(): number
	if not state or not state.Current then
		return 0
	end
	local position = state.BasePosition
	if not state.Paused then
		position += (Workspace:GetServerTimeNow() - state.BaseTime) * state.Speed
	end
	local length = state.Current.Length or math.huge
	return math.clamp(position, 0, length)
end

function MusicController.onChanged(callback: (any) -> ())
	table.insert(listeners, callback)
	if state then
		task.spawn(callback, state)
	end
end

function MusicController.getPersonalVolume(): number
	return personalVolume
end

-- 0..1, only for this player
function MusicController.setPersonalVolume(value: number)
	personalVolume = math.clamp(value, 0, 1)
	if group then
		group.Volume = personalVolume
	end
end

local function decode(json: any)
	if typeof(json) ~= "string" then
		return
	end
	local ok, result = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or typeof(result) ~= "table" then
		return
	end
	state = result
	for _, callback in listeners do
		task.spawn(callback, state)
	end
end

function MusicController.start()
	task.spawn(function()
		local stateValue = ReplicatedStorage:WaitForChild("MusicState", 30)
		if not stateValue then
			return
		end
		decode(stateValue:GetAttribute("State"))
		stateValue:GetAttributeChangedSignal("State"):Connect(function()
			decode(stateValue:GetAttribute("State"))
		end)
	end)

	task.spawn(function()
		group = SoundService:WaitForChild("Music", 30) :: SoundGroup?
		sound = SoundService:WaitForChild("GlobalMusic", 30) :: Sound?
		if group then
			group.Volume = personalVolume
		end

		-- Drift correction. Only touches our local copy of the Sound.
		while true do
			task.wait(0.5)
			local music = sound
			if music and state and state.Current and not state.Paused and music.IsLoaded and music.TimeLength > 0 then
				local expected = MusicController.getPosition()
				if music.IsPlaying and math.abs(music.TimePosition - expected) > 1.5 then
					music.TimePosition = expected
				end
			end
		end
	end)
end

return MusicController
