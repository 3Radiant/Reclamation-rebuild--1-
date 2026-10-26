--[[
	EffectsController (client)
	Kill feedback. When the server confirms YOU killed something:

	  0.00s  hit: screen snaps to grey, contrast + brightness spike, blur, dark edge
	         vignette, and the camera FOV pinches in
	  0.07s  hold: the brightness drops below normal for a heavy "thud" feel
	  0.35s  release: everything eases back to normal (~1.1s total)

	Tune with Config.KillEffect (Enabled, TitanIntensity, SoundId).
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local Remotes = require(Shared.Remotes)

local CameraController = require(script.Parent.CameraController)

local player = Players.LocalPlayer
local settings = GameConfig.KillEffect

local EffectsController = {}

local colour: ColorCorrectionEffect
local blur: BlurEffect
local edges: { Frame } = {}
local token = 0

local function tween(object: Instance, seconds: number, style: Enum.EasingStyle, direction: Enum.EasingDirection, goal: { [string]: any })
	TweenService:Create(object, TweenInfo.new(seconds, style, direction), goal):Play()
end

local function buildVignette()
	local gui = Instance.new("ScreenGui")
	gui.Name = "KillVignette"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")

	-- { size, position, anchor, gradient rotation } : each edge is dark at the screen edge and clear inward
	local layout = {
		{ UDim2.new(1, 0, 0.3, 0), UDim2.new(0, 0, 0, 0), 90 },
		{ UDim2.new(1, 0, 0.3, 0), UDim2.new(0, 0, 0.7, 0), 270 },
		{ UDim2.new(0.2, 0, 1, 0), UDim2.new(0, 0, 0, 0), 0 },
		{ UDim2.new(0.2, 0, 1, 0), UDim2.new(0.8, 0, 0, 0), 180 },
	}
	for _, spec in layout do
		local frame = Instance.new("Frame")
		frame.Size = spec[1]
		frame.Position = spec[2]
		frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Active = false

		local gradient = Instance.new("UIGradient")
		gradient.Rotation = spec[3]
		gradient.Transparency = NumberSequence.new(0, 1)
		gradient.Parent = frame

		frame.Parent = gui
		table.insert(edges, frame)
	end
end

local function setEdges(seconds: number, transparency: number, style: Enum.EasingStyle)
	for _, frame in edges do
		tween(frame, seconds, style, Enum.EasingDirection.Out, { BackgroundTransparency = transparency })
	end
end

local function reset(instant: boolean)
	colour.Saturation, colour.Contrast, colour.Brightness = 0, 0, 0
	colour.TintColor = Color3.new(1, 1, 1)
	blur.Size = 0
	for _, frame in edges do
		frame.BackgroundTransparency = 1
	end
end

function EffectsController.killFlash(kind: string?)
	if not settings.Enabled then
		return
	end
	token += 1
	local mine = token
	local power = if kind == "Titan" then settings.TitanIntensity else 1

	if settings.SoundId ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = settings.SoundId
		sound.Volume = 0.8
		SoundService:PlayLocalSound(sound)
		task.delay(4, function()
			sound:Destroy()
		end)
	end

	CameraController.punch(-12 * power)

	-- Hit: snap to grey
	tween(colour, 0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
		Saturation = -1,
		Contrast = 0.55 * power,
		Brightness = 0.28 * power,
		TintColor = Color3.fromRGB(214, 220, 232),
	})
	tween(blur, 0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Size = 20 * power })
	setEdges(0.07, 0.15, Enum.EasingStyle.Quad)

	task.spawn(function()
		task.wait(0.07)
		if token ~= mine then
			return
		end

		-- Hold: brightness dips below normal so the flash feels heavy
		tween(colour, 0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, {
			Contrast = 0.3 * power,
			Brightness = -0.06,
		})
		tween(blur, 0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, { Size = 7 * power })
		task.wait(0.28)
		if token ~= mine then
			return
		end

		-- Release: ease back to normal
		tween(colour, 0.75, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut, {
			Saturation = 0,
			Contrast = 0,
			Brightness = 0,
			TintColor = Color3.new(1, 1, 1),
		})
		tween(blur, 0.75, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut, { Size = 0 })
		setEdges(0.75, 1, Enum.EasingStyle.Quint)
	end)
end

function EffectsController.start()
	colour = Instance.new("ColorCorrectionEffect")
	colour.Name = "KillFlashColor"
	colour.Parent = Lighting

	blur = Instance.new("BlurEffect")
	blur.Name = "KillFlashBlur"
	blur.Size = 0
	blur.Parent = Lighting

	buildVignette()
	reset(true)

	Remotes.KillConfirm.OnClientEvent:Connect(function(kind)
		EffectsController.killFlash(if typeof(kind) == "string" then kind else nil)
	end)
end

return EffectsController
