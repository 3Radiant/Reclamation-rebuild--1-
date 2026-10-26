--[[
	LeaderboardController (client)
	A minimal, text-only replacement for Roblox's player list:

	  * Top middle : the round - "Round 2  -  14:32" with each side's lives under it. Plain text.
	  * Top right  : your face, name and health bar (no background), then the roster:
	                 side name + lives, then its players (name, rank in italics on the right).
	                 Press Tab (Config.Leaderboard.ToggleKey) to hide / show the roster.

	Ranks come from Config.Ranks and /rank. Config.Leaderboard: StartOpen, ShowStats (kills/deaths),
	HideEnemyNames ("???"), MaxRows.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Teams = game:GetService("Teams")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local MusicParse = require(Shared.MusicParse)
local PlayerState = require(Shared.PlayerState)

local CharacterController = require(script.Parent.CharacterController)
local RoundController = require(script.Parent.RoundController)

local player = Players.LocalPlayer
local settings = GameConfig.Leaderboard
local teamSettings = GameConfig.Teams

local LeaderboardController = {}

local WIDTH = 250
local WHITE = Color3.fromRGB(240, 240, 240)
local DIM = Color3.fromRGB(165, 168, 175)

local rosterFrame: Frame
local healthFill: Frame
local nameLabel: TextLabel
local roundLabel: TextLabel
local livesLabel: TextLabel
local open = settings.StartOpen
local dirty = true

-- Plain text with a thin dark outline so it stays readable on any background
local function text(parent: Instance, content: string, size: number, color: Color3, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = content
	l.TextSize = size
	l.TextColor3 = color
	l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.RichText = true
	l.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.6
	stroke.Parent = l
	return l
end

local function teamNameOf(target: Player): string?
	local team = target.Team
	if team and teamSettings[team.Name] then
		return team.Name
	end
	return nil
end

local function teamLives(name: string): number
	local team = Teams:FindFirstChild(name)
	return if team then (team:GetAttribute("Lives") or 0) else 0
end

local function rankIndex(target: Player, team: string): number
	local ranks = GameConfig.Ranks[team] or {}
	return table.find(ranks, PlayerState.get(target, "Rank")) or (#ranks + 1)
end

----------------------------------------------------------------------
-- Roster
----------------------------------------------------------------------

local function addHeader(order: number, title: string, right: string?)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 24)
	row.BackgroundTransparency = 1
	row.Parent = rosterFrame

	local name = text(row, title, 14, WHITE, true)
	name.Size = UDim2.new(1, -60, 1, 0)
	if right then
		local lives = text(row, right, 13, DIM)
		lives.TextXAlignment = Enum.TextXAlignment.Right
		lives.Position = UDim2.new(1, -60, 0, 0)
		lives.Size = UDim2.fromOffset(60, 24)
	end
end

local function addPlayerRow(order: number, target: Player, team: string?)
	local isMe = target == player
	local hidden = settings.HideEnemyNames and team ~= nil and not isMe and teamNameOf(player) ~= team
	local eliminated = PlayerState.get(target, "Eliminated") == true

	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 20)
	row.BackgroundTransparency = 1
	row.Parent = rosterFrame

	local color = if eliminated then DIM elseif isMe then WHITE else Color3.fromRGB(205, 207, 212)
	local name = text(row, if hidden then "???" else target.DisplayName, 13, color)
	name.Size = UDim2.new(1, -110, 1, 0)

	local right = ""
	if not hidden then
		local rank = PlayerState.get(target, "Rank")
		right = if rank ~= "" then "<i>" .. rank .. "</i>" else ""
		if settings.ShowStats then
			right = ("%d/%d  %s"):format(PlayerState.get(target, "Kills"), PlayerState.get(target, "Deaths"), right)
		end
	end
	local info = text(row, right, 12, DIM)
	info.TextXAlignment = Enum.TextXAlignment.Right
	info.Position = UDim2.new(1, -150, 0, 0)
	info.Size = UDim2.fromOffset(150, 20)
	name.Size = UDim2.new(1, -155, 1, 0)
end

local function rebuild()
	for _, child in rosterFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local order, shown = 0, 0
	for _, name in teamSettings.Order do
		local members = {}
		for _, other in Players:GetPlayers() do
			if teamNameOf(other) == name then
				table.insert(members, other)
			end
		end
		table.sort(members, function(a, b)
			local ra, rb = rankIndex(a, name), rankIndex(b, name)
			if ra ~= rb then
				return ra < rb
			end
			return a.DisplayName:lower() < b.DisplayName:lower()
		end)

		order += 1
		addHeader(order, teamSettings[name].Display, tostring(teamLives(name)))
		for _, member in members do
			if shown >= settings.MaxRows then
				break
			end
			order += 1
			shown += 1
			addPlayerRow(order, member, name)
		end
	end

	local unassigned = {}
	for _, other in Players:GetPlayers() do
		if not teamNameOf(other) then
			table.insert(unassigned, other)
		end
	end
	if #unassigned > 0 then
		order += 1
		addHeader(order, "Unassigned", nil)
		for _, member in unassigned do
			order += 1
			addPlayerRow(order, member, nil)
		end
	end
end

local function markDirty()
	dirty = true
end

local function watchPlayer(target: Player)
	for _, key in { "Rank", "Kills", "Deaths", "Eliminated" } do
		target:GetAttributeChangedSignal(key):Connect(markDirty)
	end
	target:GetPropertyChangedSignal("Team"):Connect(markDirty)
	target:GetPropertyChangedSignal("DisplayName"):Connect(markDirty)
	markDirty()
end

----------------------------------------------------------------------

local function healthColor(fraction: number): Color3
	if fraction > 0.6 then
		return Color3.fromRGB(110, 220, 110)
	elseif fraction > 0.3 then
		return Color3.fromRGB(230, 180, 70)
	end
	return Color3.fromRGB(215, 75, 70)
end

local function update()
	local humanoid = CharacterController.getHumanoid()
	local fraction = if humanoid and humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
	healthFill.Size = UDim2.fromScale(fraction, 1)
	healthFill.BackgroundColor3 = healthColor(fraction)

	-- Round text, top middle
	local phase = RoundController.getPhase()
	local remaining = math.max(0, RoundController.getEndsAt() - Workspace:GetServerTimeNow())
	if phase == "Active" then
		roundLabel.Text = ("Round %d  -  %s"):format(RoundController.getRound(), MusicParse.time(remaining))
	elseif phase == "Ending" then
		local winner = RoundController.getWinner()
		roundLabel.Text = if winner == "" or winner == "Draw" then "Stalemate" else (winner .. " victory")
	elseif phase == "Disabled" then
		roundLabel.Text = ""
	else
		roundLabel.Text = ("Next battle  -  %s"):format(MusicParse.time(remaining))
	end
	local a, b = teamSettings.Order[1], teamSettings.Order[2]
	livesLabel.Text = if phase == "Disabled" then "" else ("%s %d   |   %d %s"):format(a, teamLives(a), teamLives(b), b)
end

function LeaderboardController.setOpen(value: boolean)
	open = value
	if rosterFrame then
		rosterFrame.Visible = open
	end
end

function LeaderboardController.start()
	task.spawn(function()
		for _ = 1, 10 do
			if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, false) then
				break
			end
			task.wait(0.5)
		end
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "Leaderboard"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Round, top middle ------------------------------------------------------------
	roundLabel = text(gui, "", 17, WHITE, true)
	roundLabel.AnchorPoint = Vector2.new(0.5, 0)
	roundLabel.Position = UDim2.new(0.5, 0, 0, 10)
	roundLabel.Size = UDim2.fromOffset(400, 22)
	roundLabel.TextXAlignment = Enum.TextXAlignment.Center
	livesLabel = text(gui, "", 13, DIM)
	livesLabel.AnchorPoint = Vector2.new(0.5, 0)
	livesLabel.Position = UDim2.new(0.5, 0, 0, 32)
	livesLabel.Size = UDim2.fromOffset(400, 18)
	livesLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- Top right: your profile (no background) + roster --------------------------
	local root = Instance.new("Frame")
	root.AnchorPoint = Vector2.new(1, 0)
	root.Position = UDim2.new(1, -16, 0, 14)
	root.Size = UDim2.fromOffset(WIDTH, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.BackgroundTransparency = 1
	root.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = root

	local profile = Instance.new("Frame")
	profile.LayoutOrder = 1
	profile.Size = UDim2.new(1, 0, 0, 44)
	profile.BackgroundTransparency = 1
	profile.Parent = root

	local portrait = Instance.new("ImageLabel")
	portrait.AnchorPoint = Vector2.new(1, 0)
	portrait.Position = UDim2.fromScale(1, 0)
	portrait.Size = UDim2.fromOffset(44, 44)
	portrait.BackgroundTransparency = 1
	portrait.Parent = profile
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok and image then
			portrait.Image = image
		end
	end)

	nameLabel = text(profile, player.DisplayName, 16, WHITE, true)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Right
	nameLabel.Position = UDim2.fromOffset(0, 3)
	nameLabel.Size = UDim2.new(1, -52, 0, 20)
	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(1, 0)
	track.Position = UDim2.new(1, -52, 0, 30)
	track.Size = UDim2.new(1, -52, 0, 4)
	track.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	track.BackgroundTransparency = 0.6
	track.BorderSizePixel = 0
	track.Parent = profile
	healthFill = Instance.new("Frame")
	healthFill.AnchorPoint = Vector2.new(1, 0)
	healthFill.Position = UDim2.fromScale(1, 0)
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = healthColor(1)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = track

	rosterFrame = Instance.new("Frame")
	rosterFrame.LayoutOrder = 2
	rosterFrame.Size = UDim2.new(1, 0, 0, 0)
	rosterFrame.AutomaticSize = Enum.AutomaticSize.Y
	rosterFrame.BackgroundTransparency = 1
	rosterFrame.Visible = open
	rosterFrame.Parent = root
	local rosterLayout = Instance.new("UIListLayout")
	rosterLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rosterLayout.Padding = UDim.new(0, 1)
	rosterLayout.Parent = rosterFrame

	local scale = Instance.new("UIScale")
	scale.Parent = root
	local function fit()
		scale.Scale = math.clamp((gui.AbsoluteSize.Y - 24) / 520, 0.6, 1)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(markDirty)
	for _, name in teamSettings.Order do
		local team = Teams:WaitForChild(name, 30)
		if team then
			team:GetAttributeChangedSignal("Lives"):Connect(markDirty)
		end
	end

	local sinceRebuild = 0
	RunService.RenderStepped:Connect(function(dt)
		update()
		sinceRebuild += dt
		if dirty and sinceRebuild > 0.25 then
			dirty = false
			sinceRebuild = 0
			rebuild()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == settings.ToggleKey then
			LeaderboardController.setOpen(not open)
		end
	end)
end

return LeaderboardController
