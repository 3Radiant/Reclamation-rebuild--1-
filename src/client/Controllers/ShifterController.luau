--[[
	ShifterController (client)
	  P            shift / turn back
	  Left click   Titan melee combo (server decides the combo step + damage)
	  Ability keys (e.g. Q = Harden) come from the Titan's config
	Also: locks movement during the transformation, plays the bite animation,
	plays swing animations, and applies knockback.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlayerState = require(Shared.PlayerState)
local Remotes = require(Shared.Remotes)
local GameConfig = require(Shared.Configs.Config)
local TitanConfigs = require(Shared.Configs.TitanConfigs)

local CharacterController = require(script.Parent.CharacterController)

local player = Players.LocalPlayer

local ShifterController = {}

local swingConnection: RBXScriptConnection? = nil
local dashReadyAt = 0
local dashing = false
local handConnections: { RBXScriptConnection } = {}
local handTracks: { [string]: AnimationTrack } = {}

local function inGrabMode(): boolean
	local character = CharacterController.getCharacter()
	return character ~= nil and character:GetAttribute("TitanMode") == "Grab"
end

local function isShifted(): boolean
	return PlayerState.get(player, "Shifted") == true
end

-- Short dash toward the movement keys you are holding (W/A/S/D; none = forward).
local function dash()
	local character = CharacterController.getCharacter()
	local root = CharacterController.getRoot()
	local titanConfig = character and TitanConfigs[character:GetAttribute("TitanName")]
	if not character or not root or not titanConfig or dashing or os.clock() < dashReadyAt then
		return
	end
	local settings = table.clone(GameConfig.Titan.Dash)
	if titanConfig.Dash then
		for key, value in titanConfig.Dash do
			settings[key] = value
		end
	end
	if settings.StaminaCost > 0 and not CharacterController.spendStamina(settings.StaminaCost) then
		return
	end

	local x = (UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
	local z = (UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0)
	if x == 0 and z == 0 then
		z = -1
	end
	local direction = root.CFrame:VectorToWorldSpace(Vector3.new(x, 0, z))
	direction = Vector3.new(direction.X, 0, direction.Z).Unit

	local height: number = character:GetAttribute("TitanHeight") or 45
	local speed = settings.Distance * height / settings.Duration
	dashing = true
	dashReadyAt = os.clock() + settings.Cooldown

	local id = titanConfig.Animations and titanConfig.Animations.Dash
	local track = id and CharacterController.loadAnimation(id, Enum.AnimationPriority.Action3)
	if track then
		track.Looped = false
		track:Play(0.05)
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = root
	local push = Instance.new("LinearVelocity")
	push.Name = "DashVelocity"
	push.Attachment0 = attachment
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	push.PrimaryTangentAxis = Vector3.xAxis
	push.SecondaryTangentAxis = Vector3.zAxis
	push.MaxForce = math.huge
	push.PlaneVelocity = Vector2.new(direction.X * speed, direction.Z * speed)
	push.Parent = root

	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - started
		if elapsed >= settings.Duration or root.Parent == nil then
			connection:Disconnect()
			push:Destroy()
			attachment:Destroy()
			dashing = false
			return
		end
		local fade = 1 - 0.5 * (elapsed / settings.Duration)
		push.PlaneVelocity = Vector2.new(direction.X * speed * fade, direction.Z * speed * fade)
	end)
end

local function onInput(input: InputObject, processed: boolean)
	if processed then
		return
	end

	if input.KeyCode == Enum.KeyCode.P then
		if not PlayerState.get(player, "Transforming") then
			Remotes.ShiftToggle:FireServer()
		end
		return
	end

	if not isShifted() or PlayerState.get(player, "Transforming") then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		Remotes.TitanM1:FireServer()
		return
	end

	local grab = GameConfig.Titan.Grab
	if input.KeyCode == grab.ModeKey then
		Remotes.TitanMode:FireServer()
		return
	end

	for arm, key in grab.UseKeys do
		if input.KeyCode == key then
			Remotes.TitanHand:FireServer("Use", arm) -- eat in Grab mode, crush in Combat mode (the server decides)
			return
		end
	end

	if inGrabMode() then
		for arm, key in grab.GrabKeys do
			if input.KeyCode == key then
				Remotes.TitanHand:FireServer("Grab", arm)
				return
			end
		end
	end

	if input.KeyCode == GameConfig.Titan.Dash.Key and not inGrabMode() then
		dash()
		return
	end

	-- Titan abilities
	local character = CharacterController.getCharacter()
	local config = character and TitanConfigs[character:GetAttribute("TitanName")]
	if config and config.Abilities then
		for abilityName, ability in config.Abilities do
			if ability.Key == input.KeyCode then
				Remotes.TitanAbility:FireServer(abilityName)
			end
		end
	end
end

-- Play the right swing animation whenever the server advances the combo
local function watchTitan(character: Model)
	if swingConnection then
		swingConnection:Disconnect()
		swingConnection = nil
	end

	for _, connection in handConnections do
		connection:Disconnect()
	end
	table.clear(handConnections)
	table.clear(handTracks)
	if not character:GetAttribute("IsTitan") then
		return
	end

	local config = TitanConfigs[character:GetAttribute("TitanName")]

	-- Optional animations: TitanConfig.Animations.GrabLeft / HoldLeft / EatLeft / CrushLeft (and Right)
	for _, arm in { "Left", "Right" } do
		table.insert(handConnections, character:GetAttributeChangedSignal("HandT_" .. arm):Connect(function()
			local old = handTracks[arm]
			if old then
				old:Stop(0.15)
				handTracks[arm] = nil
			end
			local state = character:GetAttribute("Hand_" .. arm)
			local id = config and config.Animations and state and config.Animations[state .. arm]
			local track = id and CharacterController.loadAnimation(id, Enum.AnimationPriority.Action4)
			if track then
				track.Looped = state == "Hold"
				track:Play(0.1)
				handTracks[arm] = track
			end
		end))
	end
end

-- Thin stamina bar at the bottom of the screen; only shown as a Titan while it isn't full
local function buildStaminaBar()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TitanStamina"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 0, 1, -28)
	track.Size = UDim2.fromOffset(240, 4)
	track.BackgroundColor3 = Color3.new(0, 0, 0)
	track.BackgroundTransparency = 0.6
	track.BorderSizePixel = 0
	track.Visible = false
	track.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
	fill.BorderSizePixel = 0
	fill.Parent = track

	RunService.RenderStepped:Connect(function()
		local value = CharacterController.getStamina()
		track.Visible = CharacterController.isTitan() and value < 0.999
		fill.Size = UDim2.fromScale(value, 1)
		fill.BackgroundColor3 = if CharacterController.isExhausted() then Color3.fromRGB(205, 80, 70) else Color3.fromRGB(235, 235, 235)
	end)
end

local function buildModeLabel()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TitanMode"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -40)
	label.Size = UDim2.fromOffset(300, 18)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(235, 235, 235)
	label.TextTransparency = 0.25
	label.Visible = false
	label.Parent = gui
	local grab = GameConfig.Titan.Grab
	RunService.RenderStepped:Connect(function()
		label.Visible = CharacterController.isTitan()
		if label.Visible then
			label.Text = if inGrabMode()
				then ("GRAB  -  %s / %s grab   %s / %s eat   [%s] combat"):format(grab.GrabKeys.Left.Name, grab.GrabKeys.Right.Name, grab.UseKeys.Left.Name, grab.UseKeys.Right.Name, grab.ModeKey.Name)
				else ("COMBAT  -  %s / %s crush   [%s] grab"):format(grab.UseKeys.Left.Name, grab.UseKeys.Right.Name, grab.ModeKey.Name)
		end
	end)
end

function ShifterController.start()
	UserInputService.InputBegan:Connect(onInput)
	buildStaminaBar()
	buildModeLabel()

	-- Mid-transformation: freeze and play the bite animation
	PlayerState.observe(player, "Transforming", function(transforming)
		if transforming then
			CharacterController.setLock("Transforming", {
				WalkSpeed = 0,
				NoJump = true,
				NoSprint = true,
				NoCrouch = true,
				NoAutoRotate = true,
			})
			if not isShifted() then
				CharacterController.playAction("bitehand")
			end
		else
			CharacterController.clearLock("Transforming")
		end
	end)

	CharacterController.onCharacterChanged(watchTitan)

	-- Hit by a Titan
	Remotes.Knockback.OnClientEvent:Connect(function(velocity)
		local root = CharacterController.getRoot()
		if root and typeof(velocity) == "Vector3" then
			root.AssemblyLinearVelocity = velocity
		end
	end)
end

return ShifterController
