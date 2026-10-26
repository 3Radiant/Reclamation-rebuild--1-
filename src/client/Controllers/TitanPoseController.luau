--[[
	TitanPoseController (client)
	Titans tilt their torso and head up / down to follow where the camera looks.

	  * Your own Titan reads the camera pitch directly and tells the server (TitanLook) a few
	    times a second; the server stores it on the Titan as the "LookPitch" attribute.
	  * Every Titan (yours and other players') then bends its Waist and Neck joints toward that
	    pitch, smoothly, every frame on this client.

	Works on any R15 Titan with the standard joints (UpperTorso/Waist, Head/Neck), including
	custom models. Tuning: Config.Titan.Look.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local Remotes = require(Shared.Remotes)
local TitanConfigs = require(Shared.Configs.TitanConfigs)

local CameraController = require(script.Parent.CameraController)

local settings = GameConfig.Titan.Look
local player = Players.LocalPlayer

local TitanPoseController = {}

type Arm = {
	Shoulder: Motor6D?,
	Elbow: Motor6D?,
	ShoulderC0: CFrame,
	ElbowC0: CFrame,
	S: number,
	E: number,
}

type Entry = {
	Model: Model,
	Waist: Motor6D?,
	Neck: Motor6D?,
	WaistC0: CFrame,
	NeckC0: CFrame,
	Angle: number,
	Left: Arm,
	Right: Arm,
}

-- { shoulder, elbow } in degrees (positive = raised forward / bent up)
local POSE_HOLD = { 65, 75 }
local POSE_KEYS = {
	Reach = { { 0, { 0, 0 } }, { 1, { 85, 12 } } },
	Eat = { { 0, POSE_HOLD }, { 0.45, { 105, 128 } }, { 0.7, { 110, 135 } }, { 1, POSE_HOLD } },
	Crush = { { 0, POSE_HOLD }, { 0.4, { 70, 110 } }, { 0.55, { 72, 140 } }, { 1, POSE_HOLD } },
}

local function sampleKeys(keys: { any }, a: number): (number, number)
	a = math.clamp(a, 0, 1)
	for i = 2, #keys do
		local prev, nextKey = keys[i - 1], keys[i]
		if a <= nextKey[1] then
			local t = (a - prev[1]) / math.max(1e-4, nextKey[1] - prev[1])
			return prev[2][1] + (nextKey[2][1] - prev[2][1]) * t, prev[2][2] + (nextKey[2][2] - prev[2][2]) * t
		end
	end
	local last = keys[#keys][2]
	return last[1], last[2]
end

local function makeArm(upperArm: Instance?, lowerArm: Instance?, side: string): Arm
	local shoulder = upperArm and upperArm:FindFirstChild(side .. "Shoulder")
	local elbow = lowerArm and lowerArm:FindFirstChild(side .. "Elbow")
	return {
		Shoulder = if shoulder and shoulder:IsA("Motor6D") then shoulder else nil,
		Elbow = if elbow and elbow:IsA("Motor6D") then elbow else nil,
		ShoulderC0 = if shoulder and shoulder:IsA("Motor6D") then shoulder.C0 else CFrame.identity,
		ElbowC0 = if elbow and elbow:IsA("Motor6D") then elbow.C0 else CFrame.identity,
		S = 0,
		E = 0,
	}
end

local entries: { [Model]: Entry } = {}

local function register(model: Instance)
	if not model:IsA("Model") or entries[model] or model:GetAttribute("IsTitan") ~= true then
		return
	end
	task.spawn(function()
		local upper = model:WaitForChild("UpperTorso", 10)
		local head = model:WaitForChild("Head", 10)
		if not upper or not head or not model:IsDescendantOf(Workspace) then
			return
		end
		local waist = upper:FindFirstChild("Waist")
		local neck = head:FindFirstChild("Neck")
		entries[model] = {
			Model = model,
			Waist = if waist and waist:IsA("Motor6D") then waist else nil,
			Neck = if neck and neck:IsA("Motor6D") then neck else nil,
			WaistC0 = if waist and waist:IsA("Motor6D") then waist.C0 else CFrame.identity,
			NeckC0 = if neck and neck:IsA("Motor6D") then neck.C0 else CFrame.identity,
			Angle = 0,
			Left = makeArm(model:FindFirstChild("LeftUpperArm"), model:FindFirstChild("LeftLowerArm"), "Left"),
			Right = makeArm(model:FindFirstChild("RightUpperArm"), model:FindFirstChild("RightLowerArm"), "Right"),
		}
	end)
end

local function targetPitch(model: Model): number
	local pitch: number
	if model == player.Character then
		pitch = CameraController.getPitch()
	else
		pitch = model:GetAttribute("LookPitch") or 0
	end
	pitch *= settings.Strength
	return math.clamp(pitch, -settings.MaxDown, settings.MaxUp)
end

local function armTarget(model: Model, side: string): (number, number, boolean)
	local state = model:GetAttribute("Hand_" .. side)
	if state == nil or state == "Idle" then
		return 0, 0, false
	end
	local config = TitanConfigs[model:GetAttribute("TitanName")]
	local animations = config and config.Animations
	if animations and animations[state .. side] then
		return 0, 0, false -- a real animation is playing this one
	end
	local s, e = POSE_HOLD[1], POSE_HOLD[2]
	local keys = POSE_KEYS[state]
	if keys then
		local grab = GameConfig.Titan.Grab
		local duration = if state == "Reach" then grab.ReachTime elseif state == "Eat" then grab.EatTime else grab.CrushTime
		local started = model:GetAttribute("HandT_" .. side) or 0
		s, e = sampleKeys(keys, (Workspace:GetServerTimeNow() - started) / duration)
	end
	return math.rad(s), math.rad(e), true
end

local calibration: { [Humanoid]: { Base: number, Offset: number } } = {}

local function lowestFootY(model: Model): number?
	local lowest: number? = nil
	for _, name in { "LeftFoot", "RightFoot" } do
		local foot = model:FindFirstChild(name)
		if foot and foot:IsA("BasePart") then
			local half = foot.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local y = foot.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)).Y
						if lowest == nil or y < lowest then
							lowest = y
						end
					end
				end
			end
		end
	end
	return lowest
end

local function calibrateIdle(model: Model, dt: number)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart
	if not humanoid or not root then
		return
	end
	local data = calibration[humanoid]
	if not data then
		data = { Base = humanoid.HipHeight, Offset = 0 }
		calibration[humanoid] = data
	end

	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local idle = grounded and humanoid.MoveDirection.Magnitude < 0.05 and root.AssemblyLinearVelocity.Magnitude < 2

	if idle then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { model }
		local height: number = model:GetAttribute("TitanHeight") or 45
		local hit = Workspace:Raycast(root.Position, Vector3.new(0, -height * 2, 0), params)
		local footY = lowestFootY(model)
		if hit and footY then
			local sunk = hit.Position.Y - footY -- positive = feet are under the ground
			data.Offset = math.clamp(data.Offset + sunk * math.min(1, dt * 4), -height * 0.2, height * 0.4)
		end
	end

	local goal = data.Base + (if idle then data.Offset else 0)
	humanoid.HipHeight += (goal - humanoid.HipHeight) * math.min(1, dt * 8)
end

function TitanPoseController.start()
	if not settings.Enabled then
		return
	end

	for _, child in Workspace:GetChildren() do
		register(child)
	end
	Workspace.ChildAdded:Connect(register)

	-- Tell the server where we are looking (only while we are a Titan)
	local lastSent, sinceSend = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		sinceSend += dt
		local character = player.Character
		if sinceSend < settings.SendRate or not character or character:GetAttribute("IsTitan") ~= true then
			return
		end
		sinceSend = 0
		local pitch = CameraController.getPitch()
		if math.abs(pitch - lastSent) > 0.02 then
			lastSent = pitch
			Remotes.TitanLook:FireServer(pitch)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local alpha = 1 - math.exp(-settings.Smoothing * dt)
		for model, entry in entries do
			if not model:IsDescendantOf(Workspace) or model:GetAttribute("IsTitan") ~= true then
				entries[model] = nil
				continue
			end
			entry.Angle += (targetPitch(model) - entry.Angle) * alpha
			-- Negative pitch (looking down) bows the body forward: rotate about the joint's X axis
			if entry.Waist then
				entry.Waist.C0 = entry.WaistC0 * CFrame.Angles(entry.Angle * settings.WaistShare, 0, 0)
			end
			if entry.Neck then
				entry.Neck.C0 = entry.NeckC0 * CFrame.Angles(entry.Angle * (1 - settings.WaistShare), 0, 0)
			end

			for side, arm in { Left = entry.Left, Right = entry.Right } do
				local s, e, active = armTarget(model, side)
				local follow = 1 - math.exp(-16 * dt)
				arm.S += (s - arm.S) * follow
				arm.E += (e - arm.E) * follow
				if arm.Shoulder then
					arm.Shoulder.C0 = arm.ShoulderC0 * CFrame.Angles(arm.S, 0, 0)
					if active then
						arm.Shoulder.Transform = arm.Shoulder.Transform:Lerp(CFrame.identity, 0.85)
					end
				end
				if arm.Elbow then
					arm.Elbow.C0 = arm.ElbowC0 * CFrame.Angles(arm.E, 0, 0)
					if active then
						arm.Elbow.Transform = arm.Elbow.Transform:Lerp(CFrame.identity, 0.85)
					end
				end
			end

			if model == player.Character and GameConfig.Titan.IdleHipCalibration then
				calibrateIdle(model, dt)
			end
		end
	end)
end

return TitanPoseController
