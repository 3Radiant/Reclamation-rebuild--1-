--[[
	ThoughtController (client)
	Inner-thought pop-ups: small cards near the bottom centre, above the hotbar. A new
	thought appears at the bottom and every older thought slides smoothly UP to make
	room, like a grid growing upward. Each fades away after a while.

	  ThoughtController.push("text", kind?, source?)   show one locally
	  Server -> client: Remotes.Thought (/t, /thought, system messages)
	  Press J                                           check your health (HealthThoughts)

	kind: "Thought" (default) | "System" | "Overheard" (admins seeing a player's /t)
	Text supports *italic*, **bold**, ***bold italic***.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local HealthThoughts = require(Shared.Configs.HealthThoughts)
local PlayerState = require(Shared.PlayerState)
local Remotes = require(Shared.Remotes)
local TextFormat = require(Shared.TextFormat)

local CharacterController = require(script.Parent.CharacterController)

local player = Players.LocalPlayer
local settings = GameConfig.Thoughts

local ThoughtController = {}

local KIND_STYLE = {
	Thought = { Accent = Color3.fromRGB(236, 226, 200), Text = Color3.fromRGB(245, 240, 228) },
	System = { Accent = Color3.fromRGB(140, 185, 230), Text = Color3.fromRGB(225, 235, 248) },
	Overheard = { Accent = Color3.fromRGB(232, 140, 118), Text = Color3.fromRGB(248, 230, 224) },
}

local SLIDE_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local FADE_IN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

type Entry = { Frame: CanvasGroup, Height: number, Alive: boolean }

local container: Frame
local entries: { Entry } = {} -- oldest first, newest last
local rng = Random.new()
local lastHealthCheck = 0

----------------------------------------------------------------------
-- Layout: newest at the bottom, everything older stacked upward
----------------------------------------------------------------------

local function restack()
	local offset = 0
	for i = #entries, 1, -1 do
		local entry = entries[i]
		TweenService:Create(entry.Frame, SLIDE_TWEEN, { Position = UDim2.new(0.5, 0, 1, -offset) }):Play()
		offset += entry.Height + settings.Gap
	end
end

local function dismiss(entry: Entry)
	if not entry.Alive then
		return
	end
	entry.Alive = false

	local index = table.find(entries, entry)
	if index then
		table.remove(entries, index)
	end

	local frame = entry.Frame
	TweenService:Create(frame, TweenInfo.new(settings.FadeTime, Enum.EasingStyle.Quad), { GroupTransparency = 1 }):Play()
	task.delay(settings.FadeTime, function()
		frame:Destroy()
	end)
	restack()
end

----------------------------------------------------------------------
-- Building one card
----------------------------------------------------------------------

local function buildCard(body: string, style): CanvasGroup
	local frame = Instance.new("CanvasGroup")
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Position = UDim2.new(0.5, 0, 1, 18) -- starts a little below, slides up into place
	frame.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
	frame.BackgroundTransparency = 0.22
	frame.BorderSizePixel = 0
	frame.GroupTransparency = 1

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = style.Accent
	stroke.Transparency = 0.6
	stroke.Thickness = 1
	stroke.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 20)
	padding.PaddingRight = UDim.new(0, 16)
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = frame

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Position = UDim2.new(0, -12, 0.5, 0)
	bar.Size = UDim2.new(0, 3, 1, -4)
	bar.BackgroundColor3 = style.Accent
	bar.BorderSizePixel = 0
	bar.Parent = frame
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.RichText = true
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
	label.TextSize = settings.TextSize
	label.TextColor3 = style.Text
	label.Text = body
	label.Parent = frame

	return frame
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

-- Yell cards sit under the thoughts: move the thought stack up by this many pixels
function ThoughtController.setLift(pixels: number)
	if container then
		TweenService:Create(container, SLIDE_TWEEN, {
			Position = UDim2.new(0.5, 0, 1, -(settings.BottomOffset + pixels)),
		}):Play()
	end
end

function ThoughtController.push(text: string, kind: string?, source: string?)
	if not container then
		return
	end
	local style = KIND_STYLE[kind or "Thought"] or KIND_STYLE.Thought

	local body = TextFormat.format(text)
	if source then
		body = ('<font color="#%s"><b>%s</b></font>  %s'):format(style.Accent:ToHex(), TextFormat.escape(source), body)
	end

	local frame = buildCard(body, style)
	frame.Parent = container

	-- The card auto-sizes to its text; wait for layout before reading its height
	local entry: Entry = { Frame = frame, Height = 0, Alive = true }
	for _ = 1, 3 do
		RunService.RenderStepped:Wait()
		if frame.AbsoluteSize.Y > 0 then
			break
		end
	end
	if not frame.Parent then
		return
	end
	entry.Height = frame.AbsoluteSize.Y

	table.insert(entries, entry)
	while #entries > settings.MaxVisible do
		dismiss(entries[1]) -- too many on screen: the oldest leaves early
	end

	restack()
	TweenService:Create(frame, FADE_IN, { GroupTransparency = 0 }):Play()

	local lifetime = math.min(settings.BaseLifetime + #text * settings.PerCharLifetime, settings.MaxLifetime)
	task.delay(lifetime, dismiss, entry)
end

-- J: what does my body feel like?
function ThoughtController.checkHealth()
	local now = os.clock()
	if now - lastHealthCheck < settings.HealthCheckCooldown then
		return
	end
	local humanoid = CharacterController.getHumanoid()
	if not humanoid or humanoid.Health <= 0 or PlayerState.get(player, "Transforming") then
		return
	end
	lastHealthCheck = now

	local tiers = if CharacterController.isTitan() then HealthThoughts.Titan else HealthThoughts.Human
	local fraction = humanoid.Health / humanoid.MaxHealth
	local line = HealthThoughts.pick(tiers, fraction, function(count)
		return rng:NextInteger(1, count)
	end)
	if line then
		ThoughtController.push(line, "Thought")
	end
end

function ThoughtController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ReclamationThoughts"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	container = Instance.new("Frame")
	container.Name = "ThoughtStack"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 1, -settings.BottomOffset)
	container.Size = UDim2.new(0, settings.Width, 0, 420)
	container.BackgroundTransparency = 1
	container.Active = false
	container.Parent = gui

	-- Keep the stack inside narrow screens (phones)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(settings.Width, 420)
	constraint.Parent = container

	Remotes.Thought.OnClientEvent:Connect(function(text, kind, source)
		if typeof(text) == "string" and #text > 0 and #text <= 500 then
			ThoughtController.push(text, if typeof(kind) == "string" then kind else "Thought", if typeof(source) == "string" then source else nil)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == settings.HealthCheckKey then
			ThoughtController.checkHealth()
		end
	end)
end

return ThoughtController
