--[[
	BossBarController (client)
	Boss bars at the top centre of the screen: the target's name above a framed health bar
	(dark red fill, pale "damage taken" trail that drains behind it).

	The server (BossBarService) publishes bars as ObjectValues in ReplicatedStorage/BossBars,
	so this controller just mirrors that folder. A bar tracks a Player's CURRENT body (it
	survives respawns/shifting) or a Model's Humanoid, and fades out when the target is dead
	or gone. Look and size: Config.BossBar.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)

local player = Players.LocalPlayer
local settings = GameConfig.BossBar

local BossBarController = {}

type Bar = {
	Value: ObjectValue,
	Group: CanvasGroup,
	Fill: Frame,
	Trail: Frame,
	Title: TextLabel,
	Numbers: TextLabel,
	Trailing: number, -- health fraction the trail currently shows
	Shown: number, -- health fraction the fill currently shows
	DeadSince: number?,
	Visible: boolean,
}

local container: Frame
local bars: { [ObjectValue]: Bar } = {}

local function getHumanoid(target: Instance?): (Humanoid?, Model?)
	local model: Instance? = target
	if target and target:IsA("Player") then
		model = target.Character
	end
	if model and model:IsA("Model") then
		return model:FindFirstChildOfClass("Humanoid"), model
	end
	return nil, nil
end

local function titleFor(value: ObjectValue): string
	local custom = value:GetAttribute("Title")
	if typeof(custom) == "string" and custom ~= "" then
		return custom
	end
	local target = value.Value
	if target and target:IsA("Player") then
		return target.DisplayName
	end
	return if target then target.Name else "?"
end

local function build(value: ObjectValue): Bar
	local group = Instance.new("CanvasGroup")
	group.Name = value.Name
	group.LayoutOrder = tonumber(value.Name) or 0
	group.Size = UDim2.new(1, 0, 0, 58)
	group.BackgroundTransparency = 1
	group.GroupTransparency = 1
	group.Parent = container

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(6, 0)
	title.Size = UDim2.new(1, -12, 0, 26)
	title.Font = Enum.Font.Garamond
	title.TextSize = 24
	title.TextColor3 = Color3.fromRGB(240, 238, 232)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = titleFor(value)
	title.Parent = group
	local shadow = Instance.new("UIStroke")
	shadow.Thickness = 1
	shadow.Color = Color3.new(0, 0, 0)
	shadow.Transparency = 0.35
	shadow.Parent = title

	-- Frame: grey outline, dark inner track
	local frame = Instance.new("Frame")
	frame.Position = UDim2.fromOffset(0, 28)
	frame.Size = UDim2.new(1, 0, 0, 26)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
	frame.BorderSizePixel = 0
	frame.Parent = group
	local outline = Instance.new("UIStroke")
	outline.Thickness = 2
	outline.Color = Color3.fromRGB(150, 150, 154)
	outline.Parent = frame

	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(4, 4)
	track.Size = UDim2.new(1, -8, 1, -8)
	track.BackgroundColor3 = Color3.fromRGB(58, 58, 62)
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = frame

	local trail = Instance.new("Frame")
	trail.Size = UDim2.fromScale(1, 1)
	trail.BackgroundColor3 = settings.TrailColor
	trail.BorderSizePixel = 0
	trail.Parent = track

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = settings.FillColor
	fill.BorderSizePixel = 0
	fill.Parent = track
	local sheen = Instance.new("UIGradient")
	sheen.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 150))
	sheen.Rotation = 90
	sheen.Parent = fill

	local numbers = Instance.new("TextLabel")
	numbers.BackgroundTransparency = 1
	numbers.Size = UDim2.fromScale(1, 1)
	numbers.Font = Enum.Font.GothamBold
	numbers.TextSize = 13
	numbers.TextColor3 = Color3.fromRGB(245, 245, 245)
	numbers.Visible = settings.ShowNumbers
	numbers.ZIndex = 3
	numbers.Parent = track

	return {
		Value = value,
		Group = group,
		Fill = fill,
		Trail = trail,
		Title = title,
		Numbers = numbers,
		Trailing = 1,
		Shown = 1,
		DeadSince = nil,
		Visible = false,
	}
end

local function add(child: Instance)
	if child:IsA("ObjectValue") and not bars[child] then
		bars[child] = build(child)
	end
end

local function remove(child: Instance)
	local bar = bars[child :: ObjectValue]
	if bar then
		bars[child :: ObjectValue] = nil
		bar.Group:Destroy()
	end
end

local function setVisible(bar: Bar, visible: boolean)
	if bar.Visible == visible then
		return
	end
	bar.Visible = visible
	TweenService:Create(bar.Group, TweenInfo.new(0.35), { GroupTransparency = if visible then 0 else 1 }):Play()
end

local function update(dt: number)
	local now = os.clock()
	local anyVisible = false
	for value, bar in bars do
		local humanoid = getHumanoid(value.Value)
		bar.Title.Text = titleFor(value)

		if humanoid and humanoid.MaxHealth > 0 then
			local fraction = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)

			-- Fill follows quickly; the pale trail drains behind it after a short beat
			bar.Shown += (fraction - bar.Shown) * (1 - math.exp(-18 * dt))
			if bar.Trailing > bar.Shown then
				bar.Trailing = math.max(bar.Shown, bar.Trailing - 0.35 * dt)
			else
				bar.Trailing = bar.Shown
			end
			bar.Fill.Size = UDim2.fromScale(bar.Shown, 1)
			bar.Trail.Size = UDim2.fromScale(bar.Trailing, 1)
			bar.Numbers.Text = ("%d / %d"):format(math.ceil(humanoid.Health), math.ceil(humanoid.MaxHealth))

			if humanoid.Health <= 0 then
				bar.DeadSince = bar.DeadSince or now
			else
				bar.DeadSince = nil
			end
		else
			bar.DeadSince = bar.DeadSince or now -- no body right now (respawning, or gone)
		end

		local gone = bar.DeadSince ~= nil and now - bar.DeadSince > settings.DeadFadeDelay
		setVisible(bar, not gone)
		anyVisible = anyVisible or bar.Visible
	end
	container.Visible = anyVisible or next(bars) ~= nil
end

function BossBarController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BossBars"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	container = Instance.new("Frame")
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.new(0.5, 0, 0, settings.TopOffset)
	container.Size = UDim2.fromOffset(settings.Width, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.BackgroundTransparency = 1
	container.Active = false
	container.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, settings.Spacing)
	layout.Parent = container
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(settings.Width, math.huge)
	limit.Parent = container
	-- shrink on narrow screens
	local scale = Instance.new("UIScale")
	scale.Parent = container
	local function fit()
		local viewport = gui.AbsoluteSize.X
		scale.Scale = math.clamp((viewport - 24) / settings.Width, 0.5, 1)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	local folder = ReplicatedStorage:WaitForChild("BossBars", 30)
	if folder then
		for _, child in folder:GetChildren() do
			add(child)
		end
		folder.ChildAdded:Connect(add)
		folder.ChildRemoved:Connect(remove)
	end

	RunService.RenderStepped:Connect(update)
end

return BossBarController
