--[[
	R6Pose (client)
	R6 has no "hold a rifle" pose and the empty Animate script means tools just dangle. Until you
	author real gun animations, this raises the arms in code, for EVERY player holding a gun:

	  Idle   arms nearly relaxed         Ready   gun raised
	  Aiming arms straight out, rifle level (also while reloading -> Idle)

	It reads each gun's replicated "Stance" attribute, so other players see your pose too
	(your own uses the predicted stance so it feels instant). It rotates the shoulders by
	editing Motor6D.C0, which stacks on top of any animation you play.

	Automatically skipped for a gun once AnimationConfigs.Guns[<group>].aim exists, and
	switched off entirely with Config.Gun.ProceduralR6Pose = false. R6 characters only.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationConfigs = require(Shared.Configs.AnimationConfigs)
local GameConfig = require(Shared.Configs.Config)
local GunConfigs = require(Shared.Configs.GunConfigs)
local GunStates = require(Shared.Gun.GunStates)

local Stance = GunStates.Stance

local R6Pose = {}

-- Shoulder swing in radians: 0 = arm hanging, 90 degrees = arm pointing straight forward
local POSES = {
	[Stance.Idle] = { Right = math.rad(14), Left = 0 },
	[Stance.Ready] = { Right = math.rad(62), Left = math.rad(42) },
	[Stance.Aiming] = { Right = math.rad(88), Left = math.rad(84) },
}
local NO_GUN = { Right = 0, Left = 0 }
local SMOOTHING = 14

type Rig = {
	Right: Motor6D,
	Left: Motor6D,
	RightBase: CFrame,
	LeftBase: CFrame,
	RightAngle: number,
	LeftAngle: number,
}

local rigs: { [Model]: Rig } = {}
local localStance: (Tool) -> string? = function()
	return nil
end

-- Same position, rotated about the torso's X axis (forward/back swing) before the base rotation
local function swung(base: CFrame, angle: number): CFrame
	return CFrame.new(base.Position) * CFrame.Angles(angle, 0, 0) * (base - base.Position)
end

local function heldGun(character: Model): Tool?
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("GunId") ~= nil then
			return child
		end
	end
	return nil
end

local function getRig(character: Model): Rig?
	local existing = rigs[character]
	if existing then
		return existing
	end
	local torso = character:FindFirstChild("Torso")
	local right = torso and torso:FindFirstChild("Right Shoulder")
	local left = torso and torso:FindFirstChild("Left Shoulder")
	if not (right and left and right:IsA("Motor6D") and left:IsA("Motor6D")) then
		return nil
	end
	local rig: Rig = {
		Right = right,
		Left = left,
		RightBase = right.C0,
		LeftBase = left.C0,
		RightAngle = 0,
		LeftAngle = 0,
	}
	rigs[character] = rig
	return rig
end

local function targetFor(character: Model, tool: Tool)
	local config = GunConfigs[tool:GetAttribute("GunId")]
	if not config then
		return NO_GUN
	end
	local group = AnimationConfigs.Guns[config.AnimationGroup]
	if group and group.aim then
		return nil -- real animations exist: don't pose in code
	end

	local stance = localStance(tool) or tool:GetAttribute("Stance") or Stance.Idle
	if tool:GetAttribute("Reloading") then
		stance = Stance.Idle
	end
	return POSES[stance] or POSES[Stance.Idle]
end

local function release(character: Model, rig: Rig)
	rig.Right.C0 = rig.RightBase
	rig.Left.C0 = rig.LeftBase
	rigs[character] = nil
end

local function step(dt: number)
	local alpha = 1 - math.exp(-SMOOTHING * dt)

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character and humanoid and humanoid.RigType == Enum.HumanoidRigType.R6 and humanoid.Health > 0 then
			local tool = heldGun(character)
			local target = if tool then targetFor(character, tool) else NO_GUN
			local rig = if target then getRig(character) else nil
			if rig and target then
				rig.RightAngle += (target.Right - rig.RightAngle) * alpha
				rig.LeftAngle += (target.Left - rig.LeftAngle) * alpha
				if target == NO_GUN and math.abs(rig.RightAngle) < 0.003 and math.abs(rig.LeftAngle) < 0.003 then
					release(character, rig) -- fully back to normal: stop touching the motors
				else
					rig.Right.C0 = swung(rig.RightBase, rig.RightAngle)
					rig.Left.C0 = swung(rig.LeftBase, rig.LeftAngle)
				end
			end
		end
	end

	-- Forget characters that were removed
	for character, rig in rigs do
		if not character.Parent then
			rigs[character] = nil
		end
	end
end

-- getLocalStance(tool) -> the predicted stance of YOUR gun (or nil for anyone else's)
function R6Pose.start(getLocalStance: (Tool) -> string?)
	if not GameConfig.Gun.ProceduralR6Pose then
		return
	end
	localStance = getLocalStance
	RunService.RenderStepped:Connect(step)
end

return R6Pose
