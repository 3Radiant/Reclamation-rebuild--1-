--[[
	ShiftEffects (client)
	The transformation spectacle, drawn on every client when the server sends Remotes.ShiftFx:

	  * A huge lightning bolt from the sky strikes the shifter (jagged, forked, flickering),
	    with a ground shockwave, a blinding light and camera shake.
	  * Screen sequence (full strength for the shifter, fading with distance for others):
	        yellow flash  ->  white / black "impact frames"  ->  yellow  ->  eases back to normal
	    The yellow phases use a ColorCorrection; the hard white/black frames use an overlay.
	  * Sounds: Config.Shifting.Sounds.Shift (your Titan-shift sound) + Thunder.

	Tune in Config.Shifting (Lightning, FlashRange, Sounds).
]]

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local Remotes = require(Shared.Remotes)

local CameraController = require(script.Parent.CameraController)

local player = Players.LocalPlayer
local settings = GameConfig.Shifting
local rng = Random.new()

local ShiftEffects = {}

local YELLOW = Color3.fromRGB(255, 214, 40)
local PALE_YELLOW = Color3.fromRGB(255, 240, 150)

local colour: ColorCorrectionEffect
local blur: BlurEffect
local overlay: Frame
local folder: Folder
local token = 0

local function tween(object: Instance, seconds: number, style: Enum.EasingStyle, direction: Enum.EasingDirection, goal: { [string]: any })
	TweenService:Create(object, TweenInfo.new(seconds, style, direction), goal):Play()
end

local function distanceTo(position: Vector3): number
	local camera = Workspace.CurrentCamera
	return if camera then (camera.CFrame.Position - position).Magnitude else math.huge
end

----------------------------------------------------------------------
-- Screen sequence
----------------------------------------------------------------------

-- power 0..1 scales every effect (1 = the shifter themself)
local function screenSequence(power: number)
	token += 1
	local mine = token

	local function alive(): boolean
		return token == mine
	end
	local function hardFrame(color: Color3, alpha: number)
		overlay.BackgroundColor3 = color
		overlay.BackgroundTransparency = 1 - alpha
	end

	task.spawn(function()
		-- 1. Yellow flash: the whole screen snaps to saturated yellow
		colour.Saturation = 0.6 * power
		colour.TintColor = Color3.new(1, 1, 1):Lerp(YELLOW, power)
		colour.Brightness = 0.55 * power
		colour.Contrast = 0.5 * power
		blur.Size = 22 * power
		hardFrame(YELLOW, 0.55 * power)
		task.wait(0.13)
		if not alive() then
			return
		end

		-- 2. Impact frames: white / black hard cuts
		hardFrame(Color3.new(1, 1, 1), power)
		colour.Saturation = -1
		colour.Contrast = 1 * power
		task.wait(0.06)
		if not alive() then
			return
		end
		hardFrame(Color3.new(0, 0, 0), power)
		colour.Brightness = -0.5 * power
		task.wait(0.07)
		if not alive() then
			return
		end
		hardFrame(Color3.new(1, 1, 1), power)
		colour.Brightness = 0.8 * power
		task.wait(0.05)
		if not alive() then
			return
		end
		hardFrame(Color3.new(0, 0, 0), power * 0.9)
		colour.Brightness = -0.4 * power
		task.wait(0.06)
		if not alive() then
			return
		end

		-- 3. Back to yellow...
		overlay.BackgroundTransparency = 1
		colour.Saturation = 0.9 * power
		colour.TintColor = Color3.new(1, 1, 1):Lerp(PALE_YELLOW, power)
		colour.Brightness = 0.35 * power
		colour.Contrast = 0.35 * power
		blur.Size = 14 * power
		task.wait(0.22)
		if not alive() then
			return
		end

		-- 4. ...and ease out to normal, like the kill flash
		tween(colour, 1.7, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut, {
			Saturation = 0,
			Contrast = 0,
			Brightness = 0,
			TintColor = Color3.new(1, 1, 1),
		})
		tween(blur, 1.5, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut, { Size = 0 })
	end)
end

----------------------------------------------------------------------
-- Lightning
----------------------------------------------------------------------

local function segment(a: Vector3, b: Vector3, thickness: number, color: Color3, transparency: number): Part
	local length = (b - a).Magnitude
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Size = Vector3.new(thickness, thickness, length)
	part.CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -length / 2)
	part.Parent = folder
	return part
end

-- A jagged path from `top` to `bottom`; the zig-zag shrinks toward the ground.
local function boltPoints(top: Vector3, bottom: Vector3, steps: number, jitter: number): { Vector3 }
	local points = { top }
	for i = 1, steps - 1 do
		local t = i / steps
		local base = top:Lerp(bottom, t)
		local spread = jitter * (1 - t * 0.7)
		table.insert(points, base + Vector3.new(rng:NextNumber(-spread, spread), 0, rng:NextNumber(-spread, spread)))
	end
	table.insert(points, bottom)
	return points
end

local function drawBolt(points: { Vector3 }, thickness: number, parts: { Part })
	for i = 1, #points - 1 do
		-- soft glow, then the white-hot core
		table.insert(parts, segment(points[i], points[i + 1], thickness * 3.2, YELLOW, 0.55))
		table.insert(parts, segment(points[i], points[i + 1], thickness, Color3.new(1, 1, 1), 0))
	end
end

local function lightning(position: Vector3, height: number)
	local scale = math.max(height / 45, 0.6)
	local top = position + Vector3.new(rng:NextNumber(-80, 80), 650, rng:NextNumber(-80, 80))
	local parts: { Part } = {}

	local main = boltPoints(top, position, 22, 50 * scale)
	drawBolt(main, 2.2 * scale, parts)

	-- Forks off the main bolt
	for _ = 1, 5 do
		local index = rng:NextInteger(4, #main - 3)
		local start = main[index]
		local stop = start + Vector3.new(rng:NextNumber(-120, 120), -rng:NextNumber(60, 200), rng:NextNumber(-120, 120))
		drawBolt(boltPoints(start, stop, 7, 22), 0.8 * scale, parts)
	end

	-- Where it lands: light, shockwave ring, ground flash
	local lightPart = Instance.new("Part")
	lightPart.Anchored, lightPart.CanCollide, lightPart.CanQuery, lightPart.CanTouch = true, false, false, false
	lightPart.Transparency = 1
	lightPart.Size = Vector3.one
	lightPart.Position = position + Vector3.new(0, 6, 0)
	lightPart.Parent = folder
	local light = Instance.new("PointLight")
	light.Color = PALE_YELLOW
	light.Range = 60
	light.Brightness = 60
	light.Parent = lightPart
	tween(light, 1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Brightness = 0, Range = 25 })
	Debris:AddItem(lightPart, 2)

	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
	ring.Material = Enum.Material.Neon
	ring.Color = PALE_YELLOW
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.6, 3, 3)
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = folder
	tween(ring, 0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, { Size = Vector3.new(1, 90 * scale, 90 * scale), Transparency = 1 })
	Debris:AddItem(ring, 0.9)

	-- Flicker: the bolt re-strikes once, then fades
	task.spawn(function()
		task.wait(0.09)
		for _, part in parts do
			part.Transparency = 1
		end
		task.wait(0.05)
		for index, part in parts do
			part.Transparency = if index % 2 == 1 then 0.55 else 0
		end
		task.wait(0.12)
		for _, part in parts do
			tween(part, 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Transparency = 1 })
		end
		task.wait(0.5)
		for _, part in parts do
			part:Destroy()
		end
	end)
end

----------------------------------------------------------------------
-- Sound
----------------------------------------------------------------------

local function playSound(position: Vector3, id: string, volume: number, speed: number, maxDistance: number)
	if id == "" then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = folder

	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 80
	sound.RollOffMaxDistance = maxDistance
	sound.Parent = anchor
	sound:Play()
	Debris:AddItem(anchor, 12)
end

----------------------------------------------------------------------

local function onShift(data: any)
	if typeof(data) ~= "table" or typeof(data.Position) ~= "Vector3" then
		return
	end
	local position: Vector3 = data.Position
	local height: number = if typeof(data.Height) == "number" then data.Height else 45
	local distance = distanceTo(position)
	local mine = data.UserId == player.UserId

	if settings.Lightning then
		lightning(position, height)
	end

	-- Sounds: your Titan-shift sound plus thunder (slightly delayed: light travels faster)
	playSound(position, settings.Sounds.Shift, 8, 1, 3500)
	task.delay(math.min(distance / 900, 1.6), function()
		playSound(position, settings.Sounds.Thunder, 10, 0.6, 3500)
	end)

	-- Screen: full for the shifter, fading with distance for everyone else
	local power = if mine then 1 else math.clamp(1 - distance / settings.FlashRange, 0, 1) ^ 1.3
	if power > 0.08 then
		screenSequence(power)
	end
	local shakeRange = 350
	if mine or distance < shakeRange then
		local closeness = if mine then 1 else 1 - distance / shakeRange
		CameraController.shake(5 * closeness)
		CameraController.punch(-10 * closeness)
	end
end

function ShiftEffects.start()
	colour = Instance.new("ColorCorrectionEffect")
	colour.Name = "ShiftColor"
	colour.Parent = Lighting

	blur = Instance.new("BlurEffect")
	blur.Name = "ShiftBlur"
	blur.Size = 0
	blur.Parent = Lighting

	local gui = Instance.new("ScreenGui")
	gui.Name = "ShiftFlash"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.Parent = player:WaitForChild("PlayerGui")
	overlay = Instance.new("Frame")
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Active = false
	overlay.Parent = gui

	folder = Instance.new("Folder")
	folder.Name = "ShiftFxLocal"
	folder.Parent = Workspace

	Remotes.ShiftFx.OnClientEvent:Connect(onShift)
end

return ShiftEffects
