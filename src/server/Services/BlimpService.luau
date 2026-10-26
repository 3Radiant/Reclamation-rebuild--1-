--[[
	BlimpService (server)
	Marleyan airships that come out of the sky, drift over the battlefield and shell it at
	random. Their shells do not check teams: it is danger close for everyone.

	Control it with the admin chat command (all changes last until the server closes):
	  /blimps on | off            switch arrivals on / off (off: the ones up there leave)
	  /blimps spawn [n]           bring blimps in now (never above the max)
	  /blimps clear               remove every blimp immediately
	  /blimps status
	  /blimps max <n>             most blimps alive at once
	  /blimps every <min> [max]   seconds between arrivals
	  /blimps stay <min> [max]    seconds each blimp stays
	  /blimps fire <min> [max]    seconds between volleys per blimp
	  /blimps shells <min> [max]  shells per volley
	  /blimps range <studs>       how far from itself a blimp aims
	  /blimps alt <min> [max]     altitude above the ground
	  /blimps radius <studs>      size of the patrolled battlefield
	  /blimps speed <studs/s>
	  /blimps here                make the battlefield centre where you stand
	  /blimps model <Name>        use ServerStorage/Blimps/<Name>

	MODEL: drop a model into assets/blimps (see docs/CUSTOM_BLIMPS.md). It needs a PrimaryPart
	and its nose should point along -Z. Parts named "Muzzle" are where shells are fired from
	(one is picked at random each volley); without any, shells leave from under the hull.
	Every part is anchored and made non-colliding automatically.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)

local ArtilleryService = require(script.Parent.ArtilleryService)
local MessageService = require(script.Parent.MessageService)

local BlimpService = {}

local rng = Random.new()

type Range = { Min: number, Max: number }
type Blimp = {
	Model: Model,
	State: string, -- "Arriving" | "Patrol" | "Leaving"
	Position: Vector3,
	Yaw: number,
	TargetAltitudeY: number,
	Waypoint: Vector3,
	StateStartedAt: number,
	LeaveAt: number,
	NextFireAt: number,
	Muzzles: { BasePart },
	Parts: { [BasePart]: number }, -- part -> its normal transparency
	Fade: number, -- 0 = invisible .. 1 = fully visible
	Time: number,
}

-- Live settings: a copy of Config.Blimps that /blimps edits
local settings = table.clone(GameConfig.Blimps) :: any
for key, value in settings do
	if type(value) == "table" then
		settings[key] = table.clone(value)
	end
end

local enabled = false
local blimps: { Blimp } = {}
local nextSpawnAt = 0

local ARRIVE_HEIGHT = 700 -- studs above its patrol altitude where a blimp appears
local ARRIVE_TIME = 12
local LEAVE_TIME = 14

local function folder(): Folder
	local f = Workspace:FindFirstChild("Blimps")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Blimps"
		f.Parent = Workspace
	end
	return f :: Folder
end

local function between(range: Range): number
	return rng:NextNumber(range.Min, range.Max)
end

local function groundY(x: number, z: number): number
	local result = Workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -4000, 0))
	return result and result.Position.Y or settings.Area.Center.Y
end

----------------------------------------------------------------------
-- Model
----------------------------------------------------------------------

local function part(parent: Instance, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CFrame = offset
	p.Parent = parent
	return p
end

-- The stand-in airship: an envelope, a gondola, fins and two guns. Replace it by dropping a
-- model named after Config.Blimps.Model into assets/blimps.
local function buildPlaceholder(): Model
	local model = Instance.new("Model")
	model.Name = "Blimp"
	local hull = Color3.fromRGB(96, 98, 88)
	local dark = Color3.fromRGB(52, 50, 46)

	local envelope = part(model, "Envelope", Vector3.new(30, 30, 110), CFrame.new(), hull, Enum.Material.Fabric)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = envelope
	model.PrimaryPart = envelope

	part(model, "Gondola", Vector3.new(9, 7, 30), CFrame.new(0, -19, 0), dark, Enum.Material.Metal)
	part(model, "FinTop", Vector3.new(1.5, 18, 16), CFrame.new(0, 11, 46), dark, Enum.Material.Metal)
	part(model, "FinBottom", Vector3.new(1.5, 18, 16), CFrame.new(0, -11, 46), dark, Enum.Material.Metal)
	part(model, "FinLeft", Vector3.new(18, 1.5, 16), CFrame.new(-11, 0, 46), dark, Enum.Material.Metal)
	part(model, "FinRight", Vector3.new(18, 1.5, 16), CFrame.new(11, 0, 46), dark, Enum.Material.Metal)

	for i, x in { -3, 3 } do
		local muzzle = part(model, "Muzzle", Vector3.new(1.5, 1.5, 1.5), CFrame.new(x, -23.5, -6 * i), dark, Enum.Material.Metal)
		muzzle.Transparency = 1
	end
	return model
end

local function makeModel(): Model
	local folderRoot = ServerStorage:FindFirstChild("Blimps")
	local template = folderRoot and folderRoot:FindFirstChild(settings.Model)
	if template and template:IsA("Model") then
		local clone = template:Clone()
		if not clone.PrimaryPart then
			clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart", true)
		end
		if clone.PrimaryPart then
			return clone
		end
		warn("[BlimpService] custom model '" .. tostring(settings.Model) .. "' has no parts; using the placeholder")
	end
	return buildPlaceholder()
end

----------------------------------------------------------------------
-- Spawning / removing
----------------------------------------------------------------------

local function setFade(blimp: Blimp, fade: number)
	blimp.Fade = fade
	for p, normal in blimp.Parts do
		p.Transparency = 1 - (1 - normal) * fade
	end
end

local function destroyBlimp(blimp: Blimp)
	local index = table.find(blimps, blimp)
	if index then
		table.remove(blimps, index)
	end
	blimp.Model:Destroy()
end

local function spawnOne(): boolean
	if #blimps >= settings.MaxAlive then
		return false
	end

	local model = makeModel()
	local blimp: Blimp = {
		Model = model,
		State = "Arriving",
		Position = Vector3.zero,
		Yaw = rng:NextNumber(0, math.pi * 2),
		TargetAltitudeY = 0,
		Waypoint = Vector3.zero,
		StateStartedAt = os.clock(),
		LeaveAt = os.clock() + between(settings.StayFor) + ARRIVE_TIME,
		NextFireAt = math.huge,
		Muzzles = {},
		Parts = {},
		Fade = 0,
		Time = rng:NextNumber(0, 100),
	}

	-- Arrive above a random point of the battlefield
	local center: Vector3 = settings.Area.Center
	local angle = rng:NextNumber(0, math.pi * 2)
	local distance = settings.Area.Radius * rng:NextNumber(0.3, 1)
	local x, z = center.X + math.cos(angle) * distance, center.Z + math.sin(angle) * distance
	blimp.TargetAltitudeY = groundY(x, z) + between(settings.Altitude)
	blimp.Position = Vector3.new(x, blimp.TargetAltitudeY + ARRIVE_HEIGHT, z)
	blimp.Waypoint = blimp.Position

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
			blimp.Parts[descendant] = descendant.Transparency
			if descendant.Name == "Muzzle" then
				table.insert(blimp.Muzzles, descendant)
			end
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end

	-- Optional sounds
	local primary = model.PrimaryPart :: BasePart
	if settings.Sounds.Engine ~= "" then
		local engine = Instance.new("Sound")
		engine.SoundId = settings.Sounds.Engine
		engine.Looped = true
		engine.Volume = 1.2
		engine.RollOffMaxDistance = 900
		engine.RollOffMinDistance = 80
		engine.Parent = primary
		engine:Play()
	end

	setFade(blimp, 0)
	model:PivotTo(CFrame.new(blimp.Position) * CFrame.Angles(0, blimp.Yaw, 0))
	model.Parent = folder()
	table.insert(blimps, blimp)
	return true
end

local function pickWaypoint(blimp: Blimp): Vector3
	local center: Vector3 = settings.Area.Center
	local angle = rng:NextNumber(0, math.pi * 2)
	local distance = settings.Area.Radius * math.sqrt(rng:NextNumber())
	return Vector3.new(center.X + math.cos(angle) * distance, blimp.TargetAltitudeY, center.Z + math.sin(angle) * distance)
end

----------------------------------------------------------------------
-- Firing
----------------------------------------------------------------------

local function fire(blimp: Blimp)
	local center: Vector3 = settings.Area.Center
	local muzzle = if #blimp.Muzzles > 0 then blimp.Muzzles[rng:NextInteger(1, #blimp.Muzzles)] else nil
	local origin = if muzzle then muzzle.Position else blimp.Position - Vector3.new(0, 20, 0)

	-- A random spot below / around the blimp, kept inside the battlefield
	local angle = rng:NextNumber(0, math.pi * 2)
	local distance = settings.FireRadius * math.sqrt(rng:NextNumber())
	local target = Vector3.new(blimp.Position.X + math.cos(angle) * distance, 0, blimp.Position.Z + math.sin(angle) * distance)
	local offset = Vector3.new(target.X - center.X, 0, target.Z - center.Z)
	if offset.Magnitude > settings.Area.Radius then
		offset = offset.Unit * settings.Area.Radius * rng:NextNumber(0.5, 1)
		target = Vector3.new(center.X + offset.X, 0, center.Z + offset.Z)
	end

	if settings.Sounds.Fire ~= "" and muzzle then
		local sound = Instance.new("Sound")
		sound.SoundId = settings.Sounds.Fire
		sound.Volume = 2
		sound.RollOffMaxDistance = 1200
		sound.Parent = muzzle
		sound:Play()
		Debris:AddItem(sound, 6)
	end

	ArtilleryService.barrage(settings.Barrage, target, {
		Origin = origin,
		Shells = rng:NextInteger(math.floor(settings.Shells.Min), math.max(math.floor(settings.Shells.Min), math.floor(settings.Shells.Max))),
	})
end

----------------------------------------------------------------------
-- Update loop
----------------------------------------------------------------------

local function step(dt: number)
	local now = os.clock()

	if enabled and #blimps < settings.MaxAlive and now >= nextSpawnAt then
		nextSpawnAt = now + between(settings.SpawnEvery)
		if spawnOne() and settings.Announce and settings.AnnounceLines and #settings.AnnounceLines > 0 then
			MessageService.broadcast(settings.AnnounceLines, { Style = "Alert", Hold = 4 })
		end
	end

	for _, blimp in table.clone(blimps) do
		blimp.Time += dt
		local elapsed = now - blimp.StateStartedAt

		if blimp.State == "Arriving" then
			-- Drops out of the sky and fades in, easing to a stop at patrol altitude
			local t = math.clamp(elapsed / ARRIVE_TIME, 0, 1)
			local eased = 1 - (1 - t) ^ 3
			blimp.Position = Vector3.new(blimp.Position.X, blimp.TargetAltitudeY + ARRIVE_HEIGHT * (1 - eased), blimp.Position.Z)
			setFade(blimp, math.clamp(t * 3, 0, 1))
			if t >= 1 then
				blimp.State = "Patrol"
				blimp.StateStartedAt = now
				blimp.Waypoint = pickWaypoint(blimp)
				blimp.NextFireAt = now + between(settings.FireEvery)
			end
		elseif blimp.State == "Patrol" then
			local flat = Vector3.new(blimp.Waypoint.X - blimp.Position.X, 0, blimp.Waypoint.Z - blimp.Position.Z)
			if flat.Magnitude < 12 then
				blimp.Waypoint = pickWaypoint(blimp)
			else
				local direction = flat.Unit
				blimp.Position += direction * settings.Speed * dt
				local wantedYaw = math.atan2(-direction.X, -direction.Z)
				local difference = (wantedYaw - blimp.Yaw + math.pi) % (math.pi * 2) - math.pi
				blimp.Yaw += difference * (1 - math.exp(-0.6 * dt))
			end
			if now >= blimp.NextFireAt then
				blimp.NextFireAt = now + between(settings.FireEvery)
				fire(blimp)
			end
			if now >= blimp.LeaveAt then
				blimp.State = "Leaving"
				blimp.StateStartedAt = now
			end
		else -- Leaving: climbs away and fades out
			local t = math.clamp(elapsed / LEAVE_TIME, 0, 1)
			blimp.Position += Vector3.new(0, 1, 0) * (10 + 30 * t) * dt
			setFade(blimp, 1 - math.clamp((t - 0.3) / 0.7, 0, 1))
			if t >= 1 then
				destroyBlimp(blimp)
				continue
			end
		end

		-- A gentle bob and roll so it feels heavy and alive
		local bob = math.sin(blimp.Time * 0.5) * 1.5
		local roll = math.sin(blimp.Time * 0.35) * 0.025
		blimp.Model:PivotTo(CFrame.new(blimp.Position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, blimp.Yaw, roll))
	end
end

-- Blimps already up leave when you switch off
local function sendAwayAll()
	local now = os.clock()
	for _, blimp in blimps do
		if blimp.State ~= "Leaving" then
			blimp.State = "Leaving"
			blimp.StateStartedAt = now
		end
	end
end

function BlimpService.setEnabled(value: boolean)
	enabled = value
	if value then
		nextSpawnAt = 0
	else
		sendAwayAll()
	end
end

function BlimpService.isEnabled(): boolean
	return enabled
end

function BlimpService.spawn(count: number): number
	local spawned = 0
	for _ = 1, count do
		if spawnOne() then
			spawned += 1
		end
	end
	if spawned > 0 and settings.Announce and settings.AnnounceLines and #settings.AnnounceLines > 0 then
		MessageService.broadcast(settings.AnnounceLines, { Style = "Alert", Hold = 4 })
	end
	return spawned
end

function BlimpService.clear()
	for _, blimp in table.clone(blimps) do
		destroyBlimp(blimp)
	end
end

function BlimpService.start()
	RunService.Heartbeat:Connect(step)
end

----------------------------------------------------------------------
-- Admin command
----------------------------------------------------------------------

local HELP = "/blimps on|off|status|spawn [n]|clear|max n|every min [max]|stay min [max]|fire min [max]|shells min [max]|range studs|alt min [max]|radius studs|speed n|here|model Name"

local function numbers(text: string): { number }
	local list = {}
	for token in text:gmatch("%S+") do
		local value = tonumber(token)
		if value then
			table.insert(list, value)
		end
	end
	return list
end

local function setRange(key: string, values: { number }): string
	if #values == 0 or values[1] < 0 then
		return "Give one or two numbers: /blimps <setting> <min> [max]"
	end
	local low = values[1]
	local high = math.max(values[2] or values[1], low)
	settings[key] = { Min = low, Max = high }
	return ("%s = %s to %s"):format(key, tostring(low), tostring(high))
end

local function r(value: number): string
	return tostring(math.floor(value + 0.5))
end

-- Returns the reply to show the admin
function BlimpService.handleCommand(player: Player, args: string): string
	local word, rest = args:match("^%s*(%S*)%s*(.*)$")
	word = (word or ""):lower()
	local values = numbers(rest or "")

	if word == "on" then
		BlimpService.setEnabled(true)
		return "Blimps are on."
	elseif word == "off" then
		BlimpService.setEnabled(false)
		return "Blimps are off. The ones up there are leaving."
	elseif word == "toggle" then
		BlimpService.setEnabled(not enabled)
		return if enabled then "Blimps are on." else "Blimps are off."
	elseif word == "spawn" then
		local made = BlimpService.spawn(math.max(1, math.floor(values[1] or 1)))
		return if made > 0 then ("%s blimp(s) arriving."):format(r(made)) else ("At the limit (max %s alive)."):format(r(settings.MaxAlive))
	elseif word == "clear" then
		BlimpService.clear()
		return "All blimps removed."
	elseif word == "max" then
		if not values[1] then
			return "Usage: /blimps max <n>"
		end
		settings.MaxAlive = math.clamp(math.floor(values[1]), 0, 50)
		return ("Max blimps alive: %s"):format(r(settings.MaxAlive))
	elseif word == "every" then
		return setRange("SpawnEvery", values)
	elseif word == "stay" then
		return setRange("StayFor", values)
	elseif word == "fire" then
		return setRange("FireEvery", values)
	elseif word == "shells" then
		return setRange("Shells", values)
	elseif word == "alt" then
		return setRange("Altitude", values)
	elseif word == "range" then
		if not values[1] then
			return "Usage: /blimps range <studs>"
		end
		settings.FireRadius = math.max(10, values[1])
		return ("Blimps aim up to %s studs from themselves."):format(r(settings.FireRadius))
	elseif word == "radius" then
		if not values[1] then
			return "Usage: /blimps radius <studs>"
		end
		settings.Area.Radius = math.max(20, values[1])
		return ("Battlefield radius: %s studs."):format(r(settings.Area.Radius))
	elseif word == "speed" then
		if not values[1] then
			return "Usage: /blimps speed <studs per second>"
		end
		settings.Speed = math.clamp(values[1], 1, 200)
		return ("Blimp speed: %s."):format(r(settings.Speed))
	elseif word == "here" then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return "I need a body to stand on."
		end
		settings.Area.Center = root.Position
		return ("Battlefield centre set to where you stand (%s, %s, %s)."):format(r(root.Position.X), r(root.Position.Y), r(root.Position.Z))
	elseif word == "model" then
		local name = (rest or ""):match("^%s*(%S+)")
		if not name then
			return "Usage: /blimps model <Name>  (a model in ServerStorage/Blimps; 'Blimp' is the default)"
		end
		settings.Model = name
		return ("New blimps use the model '%s' (placeholder if it doesn't exist)."):format(name)
	elseif word == "status" then
		return ("Blimps %s | alive %s/%s | arrive every %s-%ss | stay %s-%ss | fire every %s-%ss | %s-%s shells | range %s | radius %s | alt %s-%s | speed %s | model %s"):format(
			if enabled then "ON" else "OFF",
			r(#blimps),
			r(settings.MaxAlive),
			r(settings.SpawnEvery.Min), r(settings.SpawnEvery.Max),
			r(settings.StayFor.Min), r(settings.StayFor.Max),
			r(settings.FireEvery.Min), r(settings.FireEvery.Max),
			r(settings.Shells.Min), r(settings.Shells.Max),
			r(settings.FireRadius),
			r(settings.Area.Radius),
			r(settings.Altitude.Min), r(settings.Altitude.Max),
			r(settings.Speed),
			settings.Model
		)
	end
	return "Usage: " .. HELP
end

return BlimpService
