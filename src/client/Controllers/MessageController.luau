--[[
	MessageController (client)
	Server messages (Remotes.ServerMessage, sent by MessageService):

	  Style "Round" : cinematic. Black letterbox bars slide in, then each line fades up in large
	                  serif type between two thin gold rules, one after the other, then the bars leave.
	  Style "Alert" : a compact banner near the top of the screen.

	Messages queue up, so back-to-back messages never overlap.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local TextFormat = require(Shared.TextFormat)

local player = Players.LocalPlayer

local MessageController = {}

local FADE = 0.7
local GOLD = Color3.fromRGB(214, 182, 112)

local gui: ScreenGui
local topBar: Frame
local bottomBar: Frame
local lineLabel: TextLabel
local ruleTop: Frame
local ruleBottom: Frame
local banner: Frame
local bannerText: TextLabel

type Message = { Lines: { string }, Style: string, Hold: number }
local queue: { Message } = {}
local running = false

local function tween(object: Instance, seconds: number, style: Enum.EasingStyle, direction: Enum.EasingDirection, goal: { [string]: any })
	local t = TweenService:Create(object, TweenInfo.new(seconds, style, direction), goal)
	t:Play()
	return t
end

local function playRound(message: Message, last: boolean)
	tween(topBar, 0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, { Size = UDim2.new(1, 0, 0.11, 0) })
	tween(bottomBar, 0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, { Size = UDim2.new(1, 0, 0.11, 0) })
	task.wait(0.6)

	for _, line in message.Lines do
		lineLabel.Text = TextFormat.format(line)
		lineLabel.Position = UDim2.new(0.5, 0, 0.47, 12)
		lineLabel.TextTransparency = 1
		lineLabel:FindFirstChildOfClass("UIStroke").Transparency = 1
		ruleTop.Size = UDim2.fromOffset(0, 2)
		ruleBottom.Size = UDim2.fromOffset(0, 2)

		tween(lineLabel, FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { TextTransparency = 0, Position = UDim2.new(0.5, 0, 0.47, 0) })
		tween(lineLabel:FindFirstChildOfClass("UIStroke") :: UIStroke, FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Transparency = 0.45 })
		tween(ruleTop, FADE + 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, { Size = UDim2.fromOffset(460, 2) })
		tween(ruleBottom, FADE + 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, { Size = UDim2.fromOffset(460, 2) })
		task.wait(FADE + message.Hold)

		tween(lineLabel, FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { TextTransparency = 1, Position = UDim2.new(0.5, 0, 0.47, -8) })
		tween(lineLabel:FindFirstChildOfClass("UIStroke") :: UIStroke, FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { Transparency = 1 })
		tween(ruleTop, FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { Size = UDim2.fromOffset(0, 2) })
		tween(ruleBottom, FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { Size = UDim2.fromOffset(0, 2) })
		task.wait(FADE + 0.15)
	end

	if last then -- more messages queued behind this one keep the bars up
		tween(topBar, 0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.In, { Size = UDim2.new(1, 0, 0, 0) })
		tween(bottomBar, 0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.In, { Size = UDim2.new(1, 0, 0, 0) })
		task.wait(0.8)
	end
end

local function playAlert(message: Message)
	for _, line in message.Lines do
		bannerText.Text = TextFormat.format(line)
		banner.Position = UDim2.new(0.5, 0, 0, -50)
		banner.Visible = true
		tween(banner, 0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, { Position = UDim2.new(0.5, 0, 0, 96) })
		task.wait(0.45 + message.Hold)
		tween(banner, 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { Position = UDim2.new(0.5, 0, 0, -50) })
		task.wait(0.45)
	end
	banner.Visible = false
end

local function run()
	if running then
		return
	end
	running = true
	task.spawn(function()
		while #queue > 0 do
			local message = table.remove(queue, 1) :: Message
			if message.Style == "Alert" then
				playAlert(message)
			else
				local nextIsRound = queue[1] ~= nil and queue[1].Style ~= "Alert"
				playRound(message, not nextIsRound)
			end
		end
		running = false
	end)
end

function MessageController.show(lines: { string }, style: string?, hold: number?)
	table.insert(queue, { Lines = lines, Style = style or "Round", Hold = hold or 2.6 })
	run()
end

function MessageController.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "ServerMessages"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 45
	gui.Parent = player:WaitForChild("PlayerGui")

	topBar = Instance.new("Frame")
	topBar.BackgroundColor3 = Color3.new(0, 0, 0)
	topBar.BorderSizePixel = 0
	topBar.Size = UDim2.new(1, 0, 0, 0)
	topBar.Parent = gui
	bottomBar = Instance.new("Frame")
	bottomBar.AnchorPoint = Vector2.new(0, 1)
	bottomBar.Position = UDim2.fromScale(0, 1)
	bottomBar.BackgroundColor3 = Color3.new(0, 0, 0)
	bottomBar.BorderSizePixel = 0
	bottomBar.Size = UDim2.new(1, 0, 0, 0)
	bottomBar.Parent = gui

	lineLabel = Instance.new("TextLabel")
	lineLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	lineLabel.Position = UDim2.fromScale(0.5, 0.47)
	lineLabel.Size = UDim2.new(0.86, 0, 0, 90)
	lineLabel.BackgroundTransparency = 1
	lineLabel.Font = Enum.Font.Garamond
	lineLabel.TextSize = 44
	lineLabel.RichText = true
	lineLabel.TextWrapped = true
	lineLabel.TextColor3 = Color3.fromRGB(246, 240, 226)
	lineLabel.TextTransparency = 1
	lineLabel.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 1
	stroke.Parent = lineLabel

	local function rule(yOffset: number): Frame
		local r = Instance.new("Frame")
		r.AnchorPoint = Vector2.new(0.5, 0.5)
		r.Position = UDim2.new(0.5, 0, 0.47, yOffset)
		r.Size = UDim2.fromOffset(0, 2)
		r.BackgroundColor3 = GOLD
		r.BorderSizePixel = 0
		r.Parent = gui
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = r
		return r
	end
	ruleTop = rule(-62)
	ruleBottom = rule(62)

	banner = Instance.new("Frame")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, -50)
	banner.AutomaticSize = Enum.AutomaticSize.X
	banner.Size = UDim2.fromOffset(0, 44)
	banner.BackgroundColor3 = Color3.fromRGB(16, 18, 22)
	banner.BackgroundTransparency = 0.1
	banner.BorderSizePixel = 0
	banner.Visible = false
	banner.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = banner
	local accent = Instance.new("UIStroke")
	accent.Color = GOLD
	accent.Transparency = 0.35
	accent.Parent = banner
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 22), UDim.new(0, 22)
	pad.Parent = banner
	bannerText = Instance.new("TextLabel")
	bannerText.AutomaticSize = Enum.AutomaticSize.X
	bannerText.Size = UDim2.fromOffset(0, 44)
	bannerText.BackgroundTransparency = 1
	bannerText.Font = Enum.Font.GothamMedium
	bannerText.TextSize = 18
	bannerText.RichText = true
	bannerText.TextColor3 = Color3.fromRGB(240, 238, 232)
	bannerText.Parent = banner

	Remotes.ServerMessage.OnClientEvent:Connect(function(data)
		if typeof(data) ~= "table" or typeof(data.Lines) ~= "table" then
			return
		end
		local lines = {}
		for _, line in data.Lines do
			if typeof(line) == "string" then
				table.insert(lines, line:sub(1, 140))
			end
		end
		if #lines > 0 then
			MessageController.show(lines, if typeof(data.Style) == "string" then data.Style else nil, if typeof(data.Hold) == "number" then math.clamp(data.Hold, 0.5, 10) else nil)
		end
	end)
end

return MessageController
