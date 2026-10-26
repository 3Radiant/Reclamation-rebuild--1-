--[[
	CameraController (client) - fully custom camera.

	Human mode : the normal Roblox third-person camera: centred behind you, focused on your
	             head. Hold RIGHT MOUSE to look (the cursor stays free so you can aim at it).
	             Scroll to zoom.
	Titan mode : mouse locked to centre, high camera scaled to the Titan's height, and the
	             Titan turns to face wherever the camera points.

	The mode is read from the character itself every frame (the "IsTitan" attribute the server
	sets), so the camera can never be left in the wrong mode after shifting or turning back.

	Aiming: GunController passes the gun's config; AimFov / AimZoom / AimShoulder in it decide
	what the camera does while aiming (nil = no change).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local CameraConfig = GameConfig.Camera

local player = Players.LocalPlayer

local CameraController = {}

local mode = "Human"
local trackedCharacter: Model? = nil
local titanHeight = 45
local titanHeadY = 0 -- head height above the root (smoothed), measured from the Head part
local aiming = false
local aimSettings: any = nil
local yaw = 0
local pitch = math.rad(-12)
local zoom = CameraConfig.DefaultZoom
local shownZoom = zoom
local minZoom, maxZoom = CameraConfig.MinZoom, CameraConfig.MaxZoom
local rightMouseHeld = false

local baseFov = GameConfig.FovWalk
local currentFov = GameConfig.FovWalk
local fovKick = 0 -- temporary extra FOV (see punch)
local fovBias = 0 -- steady FOV offset set by other systems (anxiety heartbeat)
local shakeAmount = 0 -- decaying camera shake (see shake)
local tremor = 0 -- constant small shake (anxiety)
local shakeRng = Random.new()
local recoilPitch = 0 -- decaying upward kick (radians), see recoil()
local recoilYaw = 0

-- Cinematic focus (intros): the camera turns to look at a player and slowly closes in
local focusPlayer: Player? = nil
local focusActive = false
local focusBlend = 0 -- 0 = normal camera .. 1 = fully on the subject
local focusStartedAt = 0
local focus = { PanTime = 1.6, ReturnTime = 1.4, ZoomSeconds = 6, Zoom = 0.45 }

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function getRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

-- Called automatically when the character (or its type) changes; you rarely need it.
function CameraController.setMode(newMode: string, height: number?)
	mode = newMode
	if mode == "Titan" then
		titanHeight = height or 45
		minZoom = titanHeight * CameraConfig.TitanZoomMinScale
		maxZoom = titanHeight * CameraConfig.TitanZoomMaxScale
		zoom = (minZoom + maxZoom) / 2
		pitch = CameraConfig.TitanDefaultPitch
		local head = trackedCharacter and trackedCharacter:FindFirstChild("Head")
		local r = getRoot()
		titanHeadY = if head and r and head:IsA("BasePart") then head.Position.Y - r.Position.Y else titanHeight * 0.4
	else
		minZoom, maxZoom = CameraConfig.MinZoom, CameraConfig.MaxZoom
		zoom = CameraConfig.DefaultZoom
		pitch = math.rad(-12)
	end
	shownZoom = zoom

	local root = getRoot()
	if root then
		yaw = select(2, root.CFrame:ToOrientation())
	end
end

-- settings = the gun's config table (AimFov / AimZoom / AimShoulder), or nil
function CameraController.setAiming(value: boolean, settings: any?)
	aiming = value
	aimSettings = if value then settings else nil
end

-- FOV the camera settles on when not aiming (CharacterController: 70 walking, 80 running)
function CameraController.setBaseFov(fov: number)
	baseFov = fov
end

-- Momentary FOV kick that settles back on its own. Negative = pinch in (used for kill hits).
function CameraController.punch(amount: number)
	fovKick = amount
end

-- Camera shake that decays by itself (explosions). ~1 = a rumble, 5 = very violent.
function CameraController.shake(amount: number)
	shakeAmount = math.max(shakeAmount, amount)
end

-- Steady small shake (0 = none), e.g. trembling hands while anxious
function CameraController.setTremor(amount: number)
	tremor = amount
end

-- Steady FOV offset in degrees (negative = narrower). Cleared by setting 0.
function CameraController.setFovBias(degrees: number)
	fovBias = degrees
end

-- Gun recoil: the view kicks up (and slightly sideways) then settles. Degrees.
function CameraController.recoil(degrees: number)
	recoilPitch += math.rad(degrees)
	recoilYaw += math.rad(shakeRng:NextNumber(-0.3, 0.3) * degrees)
end

-- Turn the camera to face `target` and slowly zoom toward them. Normal control comes back
-- by itself after CameraController.releaseFocus(). opts: PanTime, ReturnTime, ZoomSeconds, Zoom (0..1)
function CameraController.focusOn(target: Player, opts: any?)
	focusPlayer = target
	focusActive = true
	focusStartedAt = os.clock()
	focus = { PanTime = 1.6, ReturnTime = 1.4, ZoomSeconds = 6, Zoom = 0.45 }
	if opts then
		for key, value in opts do
			focus[key] = value
		end
	end
end

function CameraController.releaseFocus()
	focusActive = false
end

-- Current look pitch in radians (negative = looking down). Used to tilt the Titan's body.
function CameraController.getPitch(): number
	return pitch
end

function CameraController.getMode(): string
	return mode
end

----------------------------------------------------------------------
-- Frame update
----------------------------------------------------------------------

local function updateFov(camera: Camera, dt: number)
	local target = baseFov
	if aiming and aimSettings and aimSettings.AimFov then
		target = aimSettings.AimFov
	end
	currentFov += (target - currentFov) * (1 - math.exp(-9 * dt))
	fovKick *= math.exp(-8 * dt)
	camera.FieldOfView = currentFov + fovKick + fovBias
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local character = player.Character
	local root = getRoot()
	if not character or not root then
		trackedCharacter = nil
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default -- between bodies, give the mouse back
		return
	end

	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	-- Follow the character, not stale state: re-initialise whenever the body or its type changes
	local wanted = if character:GetAttribute("IsTitan") == true then "Titan" else "Human"
	if character ~= trackedCharacter or wanted ~= mode then
		trackedCharacter = character
		CameraController.setMode(wanted, character:GetAttribute("TitanHeight"))
	end

	-- Mouse behaviour
	if mode == "Titan" then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	elseif rightMouseHeld then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end

	-- Look
	local delta = UserInputService:GetMouseDelta()
	if mode == "Titan" or rightMouseHeld then
		yaw -= delta.X * CameraConfig.Sensitivity
		pitch = math.clamp(pitch - delta.Y * CameraConfig.Sensitivity, -CameraConfig.MaxPitch, CameraConfig.MaxPitch)
	end

	-- Where the camera orbits and how far back it sits
	local focusOffset: Vector3, shoulder: Vector3, targetZoom: number
	if mode == "Titan" then
		focusOffset = Vector3.zero
		shoulder = Vector3.zero
		targetZoom = zoom
	else
		focusOffset = CameraConfig.HeadOffset
		shoulder = Vector3.zero
		targetZoom = zoom
		if aiming and aimSettings then
			shoulder = aimSettings.AimShoulder or Vector3.zero
			targetZoom = aimSettings.AimZoom or zoom
		end
	end
	shownZoom += (targetZoom - shownZoom) * (1 - math.exp(-10 * dt))

	local rotation = CFrame.fromOrientation(pitch, yaw, 0)
	local focus: Vector3
	local desired: Vector3
	if mode == "Titan" then
		-- Orbit the HEAD, then lift the camera so the head sits at TitanHeadScreenY on screen:
		-- a head at depth d appears (0.5 - screenY) * 2 * tan(fov/2) * d below the centre.
		local head = character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			titanHeadY += ((head.Position.Y - root.Position.Y) - titanHeadY) * (1 - math.exp(-3 * dt))
		end
		focus = root.Position + Vector3.new(0, titanHeadY, 0)
		local lift = (0.5 - CameraConfig.TitanHeadScreenY) * 2 * math.tan(math.rad(currentFov) / 2)
		desired = (CFrame.new(focus) * rotation * CFrame.new(0, lift * shownZoom, shownZoom)).Position
	else
		focus = root.Position + focusOffset
		desired = (CFrame.new(focus) * rotation * CFrame.new(shoulder.X, shoulder.Y, shownZoom)).Position
	end

	-- Don't let walls put the camera inside geometry (human mode only)
	if mode == "Human" then
		params.FilterDescendantsInstances = { character }
		local toDesired = desired - focus
		local result = Workspace:Raycast(focus, toDesired, params)
		if result then
			desired = result.Position - toDesired.Unit * 0.3
		end
	end

	camera.CFrame = CFrame.new(desired) * rotation

	if recoilPitch ~= 0 or recoilYaw ~= 0 then
		camera.CFrame *= CFrame.Angles(recoilPitch, recoilYaw, 0)
		recoilPitch *= math.exp(-9 * dt)
		recoilYaw *= math.exp(-9 * dt)
		if math.abs(recoilPitch) < 1e-4 then
			recoilPitch, recoilYaw = 0, 0
		end
	end

	shakeAmount *= math.exp(-3.2 * dt)
	local amplitude = shakeAmount + tremor
	if amplitude > 0.002 then
		camera.CFrame *= CFrame.Angles(
			shakeRng:NextNumber(-1, 1) * amplitude * 0.012,
			shakeRng:NextNumber(-1, 1) * amplitude * 0.012,
			shakeRng:NextNumber(-1, 1) * amplitude * 0.006
		)
	end

	-- Cinematic focus on another player (blended in / out so it never snaps)
	if focusActive or focusBlend > 0 then
		local step = dt / (if focusActive then math.max(focus.PanTime, 0.05) else math.max(focus.ReturnTime, 0.05))
		focusBlend = math.clamp(focusBlend + (if focusActive then step else -step), 0, 1)
		local subject = focusPlayer and focusPlayer.Character
		local subjectRoot = subject and subject:FindFirstChild("HumanoidRootPart")
		if subject and subjectRoot and subjectRoot:IsA("BasePart") then
			local isTitan = subject:GetAttribute("IsTitan") == true
			local height: number = subject:GetAttribute("TitanHeight") or 6
			local aim = subjectRoot.Position + Vector3.new(0, if isTitan then height * 0.45 else 1.5, 0)
			local cf = camera.CFrame
			local toAim = aim - cf.Position
			local distance = toAim.Magnitude
			if distance > 1 then
				local progress = math.clamp((os.clock() - focusStartedAt) / math.max(focus.ZoomSeconds, 0.1), 0, 1)
				progress = progress * progress * (3 - 2 * progress)
				local closest = math.min(distance, if isTitan then height * 0.9 else 7) -- never inside them
				local wanted = math.max(distance * (1 - focus.Zoom * progress), closest)
				local cinematic = CFrame.lookAt(aim - toAim.Unit * wanted, aim)
				local eased = focusBlend * focusBlend * (3 - 2 * focusBlend)
				camera.CFrame = cf:Lerp(cinematic, eased)
			end
		end
	end

	updateFov(camera, dt)

	-- Titan turns to face where the camera is pointing
	if mode == "Titan" then
		local goal = CFrame.new(root.Position) * CFrame.fromOrientation(0, yaw, 0)
		root.CFrame = root.CFrame:Lerp(goal, 1 - math.exp(-14 * dt))
	end
end

----------------------------------------------------------------------

function CameraController.start()
	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			rightMouseHeld = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			rightMouseHeld = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		local step = mode == "Titan" and titanHeight * 0.1 or 1
		zoom = math.clamp(zoom - input.Position.Z * step, minZoom, maxZoom)
	end)

	RunService:BindToRenderStep("ReclamationCamera", Enum.RenderPriority.Camera.Value, update)
end

return CameraController
