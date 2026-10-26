--[[
	MusicUiController (client)
	The admin music panel. Open with the M key (Config.Music.UIKey), or "/music ui".

	  Left   : your library (Configs/MusicLibrary.luau) with search; click Play / Add on a row.
	           Below it, paste audio ids (several allowed) and Play now / Add to queue.
	  Right  : now playing (click the bar to seek), Pause/Resume, Skip, Stop, Loop, Shuffle,
	           volume + speed sliders, and the queue with a remove button on each track.

	Buttons just send Remotes.MusicControl to the server, which re-checks that you are an admin.
	Also here: tryLocal(), used by chat and the command bar for client-side commands
	("/music ui" and "/mymusic <0-100>", the player's own volume).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local MusicLibrary = require(Shared.Configs.MusicLibrary)
local MusicParse = require(Shared.MusicParse)
local PlayerState = require(Shared.PlayerState)
local Remotes = require(Shared.Remotes)

local MusicController = require(script.Parent.MusicController)
local ThoughtController = require(script.Parent.ThoughtController)

local player = Players.LocalPlayer

local MusicUiController = {}

local C = {
	Window = Color3.fromRGB(18, 20, 24),
	Panel = Color3.fromRGB(28, 31, 37),
	Row = Color3.fromRGB(36, 40, 47),
	Button = Color3.fromRGB(52, 58, 68),
	ButtonHot = Color3.fromRGB(72, 82, 98),
	Text = Color3.fromRGB(236, 238, 242),
	Dim = Color3.fromRGB(150, 156, 168),
	Accent = Color3.fromRGB(110, 160, 235),
	Bad = Color3.fromRGB(214, 70, 64),
}

local window: Frame
local libraryList: ScrollingFrame
local queueList: ScrollingFrame
local searchBox: TextBox
local idBox: TextBox
local titleLabel: TextLabel
local byLabel: TextLabel
local timeLabel: TextLabel
local progressFill: Frame
local progressTrack: Frame
local pauseButton: TextButton
local loopButton: TextButton
local shuffleButton: TextButton
local volumeSlider: any
local speedSlider: any
local lastRev = -1

local function send(action: string, a: any?, b: any?)
	Remotes.MusicControl:FireServer(action, a, b)
end

----------------------------------------------------------------------
-- Small widgets
----------------------------------------------------------------------

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, text: string, size: number, color: Color3, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, position: UDim2, size: UDim2, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = text
	b.Position = position
	b.Size = size
	b.BackgroundColor3 = C.Button
	b.TextColor3 = C.Text
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 13
	b.BorderSizePixel = 0
	corner(b, 6)
	b.Parent = parent
	b.MouseEnter:Connect(function()
		b.BackgroundColor3 = C.ButtonHot
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundColor3 = C.Button
	end)
	b.Activated:Connect(onClick)
	return b
end

local function box(parent: Instance, placeholder: string, position: UDim2, size: UDim2): TextBox
	local t = Instance.new("TextBox")
	t.Position = position
	t.Size = size
	t.BackgroundColor3 = C.Row
	t.BorderSizePixel = 0
	t.ClearTextOnFocus = false
	t.Font = Enum.Font.Gotham
	t.TextSize = 14
	t.TextColor3 = C.Text
	t.PlaceholderText = placeholder
	t.PlaceholderColor3 = C.Dim
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Text = ""
	corner(t, 6)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.Parent = t
	t.Parent = parent
	return t
end

local function scroller(parent: Instance, position: UDim2, size: UDim2): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.Position = position
	s.Size = size
	s.BackgroundColor3 = C.Panel
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 4
	s.CanvasSize = UDim2.new()
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	corner(s, 8)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = s
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 6), UDim.new(0, 10)
	pad.Parent = s
	s.Parent = parent
	return s
end

-- Horizontal slider. onChange(value, final) is called while dragging (throttled) and on release.
local function slider(parent: Instance, position: UDim2, size: UDim2, min: number, max: number, onChange: (number, boolean) -> ())
	local track = Instance.new("Frame")
	track.Position = position
	track.Size = size
	track.BackgroundColor3 = C.Button
	track.BorderSizePixel = 0
	corner(track, 7)
	track.Parent = parent

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = C.Accent
	fill.BorderSizePixel = 0
	corner(fill, 7)
	fill.Parent = track

	local dragging = false
	local value = min
	local lastSent = 0

	local function show(v: number)
		fill.Size = UDim2.fromScale(math.clamp((v - min) / (max - min), 0, 1), 1)
	end
	local function fromX(x: number): number
		local alpha = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		return min + (max - min) * alpha
	end

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			value = fromX(input.Position.X)
			show(value)
			onChange(value, false)
			lastSent = os.clock()
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			value = fromX(input.Position.X)
			show(value)
			if os.clock() - lastSent > 0.12 then
				lastSent = os.clock()
				onChange(value, false)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			onChange(value, true)
		end
	end)

	return {
		set = function(v: number)
			if not dragging then
				value = v
				show(v)
			end
		end,
	}
end

----------------------------------------------------------------------
-- Lists
----------------------------------------------------------------------

local function clearRows(list: ScrollingFrame)
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function rebuildLibrary()
	clearRows(libraryList)
	local query = searchBox.Text:lower()
	local shown = 0
	for index, entry in MusicLibrary do
		local haystack = (entry.Title .. " " .. (entry.Category or "")):lower()
		if query ~= "" and not haystack:find(query, 1, true) then
			continue
		end
		shown += 1
		local row = Instance.new("Frame")
		row.LayoutOrder = index
		row.Size = UDim2.new(1, 0, 0, 36)
		row.BackgroundColor3 = C.Row
		row.BorderSizePixel = 0
		corner(row, 6)
		row.Parent = libraryList

		local name = label(row, entry.Title, 14, C.Text)
		name.Position = UDim2.fromOffset(10, if entry.Category then 3 else 0)
		name.Size = UDim2.new(1, -112, 0, if entry.Category then 20 else 36)
		if entry.Category then
			local tag = label(row, entry.Category, 11, C.Dim)
			tag.Position = UDim2.fromOffset(10, 20)
			tag.Size = UDim2.new(1, -112, 0, 14)
		end
		button(row, "Play", UDim2.new(1, -100, 0.5, -13), UDim2.fromOffset(44, 26), function()
			send("PlayId", tostring(entry.Id))
		end)
		button(row, "Add", UDim2.new(1, -50, 0.5, -13), UDim2.fromOffset(44, 26), function()
			send("AddId", tostring(entry.Id))
		end)
	end
	if shown == 0 then
		local empty = Instance.new("Frame")
		empty.Size = UDim2.new(1, 0, 0, 60)
		empty.BackgroundTransparency = 1
		empty.Parent = libraryList
		local text = label(
			empty,
			if #MusicLibrary == 0 then "No tracks yet. Add ids to Configs/MusicLibrary.luau, or paste one below." else "No match.",
			13,
			C.Dim
		)
		text.Size = UDim2.fromScale(1, 1)
		text.TextWrapped = true
		text.TextTruncate = Enum.TextTruncate.None
	end
end

local function rebuildQueue(state: any)
	clearRows(queueList)
	local queue = state and state.Queue or {}
	if #queue == 0 then
		local empty = Instance.new("Frame")
		empty.Size = UDim2.new(1, 0, 0, 26)
		empty.BackgroundTransparency = 1
		empty.Parent = queueList
		label(empty, "Queue is empty.", 13, C.Dim).Size = UDim2.fromScale(1, 1)
		return
	end
	for index, track in queue do
		local row = Instance.new("Frame")
		row.LayoutOrder = index
		row.Size = UDim2.new(1, 0, 0, 28)
		row.BackgroundColor3 = C.Row
		row.BorderSizePixel = 0
		corner(row, 6)
		row.Parent = queueList
		local name = label(row, ("%d.  %s"):format(index, track.Title), 13, C.Text)
		name.Position = UDim2.fromOffset(10, 0)
		name.Size = UDim2.new(1, -120, 1, 0)
		local by = label(row, track.By or "", 11, C.Dim)
		by.TextXAlignment = Enum.TextXAlignment.Right
		by.Position = UDim2.new(1, -150, 0, 0)
		by.Size = UDim2.fromOffset(90, 28)
		button(row, "X", UDim2.new(1, -30, 0.5, -11), UDim2.fromOffset(24, 22), function()
			send("Remove", index)
		end)
	end
end

----------------------------------------------------------------------
-- State -> widgets
----------------------------------------------------------------------

local function applyState(state: any)
	if not window then
		return
	end
	if state.Rev ~= lastRev then
		lastRev = state.Rev
		rebuildQueue(state)
	end
	local current = state.Current
	titleLabel.Text = if current then current.Title else "Nothing playing"
	byLabel.Text = if current then ("Added by %s"):format(current.By or "?") else "Add a track from the library or paste an id."
	pauseButton.Text = if state.Paused then "Resume" else "Pause"
	loopButton.Text = "Loop: " .. state.Loop
	shuffleButton.Text = if state.Shuffle then "Shuffle: On" else "Shuffle: Off"
	shuffleButton.TextColor3 = if state.Shuffle then C.Accent else C.Text
	volumeSlider.set(state.Volume * 100)
	speedSlider.set(state.Speed)
end

local function updateProgress()
	local state = MusicController.getState()
	local current = state and state.Current
	if not current or not current.Length then
		progressFill.Size = UDim2.fromScale(0, 1)
		timeLabel.Text = "0:00 / 0:00"
		return
	end
	local position = MusicController.getPosition()
	progressFill.Size = UDim2.fromScale(math.clamp(position / current.Length, 0, 1), 1)
	timeLabel.Text = ("%s / %s"):format(MusicParse.time(position), MusicParse.time(current.Length))
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------

local function isAdmin(): boolean
	return PlayerState.get(player, "IsAdmin") == true
end

function MusicUiController.toggle()
	if not window then
		return
	end
	if window.Visible then
		window.Visible = false
		return
	end
	if not isAdmin() then
		ThoughtController.push("Only admins can use the music player.", "System")
		return
	end
	window.Visible = true
	rebuildLibrary()
	local state = MusicController.getState()
	if state then
		lastRev = -1
		applyState(state)
	end
end

-- Client-side commands. Returns true if handled here (so it is NOT sent to the server).
function MusicUiController.tryLocal(name: string, args: string): boolean
	name = name:lower()
	if name == "music" and args:lower():match("^%s*(%a+)") and ({ ui = true, panel = true, gui = true })[args:lower():match("^%s*(%a+)")] then
		MusicUiController.toggle()
		return true
	elseif name == "mymusic" then
		local value = tonumber(args)
		if value then
			MusicController.setPersonalVolume(value / 100)
			ThoughtController.push(("My music volume: %d%%."):format(math.clamp(value, 0, 100)), "System")
		else
			ThoughtController.push("Usage: /mymusic <0-100>  (only changes your own volume)", "System")
		end
		return true
	end
	return false
end

function MusicUiController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MusicPanel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 40
	gui.Parent = player:WaitForChild("PlayerGui")

	window = Instance.new("Frame")
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(760, 480)
	window.BackgroundColor3 = C.Window
	window.BackgroundTransparency = 0.04
	window.BorderSizePixel = 0
	window.Visible = false
	corner(window, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.9
	stroke.Parent = window
	window.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Parent = window
	local function fit()
		local size = gui.AbsoluteSize
		scale.Scale = math.clamp(math.min((size.X - 20) / 760, (size.Y - 20) / 480), 0.5, 1)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	local header = label(window, "Music", 20, C.Text, true)
	header.Position = UDim2.fromOffset(18, 12)
	header.Size = UDim2.fromOffset(300, 30)
	local hint = label(window, "Plays for everyone  |  M to close", 12, C.Dim)
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.Position = UDim2.new(1, -330, 0, 18)
	hint.Size = UDim2.fromOffset(270, 20)
	button(window, "X", UDim2.new(1, -44, 0, 12), UDim2.fromOffset(30, 28), function()
		window.Visible = false
	end)

	-- Left: library + ids ------------------------------------------------
	searchBox = box(window, "Search library...", UDim2.fromOffset(18, 56), UDim2.fromOffset(300, 30))
	searchBox:GetPropertyChangedSignal("Text"):Connect(rebuildLibrary)
	libraryList = scroller(window, UDim2.fromOffset(18, 94), UDim2.fromOffset(300, 246))

	idBox = box(window, "Paste audio id(s)...", UDim2.fromOffset(18, 352), UDim2.fromOffset(300, 32))
	button(window, "Play now", UDim2.fromOffset(18, 392), UDim2.fromOffset(146, 34), function()
		if idBox.Text ~= "" then
			send("PlayId", idBox.Text)
			idBox.Text = ""
		end
	end)
	button(window, "Add to queue", UDim2.fromOffset(172, 392), UDim2.fromOffset(146, 34), function()
		if idBox.Text ~= "" then
			send("AddId", idBox.Text)
			idBox.Text = ""
		end
	end)
	local tip = label(window, "Tip: you can paste several ids at once.", 11, C.Dim)
	tip.Position = UDim2.fromOffset(18, 434)
	tip.Size = UDim2.fromOffset(300, 16)

	-- Right: now playing ---------------------------------------------------
	local card = Instance.new("Frame")
	card.Position = UDim2.fromOffset(338, 56)
	card.Size = UDim2.fromOffset(404, 200)
	card.BackgroundColor3 = C.Panel
	card.BorderSizePixel = 0
	corner(card, 8)
	card.Parent = window

	titleLabel = label(card, "Nothing playing", 18, C.Text, true)
	titleLabel.Position = UDim2.fromOffset(14, 10)
	titleLabel.Size = UDim2.new(1, -28, 0, 24)
	byLabel = label(card, "", 12, C.Dim)
	byLabel.Position = UDim2.fromOffset(14, 34)
	byLabel.Size = UDim2.new(1, -28, 0, 16)

	progressTrack = Instance.new("Frame")
	progressTrack.Position = UDim2.fromOffset(14, 60)
	progressTrack.Size = UDim2.new(1, -28, 0, 8)
	progressTrack.BackgroundColor3 = C.Button
	progressTrack.BorderSizePixel = 0
	corner(progressTrack, 4)
	progressTrack.Parent = card
	progressFill = Instance.new("Frame")
	progressFill.Size = UDim2.fromScale(0, 1)
	progressFill.BackgroundColor3 = C.Accent
	progressFill.BorderSizePixel = 0
	corner(progressFill, 4)
	progressFill.Parent = progressTrack
	progressTrack.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local state = MusicController.getState()
			if state and state.Current and state.Current.Length then
				local alpha = math.clamp((input.Position.X - progressTrack.AbsolutePosition.X) / math.max(progressTrack.AbsoluteSize.X, 1), 0, 1)
				send("Seek", alpha * state.Current.Length)
			end
		end
	end)
	timeLabel = label(card, "0:00 / 0:00", 12, C.Dim)
	timeLabel.Position = UDim2.fromOffset(14, 72)
	timeLabel.Size = UDim2.fromOffset(200, 16)

	-- Controls row
	local buttonWidth = 72
	local function at(i: number): UDim2
		return UDim2.fromOffset(14 + (i - 1) * (buttonWidth + 6), 98)
	end
	local size = UDim2.fromOffset(buttonWidth, 30)
	pauseButton = button(card, "Pause", at(1), size, function()
		local state = MusicController.getState()
		send(if state and state.Paused then "Resume" else "Pause")
	end)
	button(card, "Skip", at(2), size, function()
		send("Skip")
	end)
	button(card, "Stop", at(3), size, function()
		send("Stop")
	end)
	loopButton = button(card, "Loop: Off", at(4), size, function()
		local state = MusicController.getState()
		local order = { Off = "Track", Track = "Queue", Queue = "Off" }
		send("Loop", order[state and state.Loop or "Off"])
	end)
	loopButton.TextSize = 11
	shuffleButton = button(card, "Shuffle: Off", at(5), size, function()
		send("Shuffle")
	end)
	shuffleButton.TextSize = 11

	-- Sliders
	local volumeText = label(card, "Volume", 12, C.Dim)
	volumeText.Position = UDim2.fromOffset(14, 144)
	volumeText.Size = UDim2.fromOffset(170, 16)
	volumeSlider = slider(card, UDim2.fromOffset(14, 166), UDim2.fromOffset(176, 14), 0, 100, function(value, final)
		volumeText.Text = ("Volume  %d%%"):format(value)
		send("Volume", value)
	end)
	local speedText = label(card, "Speed", 12, C.Dim)
	speedText.Position = UDim2.fromOffset(214, 144)
	speedText.Size = UDim2.fromOffset(170, 16)
	speedSlider = slider(card, UDim2.fromOffset(214, 166), UDim2.fromOffset(176, 14), 0.5, 2, function(value, final)
		speedText.Text = ("Speed  %.2fx"):format(value)
		send("Speed", math.floor(value * 20 + 0.5) / 20)
	end)

	-- Queue -------------------------------------------------------------------
	local queueHeader = label(window, "Up next", 14, C.Text, true)
	queueHeader.Position = UDim2.fromOffset(338, 266)
	queueHeader.Size = UDim2.fromOffset(200, 20)
	button(window, "Clear queue", UDim2.fromOffset(644, 262), UDim2.fromOffset(98, 26), function()
		send("Clear")
	end)
	queueList = scroller(window, UDim2.fromOffset(338, 292), UDim2.fromOffset(404, 168))

	MusicController.onChanged(applyState)

	RunService.RenderStepped:Connect(function()
		if window.Visible then
			updateProgress()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= GameConfig.Music.UIKey then
			return
		end
		MusicUiController.toggle()
	end)
end

return MusicUiController
