--[[
	ArtilleryController (client)
	While the Artillery Signal tool is equipped: a circle follows your mouse on the
	ground (green = in range and ready, red = out of range / reloading). Click to call the
	barrage. The server re-checks range and cooldown; this is only the aiming UI.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtilleryConfigs = require(Shared.Configs.ArtilleryConfigs)
local Remotes = require(Shared.Remotes)

local CharacterController = require(script.Parent.CharacterController)
local ThoughtController = require(script.Parent.ThoughtController)
local Aim = require(script.Parent.Parent.Gun.Aim)

local player = Players.LocalPlayer
local rng = Random.new()

local ArtilleryController = {}

local active: { Tool: Tool, Config: any, Connections: { RBXScriptConnection } }? = nil
local reticle: Part? = nil
local bound = setmetatable({}, { __mode = "k" }) :: { [Instance]: boolean }
local lastNagAt = 0

local READY_COLOR = Color3.fromRGB(110, 255, 140)
local BLOCKED_COLOR = Color3.fromRGB(255, 80, 70)

function ArtilleryController.getActive()
	return active
end

-- seconds until the tool can be used again (0 = ready)
function ArtilleryController.getCooldown(): number
	if not active then
		return 0
	end
	return math.max(0, (active.Tool:GetAttribute("ReadyAt") or 0) - Workspace:GetServerTimeNow())
end

local function groundDistance(position: Vector3): number
	local root = CharacterController.getRoot()
	if not root then
		return math.huge
	end
	return ((position - root.Position) * Vector3.new(1, 0, 1)).Magnitude
end

local function inRange(config: any, position: Vector3): boolean
	local distance = groundDistance(position)
	return distance >= config.MinRange and distance <= config.MaxRange
end

----------------------------------------------------------------------
-- Reticle
----------------------------------------------------------------------

local function createReticle(config: any)
	-- Just a small aiming ring: the real danger zone is random and is never shown
	local diameter = 6
	local part = Instance.new("Part")
	part.Name = "ArtilleryReticle"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.25, diameter, diameter)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Transparency = 0.55
	part.Color = BLOCKED_COLOR
	part.Parent = Workspace
	reticle = part
end

local function destroyReticle()
	if reticle then
		reticle:Destroy()
		reticle = nil
	end
end

local function updateReticle()
	local gun = active
	local character = CharacterController.getCharacter()
	if not gun or not reticle or not character then
		return
	end
	local target = Aim.getMouseWorldPosition({ character })
	reticle.CFrame = CFrame.new(target + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	local ready = ArtilleryController.getCooldown() <= 0 and inRange(gun.Config, target)
	reticle.Color = if ready then READY_COLOR else BLOCKED_COLOR
end

----------------------------------------------------------------------
-- Calling the strike
----------------------------------------------------------------------

local function nag(text: string)
	local now = os.clock()
	if now - lastNagAt > 1.5 then
		lastNagAt = now
		ThoughtController.push(text, "System")
	end
end

local function call()
	local gun = active
	local character = CharacterController.getCharacter()
	if not gun or not character then
		return
	end
	local config = gun.Config

	if ArtilleryController.getCooldown() > 0 then
		nag(config.CooldownThought)
		return
	end

	local target = Aim.getMouseWorldPosition({ character })
	if not inRange(config, target) then
		nag(config.OutOfRangeThought)
		return
	end

	Remotes.ArtilleryCall:FireServer(gun.Tool, target)
	ThoughtController.push(config.CallThoughts[rng:NextInteger(1, #config.CallThoughts)], "System")
end

----------------------------------------------------------------------
-- Equip / unequip
----------------------------------------------------------------------

local function teardown()
	if active then
		for _, connection in active.Connections do
			connection:Disconnect()
		end
	end
	active = nil
	destroyReticle()
end

local function onEquipped(tool: Tool)
	local config = ArtilleryConfigs[tool:GetAttribute("ArtilleryId")]
	if not config or CharacterController.isTitan() then
		return
	end
	teardown()
	active = { Tool = tool, Config = config, Connections = {} }
	createReticle(config)
end

local function bindTool(tool: Instance)
	if not tool:IsA("Tool") or bound[tool] or tool:GetAttribute("ArtilleryId") == nil then
		return
	end
	bound[tool] = true

	tool.Equipped:Connect(function()
		onEquipped(tool)
	end)
	tool.Unequipped:Connect(function()
		if active and active.Tool == tool then
			teardown()
		end
	end)
	if tool.Parent == player.Character then
		onEquipped(tool)
	end
end

local function watchCharacter(character: Model)
	teardown()
	if character:GetAttribute("IsTitan") then
		return
	end
	local backpack = player:WaitForChild("Backpack")
	for _, child in backpack:GetChildren() do
		bindTool(child)
	end
	backpack.ChildAdded:Connect(bindTool)
	for _, child in character:GetChildren() do
		bindTool(child)
	end
	character.ChildAdded:Connect(bindTool)
end

function ArtilleryController.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and active and input.UserInputType == Enum.UserInputType.MouseButton1 then
			call()
		end
	end)
	RunService.RenderStepped:Connect(updateReticle)
	CharacterController.onCharacterChanged(watchCharacter)
end

return ArtilleryController
