--[[
	AnxietyController (client)
	The anxiety effect. The server (AnxietyService) sends (level 0..1, seconds); this
	controller shows, for as long as it lasts:

	  * the screen draining toward greyscale (ColorCorrection)
	  * a dark vignette closing in from the edges, throbbing with a heartbeat
	  * the FOV pinching and a slight camera tremor on each beat
	  * an optional looping heartbeat sound (Config.Anxiety.HeartbeatSoundId)

	New hits don't stack up past the strongest level; they just extend the duration.
	Everything is tuned in Config.Anxiety.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local Remotes = require(Shared.Remotes)

local CameraController = require(script.Parent.CameraController)

local player = Players.LocalPlayer
local settings = GameConfig.Anxiety

local AnxietyController = {}

local colour: ColorCorrectionEffect
local blur: BlurEffect
local edges: { Frame } = {}
local heartbeat: Sound? = nil

local peak = 0 -- strongest requested level
local endsAt = 0 -- os.clock() when the requested effect is over
local level = 0 -- smoothed level actually on screen
local phase = 0 -- heartbeat phase (0..1)

-- Edge layout: size at level 0 / 1 are interpolated each frame
-- { position, anchor, horizontal?, gradient rotation }
local EDGES = {
	{ UDim2.new(0, 0, 0, 0), Vector2.new(0, 0), false, 90 }, -- top
	{ UDim2.new(0, 0, 1, 0), Vector2.new(0, 1), false, 270 }, -- bottom
	{ UDim2.new(0, 0, 0, 0), Vector2.new(0, 0), true, 0 }, -- left
	{ UDim2.new(1, 0, 0, 0), Vector2.new(1, 0), true, 180 }, -- right
}

local function buildVignette()
	local gui = Instance.new("ScreenGui")
	gui.Name = "AnxietyVignette"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 15
	gui.Parent = player:WaitForChild("PlayerGui")

	for _, spec in EDGES do
		local frame = Instance.new("Frame")
		frame.Position = spec[1]
		frame.AnchorPoint = spec[2]
		frame.BackgroundColor3 = Color3.fromRGB(6, 6, 9)
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Active = false
		frame.Visible = false

		local gradient = Instance.new("UIGradient")
		gradient.Rotation = spec[4]
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.45, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = frame

		frame.Parent = gui
		table.insert(edges, frame)
	end
end

local function setVignette(strength: number, reach: number)
	for index, frame in edges do
		frame.Visible = strength > 0.01
		if EDGES[index][3] then
			frame.Size = UDim2.new(reach * 0.6, 0, 1, 0)
		else
			frame.Size = UDim2.new(1, 0, reach, 0)
		end
		frame.BackgroundTransparency = 1 - strength
	end
end

local function update(dt: number)
	local now = os.clock()

	-- Where the level should be right now: hold at peak, then ease out over FadeOutTime
	local target = 0
	if now < endsAt then
		target = peak * math.clamp((endsAt - now) / settings.FadeOutTime, 0, 1)
	else
		peak = 0
	end

	-- Rise quickly, recover slowly
	local speed = if target > level then 4 else 1.4
	level += (target - level) * (1 - math.exp(-speed * dt))
	if level < 0.003 and target == 0 then
		level = 0
	end

	if level <= 0 then
		colour.Saturation, colour.Contrast, colour.Brightness = 0, 0, 0
		colour.TintColor = Color3.new(1, 1, 1)
		blur.Size = 0
		setVignette(0, 0)
		CameraController.setTremor(0)
		CameraController.setFovBias(0)
		if heartbeat and heartbeat.Playing then
			heartbeat:Stop()
		end
		return
	end

	-- Heartbeat: a sharp double thump ("lub-dub") that gets faster with the level
	local rate = settings.PulseRateMin + (settings.PulseRateMax - settings.PulseRateMin) * level
	phase = (phase + dt * rate) % 1
	local lub = math.max(0, 1 - math.abs(phase - 0.08) / 0.1)
	local dub = math.max(0, 1 - math.abs(phase - 0.30) / 0.1) * 0.7
	local beat = math.max(lub, dub)

	colour.Saturation = -settings.MaxSaturationLoss * level
	colour.Contrast = 0.12 * level
	colour.Brightness = -0.05 * level - 0.03 * beat * level
	colour.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(196, 206, 224), level)
	blur.Size = 3 * level * beat

	local strength = math.clamp(settings.VignetteStrength * (0.55 + 0.45 * level) * (0.85 + 0.15 * beat), 0, 1)
	setVignette(strength, settings.VignetteReach * level * (0.8 + 0.2 * beat) + 0.04)

	CameraController.setFovBias(-settings.FovNarrow * level * beat)
	CameraController.setTremor(settings.Tremor * level * (0.5 + 0.5 * beat))

	if heartbeat then
		if not heartbeat.Playing then
			heartbeat:Play()
		end
		heartbeat.Volume = 0.2 + 0.8 * level
		heartbeat.PlaybackSpeed = 0.8 + 0.6 * level
	end
end

-- level 0..1 for `seconds`. level 0 clears at once.
function AnxietyController.apply(newLevel: number, seconds: number)
	newLevel = math.clamp(newLevel, 0, 1)
	if newLevel <= 0 or seconds <= 0 then
		peak, endsAt = 0, 0
		level = math.min(level, 0.25) -- still eases out rather than snapping
		return
	end
	local now = os.clock()
	if now >= endsAt then
		peak = newLevel
	else
		peak = math.max(peak, newLevel)
	end
	endsAt = math.max(endsAt, now + math.max(seconds, settings.FadeOutTime))
end

function AnxietyController.getLevel(): number
	return level
end

function AnxietyController.start()
	colour = Instance.new("ColorCorrectionEffect")
	colour.Name = "AnxietyColor"
	colour.Parent = Lighting

	blur = Instance.new("BlurEffect")
	blur.Name = "AnxietyBlur"
	blur.Size = 0
	blur.Parent = Lighting

	buildVignette()

	if settings.HeartbeatSoundId ~= "" then
		heartbeat = Instance.new("Sound")
		heartbeat.Name = "AnxietyHeartbeat"
		heartbeat.SoundId = settings.HeartbeatSoundId
		heartbeat.Looped = true
		heartbeat.Volume = 0
		heartbeat.Parent = player:WaitForChild("PlayerGui")
	end

	Remotes.Anxiety.OnClientEvent:Connect(function(newLevel, seconds)
		if typeof(newLevel) == "number" and typeof(seconds) == "number" then
			AnxietyController.apply(newLevel, seconds)
		end
	end)

	RunService.RenderStepped:Connect(update)
end

return AnxietyController
