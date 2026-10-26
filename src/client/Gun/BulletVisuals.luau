--[[
	BulletVisuals (client)
	Cosmetic bullets only - the server decides what actually hits. Uses the same
	Ballistics module so the visual path matches the real one.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GunConfigs = require(Shared.Configs.GunConfigs)
local Remotes = require(Shared.Remotes)
local Ballistics = require(Shared.Gun.Ballistics)
local Spread = require(Shared.Gun.Spread)

local BulletVisuals = {}

-- GunConfig.Tracer picks one of these
BulletVisuals.TracerStyles = {
	Default = { Color = Color3.fromRGB(255, 214, 130), Size = Vector3.new(0.1, 0.1, 2.4), TrailWidth = 0.16, TrailLength = 0.14 },
}

local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local rng = Random.new()

local folder = Instance.new("Folder")
folder.Name = "GunBullets"
folder.Parent = Workspace

local fxFolder = Instance.new("Folder")
fxFolder.Name = "GunFx"
fxFolder.Parent = Workspace

-- Invisible anchored part to hang particles / lights on
local function fxPart(cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.CFrame = cframe
	part.Parent = fxFolder
	return part
end

local function emitter(parent: Instance, texture: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Rate = 0
	e.Enabled = false
	e.Parent = parent
	return e
end

local function distanceToCamera(position: Vector3): number
	local camera = Workspace.CurrentCamera
	return if camera then (camera.CFrame.Position - position).Magnitude else math.huge
end

-- Plays a 3D sound at a position (for every client). Blank / missing id = silent.
function BulletVisuals.playSound(id: string?, position: Vector3, volume: number?, maxDistance: number?)
	if not id or id == "" then
		return
	end
	local part = fxPart(CFrame.new(position))
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 1
	sound.PlaybackSpeed = rng:NextNumber(0.97, 1.03) -- tiny variation so repeats don't sound robotic
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 20
	sound.RollOffMaxDistance = maxDistance or 700
	sound.Parent = part
	sound:Play()
	Debris:AddItem(part, 8)
end

----------------------------------------------------------------------
-- Muzzle: a sharp flash, a few streaking sparks and a thin wisp of smoke
-- (kept small on purpose, so it reads as a shot and not as a cloud)
----------------------------------------------------------------------

function BulletVisuals.muzzleFlash(origin: Vector3, direction: Vector3)
	if distanceToCamera(origin) > 400 then
		return
	end
	local part = fxPart(CFrame.lookAt(origin, origin + direction))

	local flash = emitter(part, TEX_SPARK)
	flash.Color = ColorSequence.new(Color3.fromRGB(255, 244, 205), Color3.fromRGB(255, 176, 74))
	flash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(1, 0.4) })
	flash.Lifetime = NumberRange.new(0.05, 0.08)
	flash.Speed = NumberRange.new(0, 3)
	flash.Rotation = NumberRange.new(0, 360)
	flash.LightEmission = 1
	flash.LightInfluence = 0
	flash.Transparency = NumberSequence.new(0, 1)
	flash.EmissionDirection = Enum.NormalId.Front
	flash:Emit(2)

	local sparks = emitter(part, TEX_SPARK)
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 226, 150), Color3.fromRGB(255, 120, 40))
	sparks.Size = NumberSequence.new(0.35, 0.05)
	sparks.Lifetime = NumberRange.new(0.12, 0.28)
	sparks.Speed = NumberRange.new(26, 60)
	sparks.SpreadAngle = Vector2.new(14, 14)
	sparks.Acceleration = Vector3.new(0, -30, 0)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Orientation = Enum.ParticleOrientation.VelocityParallel
	sparks.EmissionDirection = Enum.NormalId.Front
	sparks:Emit(7)

	local smoke = emitter(part, TEX_SMOKE)
	smoke.Color = ColorSequence.new(Color3.fromRGB(205, 205, 205), Color3.fromRGB(120, 120, 120))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 2.6) })
	smoke.Lifetime = NumberRange.new(0.7, 1.2)
	smoke.Speed = NumberRange.new(3, 9)
	smoke.SpreadAngle = Vector2.new(18, 18)
	smoke.Acceleration = Vector3.new(0, 2.5, 0)
	smoke.Drag = 2
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-40, 40)
	smoke.LightInfluence = 1
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.EmissionDirection = Enum.NormalId.Front
	smoke:Emit(4)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 100)
	light.Range = 14
	light.Brightness = 5
	light.Parent = part
	TweenService:Create(light, TweenInfo.new(0.09), { Brightness = 0 }):Play()

	Debris:AddItem(part, 2)
end

-- A spent brass casing flips out to the right and drops
function BulletVisuals.ejectCasing(origin: Vector3, direction: Vector3)
	if distanceToCamera(origin) > 80 then
		return
	end
	local right = direction:Cross(Vector3.yAxis)
	right = if right.Magnitude > 0.01 then right.Unit else Vector3.xAxis

	local casing = Instance.new("Part")
	casing.Size = Vector3.new(0.12, 0.12, 0.42)
	casing.Color = Color3.fromRGB(212, 170, 80)
	casing.Material = Enum.Material.Metal
	casing.CanQuery = false
	casing.CanTouch = false
	casing.CastShadow = false
	casing.CFrame = CFrame.lookAt(origin - direction * 0.8, origin + right)
	casing.AssemblyLinearVelocity = right * rng:NextNumber(7, 11) + Vector3.new(0, rng:NextNumber(7, 11), 0) - direction * rng:NextNumber(0, 2)
	casing.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-30, 30), rng:NextNumber(-30, 30), rng:NextNumber(-30, 30))
	casing.Parent = fxFolder
	Debris:AddItem(casing, 3)
end

----------------------------------------------------------------------
-- Impact: dust puff + a few sparks, aimed out of the surface
----------------------------------------------------------------------

function BulletVisuals.impact(result: RaycastResult)
	if distanceToCamera(result.Position) > 250 then
		return
	end
	local hit = result.Instance
	local part = fxPart(CFrame.lookAt(result.Position, result.Position + result.Normal))
	local tint = hit.Color:Lerp(Color3.fromRGB(140, 130, 120), 0.6)

	local dust = emitter(part, TEX_SMOKE)
	dust.Color = ColorSequence.new(tint)
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 2.2) })
	dust.Lifetime = NumberRange.new(0.5, 0.9)
	dust.Speed = NumberRange.new(2, 8)
	dust.SpreadAngle = Vector2.new(35, 35)
	dust.Drag = 3
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	dust.EmissionDirection = Enum.NormalId.Front
	dust:Emit(6)

	local sparks = emitter(part, TEX_SPARK)
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 226, 160), Color3.fromRGB(255, 130, 50))
	sparks.Size = NumberSequence.new(0.25, 0.04)
	sparks.Lifetime = NumberRange.new(0.15, 0.35)
	sparks.Speed = NumberRange.new(14, 34)
	sparks.SpreadAngle = Vector2.new(50, 50)
	sparks.Acceleration = Vector3.new(0, -50, 0)
	sparks.LightEmission = 1
	sparks.Orientation = Enum.ParticleOrientation.VelocityParallel
	sparks.EmissionDirection = Enum.NormalId.Front
	sparks:Emit(5)

	Debris:AddItem(part, 2)
end

----------------------------------------------------------------------

----------------------------------------------------------------------
-- Flares: a glowing coloured ball with a smoke trail; where it lands it keeps burning
----------------------------------------------------------------------

local function flareColor(config: any, colorName: string?): Color3
	local colors = config.Colors
	return (colors and (colors[colorName or config.DefaultColor] or colors[config.DefaultColor])) or Color3.fromRGB(255, 60, 50)
end

local function isDark(color: Color3): boolean
	return color.R + color.G + color.B < 0.45
end

-- A burning flare on the ground (or briefly in the air if it ran out of range)
local function burn(position: Vector3, normal: Vector3, config: any, color: Color3, seconds: number)
	local part = fxPart(CFrame.new(position + normal * 0.5))
	local dark = isDark(color)

	local light = Instance.new("PointLight")
	light.Color = if dark then Color3.fromRGB(90, 90, 100) else color
	light.Range = config.Flare.LightRange
	light.Brightness = if dark then 0.8 else config.Flare.LightBrightness
	light.Shadows = false
	light.Parent = part

	local glow = Instance.new("Part") -- the burning stick itself
	glow.Size = Vector3.new(0.5, 0.5, 0.5)
	glow.Shape = Enum.PartType.Ball
	glow.Material = Enum.Material.Neon
	glow.Color = color
	glow.Anchored = true
	glow.CanCollide = false
	glow.CanQuery = false
	glow.CanTouch = false
	glow.CastShadow = false
	glow.Position = part.Position
	glow.Parent = fxFolder

	local smoke = emitter(part, TEX_SMOKE)
	smoke.Color = ColorSequence.new(color)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 9) })
	smoke.Lifetime = NumberRange.new(3, 5)
	smoke.Speed = NumberRange.new(4, 9)
	smoke.SpreadAngle = Vector2.new(14, 14)
	smoke.Acceleration = Vector3.new(0, 3, 0)
	smoke.Drag = 1.5
	smoke.LightEmission = if dark then 0 else 0.45
	smoke.LightInfluence = if dark then 1 else 0.2
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-20, 20)
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	smoke.EmissionDirection = Enum.NormalId.Front
	smoke.Rate = 14
	smoke.Enabled = true

	local sparks = emitter(part, TEX_SPARK)
	sparks.Color = ColorSequence.new(if dark then Color3.fromRGB(140, 140, 150) else color)
	sparks.Size = NumberSequence.new(0.3, 0.02)
	sparks.Lifetime = NumberRange.new(0.3, 0.7)
	sparks.Speed = NumberRange.new(6, 16)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Acceleration = Vector3.new(0, -25, 0)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.EmissionDirection = Enum.NormalId.Front
	sparks.Rate = 22
	sparks.Enabled = true

	-- Flicker, then die down
	local startedAt = os.clock()
	local baseBrightness = light.Brightness
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - startedAt
		if elapsed >= seconds or not part.Parent then
			connection:Disconnect()
			smoke.Enabled = false
			sparks.Enabled = false
			glow:Destroy()
			TweenService:Create(light, TweenInfo.new(1.2), { Brightness = 0 }):Play()
			return
		end
		local left = math.clamp((seconds - elapsed) / 2, 0, 1) -- last 2s: fade
		light.Brightness = baseBrightness * left * rng:NextNumber(0.75, 1.1)
		glow.Transparency = 1 - left
	end)
	Debris:AddItem(part, seconds + 6)
	Debris:AddItem(glow, seconds + 1)
end

local function spawnFlare(origin: Vector3, direction: Vector3, config: any, shooterCharacter: Instance?, colorName: string?)
	local color = flareColor(config, colorName)
	local dark = isDark(color)
	BulletVisuals.muzzleFlash(origin, direction)
	if config.Sounds then
		BulletVisuals.playSound(config.Sounds.Fire, origin, config.Sounds.FireVolume, config.Sounds.FireDistance)
	end

	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * 0.8
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.lookAt(origin, origin + direction)
	part.Parent = folder

	local light = Instance.new("PointLight")
	light.Color = if dark then Color3.fromRGB(110, 110, 120) else color
	light.Range = 22
	light.Brightness = if dark then 1 else 3
	light.Parent = part

	local smoke = emitter(part, TEX_SMOKE)
	smoke.Color = ColorSequence.new(color)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 15) })
	smoke.Lifetime = NumberRange.new(20, 25)
	smoke.Speed = NumberRange.new(0, 2)
	smoke.LightEmission = if dark then 0 else 0.35
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	smoke.Rate = 45
	smoke.Enabled = true

	local sparks = emitter(part, TEX_SPARK)
	sparks.Color = ColorSequence.new(if dark then Color3.fromRGB(150, 150, 160) else color)
	sparks.Size = NumberSequence.new(0.35, 0.02)
	sparks.Lifetime = NumberRange.new(0.2, 0.45)
	sparks.Speed = NumberRange.new(2, 7)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Rate = 30
	sparks.Enabled = true

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if shooterCharacter then { shooterCharacter } else {}
	local bullet = Ballistics.new(origin, direction, config, params)

	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		local result = Ballistics.Step(bullet, dt)
		part.Position = bullet.Position
		if result then
			burn(result.Position, result.Normal, config, color, config.Flare.BurnTime)
		elseif bullet.Finished then
			burn(bullet.Position, Vector3.zero, config, color, config.Flare.BurnTime * 0.25) -- burnt out in the air
		end
		if bullet.Finished then
			connection:Disconnect()
			smoke.Enabled = false
			sparks.Enabled = false
			part:Destroy()
		end
	end)
end

function BulletVisuals.spawnBullet(origin: Vector3, direction: Vector3, config: any, shooterCharacter: Instance?, colorName: string?, quiet: boolean?, speedScale: number?)
	if config.Colors then
		spawnFlare(origin, direction, config, shooterCharacter, colorName)
		return
	end
	local style = BulletVisuals.TracerStyles[config.Tracer] or BulletVisuals.TracerStyles.Default

	local worked = config.Type == "Bolt" or config.Type == "Pump"
	local sounds = config.Sounds
	if not quiet then -- extra pellets of the same shot are silent: one flash, one bang
		BulletVisuals.muzzleFlash(origin, direction)
		if sounds then
			BulletVisuals.playSound(sounds.Fire, origin, sounds.FireVolume, sounds.FireDistance)
			if worked and sounds.Bolt and sounds.Bolt ~= "" then
				task.delay(0.55, BulletVisuals.playSound, sounds.Bolt, origin, sounds.BoltVolume, 120)
			end
		end
	end
	if quiet or config.Casing == false then
		print("")
		-- no brass
	elseif worked then -- elseif config.Type == "Bolt" then
		task.delay(0.55, BulletVisuals.ejectCasing, origin, direction) -- after the bolt is worked
	else
		BulletVisuals.ejectCasing(origin, direction)
	end

	local part = Instance.new("Part")
	part.Size = style.Size
	part.Color = style.Color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- bullets never block raycasts
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.lookAt(origin, origin + direction)
	part.Parent = folder

	-- A short fading streak behind the bullet
	local back = Instance.new("Attachment")
	back.Position = Vector3.new(0, 0, style.Size.Z / 2)
	back.Parent = part
	local front = Instance.new("Attachment")
	front.Position = Vector3.new(0, 0, -style.Size.Z / 2)
	front.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = back
	trail.Attachment1 = front
	trail.Color = ColorSequence.new(style.Color)
	trail.Lifetime = style.TrailLength
	trail.LightEmission = 1
	trail.MinLength = 0.05
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = part

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if shooterCharacter then { shooterCharacter } else {}

	local bullet = Ballistics.new(origin, direction, config, params, speedScale)

	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		local result = Ballistics.Step(bullet, dt)
		part.CFrame = CFrame.lookAt(bullet.Position, bullet.Position + bullet.Velocity)
		if result then
			BulletVisuals.impact(result)
		end
		if bullet.Finished then
			connection:Disconnect()
			part:Destroy()
		end
	end)
end

function BulletVisuals.spawnShot(origin: Vector3, direction: Vector3, config: any, shooterCharacter: Instance?, colorName: string?, seed: number?)
	if config.Colors then
		BulletVisuals.spawnBullet(origin, direction, config, shooterCharacter, colorName)
		return
	end
	for index, pellet in Spread.pellets(config, direction, seed or 0) do
		BulletVisuals.spawnBullet(origin, pellet.Direction, config, shooterCharacter, colorName, index > 1, pellet.SpeedScale)
	end
end

function BulletVisuals.start()
	Remotes.GunBulletReplicate.OnClientEvent:Connect(function(shooterCharacter, gunId, origin, direction, colorName, seed)
		local config = GunConfigs[gunId]
		if config and typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
			BulletVisuals.spawnShot(origin, direction, config, shooterCharacter, if typeof(colorName) == "string" then colorName else nil, if typeof(seed) == "number" then seed else 0)
		end
	end)
end

return BulletVisuals
