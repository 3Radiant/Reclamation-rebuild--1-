--[[
	RoundController (client)
	Reads the round state the server publishes (ReplicatedStorage/RoundState) and
	  * plays the round-start SLOW MOTION: everyone's walking and animations slow down for
	    Config.Round.SlowMoDuration seconds, with a muted, cinematic colour grade
	  * shows an "eliminated" notice when your team has no lives left

	Getters used by the leaderboard:
	  RoundController.getPhase() / getRound() / getEndsAt() / getWinner()
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local PlayerState = require(Shared.PlayerState)

local CharacterController = require(script.Parent.CharacterController)

local player = Players.LocalPlayer
local settings = GameConfig.Round

local RoundController = {}

local stateValue: Configuration? = nil
local grade: ColorCorrectionEffect
local notice: TextLabel
local wasSlow = false

function RoundController.getPhase(): string
	return if stateValue then (stateValue:GetAttribute("Phase") or "Intermission") else "Intermission"
end
function RoundController.getRound(): number
	return if stateValue then (stateValue:GetAttribute("Round") or 0) else 0
end
function RoundController.getEndsAt(): number
	return if stateValue then (stateValue:GetAttribute("PhaseEndsAt") or 0) else 0
end
function RoundController.getWinner(): string
	return if stateValue then (stateValue:GetAttribute("Winner") or "") else ""
end

-- Slows every character's playing animations (everyone moves in slow motion)
local function scaleAnimations(scale: number)
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				track:AdjustSpeed(scale)
			end
		end
	end
end

local function update()
	-- Slow motion
	local untilTime = if stateValue then (stateValue:GetAttribute("SlowMoUntil") or 0) else 0
	local remaining = untilTime - Workspace:GetServerTimeNow()
	if remaining > 0 then
		-- ease out of slow-mo over the last 1.5 seconds
		local k = math.clamp(remaining / 1.5, 0, 1)
		local scale = 1 + (settings.SlowMoSpeed - 1) * k
		CharacterController.setTimeScale(scale)
		scaleAnimations(scale)
		grade.Saturation = -0.3 * k
		grade.Contrast = 0.12 * k
		grade.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(226, 232, 255), k)
		wasSlow = true
	elseif wasSlow then
		wasSlow = false
		CharacterController.setTimeScale(1)
		scaleAnimations(1)
		grade.Saturation, grade.Contrast = 0, 0
		grade.TintColor = Color3.new(1, 1, 1)
	end

	-- Eliminated notice
	local eliminated = PlayerState.get(player, "Eliminated") == true and RoundController.getPhase() == "Active"
	notice.Visible = eliminated
end

function RoundController.start()
	grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "RoundSlowMoGrade"
	grade.Parent = Lighting

	local gui = Instance.new("ScreenGui")
	gui.Name = "RoundNotices"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 12
	gui.Parent = player:WaitForChild("PlayerGui")

	notice = Instance.new("TextLabel")
	notice.AnchorPoint = Vector2.new(0.5, 1)
	notice.Position = UDim2.new(0.5, 0, 0.82, 0)
	notice.Size = UDim2.fromOffset(520, 44)
	notice.BackgroundColor3 = Color3.fromRGB(16, 18, 22)
	notice.BackgroundTransparency = 0.2
	notice.Font = Enum.Font.GothamMedium
	notice.TextSize = 17
	notice.TextColor3 = Color3.fromRGB(226, 120, 108)
	notice.Text = "ELIMINATED  -  your side has no lives left. Wait for the next battle."
	notice.Visible = false
	notice.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = notice

	task.spawn(function()
		stateValue = ReplicatedStorage:WaitForChild("RoundState", 30) :: Configuration?
	end)

	RunService.RenderStepped:Connect(update)
end

return RoundController
