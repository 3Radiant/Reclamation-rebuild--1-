--[[
	ArtilleryEffects (client)
	Everything you see and hear of the artillery. The server only says WHAT happened
	(Remotes.ArtilleryFx); each client draws it, so none of this costs the server anything.

	Incoming : a shell whistles down from the sky - the sound speeds up and gets louder
	           as it falls (a looping whistle sound is pitched up over FallTime).
	Impact   : in order, scaled by Config.Visual and your distance to the blast:
	             1. white flash + blinding light
	             2. fireball, shockwave ring and dome, fire / dust / spark bursts, debris
	             3. camera shake and a white-out (if close)
	             4. a deep layered boom, arriving after a delay (speed of sound)
	             5. a rising column of black smoke that lingers
	             6. muffled hearing if you were close (an EQ effect, no asset needed)

	Sound slots and all sizes are in ArtilleryConfigs/<Name>.luau (Sounds, Visual).
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtilleryConfigs = require(Shared.Configs.ArtilleryConfigs)
local Remotes = require(Shared.Remotes)

local CameraController = require(script.Parent.CameraController)

local player = Players.LocalPlayer
local rng = Random.new()

local ArtilleryEffects = {}

local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local folder: Folder
local flashFrame: Frame
local muffle: EqualizerSoundEffect
local flashToken, muffleToken = 0, 0

local function tween(object: Instance, seconds: number, style: Enum.EasingStyle, direction: Enum.EasingDirection, goal: { [string]: any })
	TweenService:Create(object, TweenInfo.new(seconds, style, direction), goal):Play()
end

local function effectPart(position: Vector3, size: Vector3?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size or Vector3.one
	part.Position = position
	part.Parent = folder
	return part
end

local function newSound(parent: Instance, id: string, volume: number, speed: number, maxDistance: number): Sound?
	if id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 60
	sound.RollOffMaxDistance = maxDistance
	sound.Parent = parent
	return sound
end

local function distanceTo(position: Vector3): number
	local camera = Workspace.CurrentCamera
	return if camera then (camera.CFrame.Position - position).Magnitude else math.huge
end

----------------------------------------------------------------------
-- Incoming shell
----------------------------------------------------------------------

local function incoming(config: any, impact: Vector3, start: Vector3, fallTime: number)
	local carrier = effectPart(start)
	local whistle = newSound(carrier, config.Sounds.Whistle, 0.25, 0.7, 1400)
	if whistle then
		whistle.Looped = true
		whistle:Play()
		tween(whistle, fallTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { Volume = 6, PlaybackSpeed = 1.7 })
	end
	tween(carrier, fallTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { Position = impact })

	task.delay(fallTime, function()
		if whistle then
			whistle:Stop()
		end
		carrier:Destroy()
	end)
end

----------------------------------------------------------------------
-- Impact
----------------------------------------------------------------------

local function emitter(parent: Instance, texture: string, color: ColorSequence, size: NumberSequence, lifetime: NumberRange, speed: NumberRange): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = color
	e.Size = size
	e.Lifetime = lifetime
	e.Speed = speed
	e.Rate = 0
	e.Enabled = false
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-60, 60)
	e.Parent = parent
	return e
end

local function flashScreen(strength: number)
	flashToken += 1
	local mine = flashToken
	flashFrame.BackgroundTransparency = 1 - math.clamp(strength, 0, 1)
	task.delay(0.12, function()
		if mine == flashToken then
			tween(flashFrame, 1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { BackgroundTransparency = 1 })
		end
	end)
end

-- Muffled hearing: highs drop out, then recover over a few seconds
local function deafen(strength: number)
	muffleToken += 1
	local mine = muffleToken
	muffle.HighGain = -70 * strength
	muffle.MidGain = -25 * strength
	task.delay(1.2 + 2 * strength, function()
		if mine == muffleToken then
			tween(muffle, 3.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, { HighGain = 0, MidGain = 0 })
		end
	end)
end

local function impact(config: any, position: Vector3, blastRadius: number)
	local visual = config.Visual
	local size = blastRadius * visual.Scale
	local distance = distanceTo(position)

	-- 1. light -------------------------------------------------------------
	local lightPart = effectPart(position + Vector3.new(0, 4, 0))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 80)
	light.Range = 60
	light.Brightness = 40
	light.Parent = lightPart
	tween(light, 1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Brightness = 0, Range = 20 })
	Debris:AddItem(lightPart, 2)

	-- 2. fireball + shockwave -----------------------------------------------
	local fireball = effectPart(position + Vector3.new(0, size * 0.25, 0), Vector3.one * 2)
	fireball.Shape = Enum.PartType.Ball
	fireball.Material = Enum.Material.Neon
	fireball.Color = Color3.fromRGB(255, 190, 90)
	fireball.Transparency = 0
	tween(fireball, 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Size = Vector3.one * size * 1.6 })
	tween(fireball, 0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { Transparency = 1, Color = Color3.fromRGB(190, 60, 30) })
	Debris:AddItem(fireball, 1.2)

	local ring = effectPart(position + Vector3.new(0, 0.6, 0), Vector3.new(0.6, 2, 2))
	ring.Shape = Enum.PartType.Cylinder
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 235, 210)
	ring.Transparency = 0.25
	tween(ring, 0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, { Size = Vector3.new(1.2, size * 5, size * 5), Transparency = 1 })
	Debris:AddItem(ring, 0.9)

	local dome = effectPart(position, Vector3.one * 4)
	dome.Shape = Enum.PartType.Ball
	dome.Material = Enum.Material.ForceField
	dome.Color = Color3.fromRGB(255, 240, 225)
	dome.Transparency = 0.2
	tween(dome, 0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, { Size = Vector3.one * size * 3.2, Transparency = 1 })
	Debris:AddItem(dome, 0.8)

	-- 3. particles ----------------------------------------------------------
	local source = effectPart(position + Vector3.new(0, 1.5, 0))
	local fire = emitter(
		source, TEX_FIRE,
		ColorSequence.new(Color3.fromRGB(255, 200, 110), Color3.fromRGB(200, 60, 20)),
		NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.5), NumberSequenceKeypoint.new(1, size * 1.3) }),
		NumberRange.new(0.8, 1.6), NumberRange.new(size * 1.2, size * 3)
	)
	fire.SpreadAngle = Vector2.new(70, 70)
	fire.LightEmission = 1
	fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	fire:Emit(55)

	local dust = emitter(
		source, TEX_SMOKE,
		ColorSequence.new(Color3.fromRGB(120, 105, 90)),
		NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.6), NumberSequenceKeypoint.new(1, size * 2.4) }),
		NumberRange.new(2.5, 4.5), NumberRange.new(size * 4, size * 8)
	)
	dust.SpreadAngle = Vector2.new(88, 88)
	dust.Drag = 3
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	dust:Emit(60)

	local sparks = emitter(
		source, TEX_SPARK,
		ColorSequence.new(Color3.fromRGB(255, 220, 140)),
		NumberSequence.new(0.9, 0.2),
		NumberRange.new(1, 2.4), NumberRange.new(size * 3, size * 9)
	)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -60, 0)
	sparks.LightEmission = 1
	sparks:Emit(90)

	-- Black smoke column that lingers and rises
	local smoke = emitter(
		source, TEX_SMOKE,
		ColorSequence.new(Color3.fromRGB(38, 34, 32), Color3.fromRGB(70, 66, 64)),
		NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.7), NumberSequenceKeypoint.new(1, size * 3.2) }),
		NumberRange.new(7, 11), NumberRange.new(size * 0.8, size * 1.6)
	)
	smoke.SpreadAngle = Vector2.new(14, 14)
	smoke.Acceleration = Vector3.new(0, 4, 0)
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.7, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Rate = 38
	smoke.Enabled = true
	task.delay(3.2, function()
		smoke.Enabled = false
	end)
	Debris:AddItem(source, 14)

	-- Debris chunks (only worth drawing if you can see them)
	if distance < 450 then
		for _ = 1, 14 do
			local chunk = Instance.new("Part")
			chunk.Size = Vector3.new(rng:NextNumber(0.6, 2.4), rng:NextNumber(0.6, 2.4), rng:NextNumber(0.6, 2.4))
			chunk.Material = Enum.Material.Slate
			chunk.Color = Color3.fromRGB(70, 62, 55)
			chunk.CanCollide = false -- they'd collide with players' own physics; purely visual
			chunk.CFrame = CFrame.new(position + Vector3.new(0, 2, 0)) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
			chunk.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.9, 1.6), rng:NextNumber(-1, 1)) * size * rng:NextNumber(2.5, 5)
			chunk.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8))
			chunk.Parent = folder
			Debris:AddItem(chunk, 5)
		end
	end

	-- 4. camera, white-out, deafness ----------------------------------------
	if distance < visual.ShakeRange then
		local closeness = 1 - distance / visual.ShakeRange
		CameraController.shake(visual.ShakeMax * closeness ^ 1.4)
		CameraController.punch(-9 * closeness)
	end
	local flashRange = blastRadius * visual.FlashRange
	if distance < flashRange then
		flashScreen(0.95 * (1 - distance / flashRange))
	end
	local deafRange = blastRadius * visual.DeafenRange
	if distance < deafRange then
		deafen(1 - distance / deafRange)
	end

	-- 5. the boom: light is faster than sound ---------------------------------
	task.delay(math.min(distance / visual.SpeedOfSound, 2.2), function()
		local anchor = effectPart(position)
		local deep = newSound(anchor, config.Sounds.Explosion, 10, 0.55, 3200)
		local mid = newSound(anchor, config.Sounds.Explosion, 7, 0.85, 2600)
		local crack = newSound(anchor, config.Sounds.Explosion, 5, 1.3, 1800)
		local reverb = Instance.new("ReverbSoundEffect")
		reverb.DecayTime = 3.5
		reverb.Density = 1
		reverb.Diffusion = 0.9
		reverb.DryLevel = 0
		reverb.WetLevel = -4
		if deep and mid and crack then -- all three exist or none (same sound id)
			for _, sound in { deep, mid, crack } do
				reverb:Clone().Parent = sound
				sound:Play()
			end
		end
		reverb:Destroy()
		Debris:AddItem(anchor, 9)
	end)
end

----------------------------------------------------------------------

function ArtilleryEffects.start()
	folder = Instance.new("Folder")
	folder.Name = "ArtilleryFxLocal"
	folder.Parent = Workspace

	local gui = Instance.new("ScreenGui")
	gui.Name = "ArtilleryFlash"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.Parent = player:WaitForChild("PlayerGui")
	flashFrame = Instance.new("Frame")
	flashFrame.Size = UDim2.fromScale(1, 1)
	flashFrame.BackgroundColor3 = Color3.fromRGB(255, 244, 230)
	flashFrame.BackgroundTransparency = 1
	flashFrame.BorderSizePixel = 0
	flashFrame.Active = false
	flashFrame.Parent = gui

	muffle = Instance.new("EqualizerSoundEffect")
	muffle.Name = "ArtilleryMuffle"
	muffle.LowGain = 0
	muffle.MidGain = 0
	muffle.HighGain = 0
	muffle.Parent = SoundService

	Remotes.ArtilleryFx.OnClientEvent:Connect(function(data)
		if typeof(data) ~= "table" or typeof(data.Position) ~= "Vector3" then
			return
		end
		local config = ArtilleryConfigs[data.Id]
		if not config or not config.Visual then
			return
		end
		if data.Kind == "Incoming" and typeof(data.Start) == "Vector3" and typeof(data.Time) == "number" then
			incoming(config, data.Position, data.Start, data.Time)
		elseif data.Kind == "Impact" and typeof(data.Time) == "number" then
			impact(config, data.Position, data.Time)
		end
	end)
end

return ArtilleryEffects
