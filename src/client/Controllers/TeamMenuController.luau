--[[
	TeamMenuController (client)
	The "Choose your side" menu. Opens automatically when you join (no team yet) and any time
	with /team. Two plain columns - Eldian and Marleyan - with a tagline and player count. Click one to join; the server checks the balance rule and
	spawns you in (RoundService).

	Change sides later with /team (only between battles, or while you're dead). Esc closes the
	menu if you already have a side. Names, colours and emblems: Config.Teams.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local settings = GameConfig.Teams

local TeamMenuController = {}

local gui: ScreenGui
local dim: Frame
local stage: Frame
local blur: BlurEffect
local titleLabel: TextLabel
local subtitle: TextLabel
local closeHint: TextLabel
local cards: { [string]: { Frame: Frame, Count: TextLabel, Button: TextButton, Current: TextLabel } } = {}
local visible = false

local function currentTeamName(): string?
	local team = player.Team
	if team and settings[team.Name] then
		return team.Name
	end
	return nil
end

local function count(name: string): number
	local total = 0
	for _, other in Players:GetPlayers() do
		if other.Team and other.Team.Name == name then
			total += 1
		end
	end
	return total
end

local function refresh()
	local mine = currentTeamName()
	for name, card in cards do
		local n = count(name)
		card.Count.Text = ("%d %s%s"):format(n, if n == 1 then "player" else "players", if mine == name then "  -  your side" else "")
		card.Button.Text = if mine == name then "Joined" else "Join"
		card.Button.Active = mine ~= name
		card.Button.TextTransparency = if mine == name then 0.5 else 0
	end
	closeHint.Visible = mine ~= nil
	titleLabel.Text = if mine then "Change side" else "Choose a side"
	subtitle.Text = if mine then "You can switch between battles, or while you are down." else ""
end

local function setVisible(show: boolean)
	if visible == show then
		return
	end
	visible = show
	if show then
		refresh()
		gui.Enabled = true
		dim.BackgroundTransparency = 1
		TweenService:Create(dim, TweenInfo.new(0.35), { BackgroundTransparency = 0.35 }):Play()
		TweenService:Create(blur, TweenInfo.new(0.35), { Size = 8 }):Play()
	else
		TweenService:Create(blur, TweenInfo.new(0.3), { Size = 0 }):Play()
		TweenService:Create(dim, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		task.delay(0.3, function()
			if not visible then
				gui.Enabled = false
			end
		end)
	end
end

function TeamMenuController.toggle()
	setVisible(not visible)
end

-- /team opens the menu (client-side command)
function TeamMenuController.tryLocal(name: string): boolean
	if name:lower() == "team" then
		setVisible(true)
		return true
	end
	return false
end

local function buildCard(name: string, index: number)
	local config = settings[name]
	local x = if index == 1 then -160 else 160

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(280, 190)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, x, 0.5, 0)
	frame.BackgroundTransparency = 1
	frame.Parent = stage

	local function label(y: number, h: number, content: string, size: number, color: Color3, font: Enum.Font): TextLabel
		local l = Instance.new("TextLabel")
		l.Position = UDim2.fromOffset(0, y)
		l.Size = UDim2.new(1, 0, 0, h)
		l.BackgroundTransparency = 1
		l.Font = font
		l.Text = content
		l.TextSize = size
		l.TextColor3 = color
		l.TextWrapped = true
		l.Parent = frame
		return l
	end

	label(0, 30, config.Display, 24, Color3.fromRGB(235, 235, 235), Enum.Font.GothamMedium)
	label(32, 40, config.Tagline, 14, Color3.fromRGB(150, 153, 160), Enum.Font.Gotham)
	local countLabel = label(80, 20, "", 13, Color3.fromRGB(120, 123, 130), Enum.Font.Gotham)
	local current = countLabel -- the count line doubles as the "current side" note

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, 0, 0, 120)
	button.Size = UDim2.fromOffset(160, 36)
	button.BackgroundTransparency = 1
	button.TextColor3 = Color3.fromRGB(235, 235, 235)
	button.Font = Enum.Font.Gotham
	button.TextSize = 15
	button.Text = "Join"
	button.AutoButtonColor = false
	button.Parent = frame
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.fromRGB(235, 235, 235)
	outline.Transparency = 0.6
	outline.Thickness = 1
	outline.Parent = button
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 4)
	round.Parent = button

	button.MouseEnter:Connect(function()
		if button.Active then
			outline.Transparency = 0.1
		end
	end)
	button.MouseLeave:Connect(function()
		outline.Transparency = 0.6
	end)
	button.Activated:Connect(function()
		if button.Active then
			Remotes.TeamSelect:FireServer(name)
		end
	end)

	cards[name] = { Frame = frame, Count = countLabel, Button = button, Current = current }
end

function TeamMenuController.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "TeamMenu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 70
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	blur = Instance.new("BlurEffect")
	blur.Name = "TeamMenuBlur"
	blur.Size = 0
	blur.Parent = Lighting

	dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Parent = gui

	-- Everything lives on a fixed-size stage that scales down on small screens
	stage = Instance.new("Frame")
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromOffset(760, 300)
	stage.BackgroundTransparency = 1
	stage.Parent = dim
	local scale = Instance.new("UIScale")
	scale.Parent = stage
	local function fit()
		local size = gui.AbsoluteSize
		scale.Scale = math.clamp(math.min((size.X - 30) / 760, (size.Y - 30) / 300), 0.45, 1)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	titleLabel = Instance.new("TextLabel")
	titleLabel.AnchorPoint = Vector2.new(0.5, 0)
	titleLabel.Position = UDim2.new(0.5, 0, 0.5, -130)
	titleLabel.Size = UDim2.fromOffset(700, 30)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.Gotham
	titleLabel.TextSize = 16
	titleLabel.TextColor3 = Color3.fromRGB(170, 173, 180)
	titleLabel.Parent = stage
	subtitle = Instance.new("TextLabel")
	subtitle.AnchorPoint = Vector2.new(0.5, 0)
	subtitle.Position = UDim2.new(0.5, 0, 0.5, -104)
	subtitle.Size = UDim2.fromOffset(700, 24)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 13
	subtitle.TextColor3 = Color3.fromRGB(170, 176, 188)
	subtitle.Parent = stage
	closeHint = Instance.new("TextLabel")
	closeHint.AnchorPoint = Vector2.new(0.5, 0)
	closeHint.Position = UDim2.new(0.5, 0, 0.5, 120)
	closeHint.Size = UDim2.fromOffset(700, 22)
	closeHint.BackgroundTransparency = 1
	closeHint.Font = Enum.Font.Gotham
	closeHint.TextSize = 12
	closeHint.TextColor3 = Color3.fromRGB(140, 146, 158)
	closeHint.Text = "Esc to close"
	closeHint.Visible = false
	closeHint.Parent = stage

	for index, name in settings.Order do
		buildCard(name, index)
	end

	-- Open for new arrivals once they have no team; close when they get one.
	local function onTeamChanged()
		if currentTeamName() then
			setVisible(false)
		end
		refresh()
	end
	player:GetPropertyChangedSignal("Team"):Connect(onTeamChanged)
	task.delay(1, function()
		if not currentTeamName() then
			setVisible(true)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if visible and input.KeyCode == Enum.KeyCode.Escape and currentTeamName() then
			setVisible(false)
		end
	end)

	-- Keep the player counts live while the menu is open
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if visible and accumulator > 0.5 then
			accumulator = 0
			refresh()
		end
	end)
end

return TeamMenuController
