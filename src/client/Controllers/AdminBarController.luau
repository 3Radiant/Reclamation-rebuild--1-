--[[
	AdminBarController (client)
	Press ; to open the command bar (admins only), type a command, press Enter.
	Escape or clicking away closes it. Up / Down walks through your command history.

	    anxiety me 8 30        thought all Stay calm.        strike Bob        cmds

	A leading "/" or ";" is optional. Commands run through the same server handler as chat
	commands, which re-checks that you are really an admin, so this bar is only a UI.
	Results appear as inner-thought cards.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlayerState = require(Shared.PlayerState)
local Remotes = require(Shared.Remotes)

local MusicUiController = require(script.Parent.MusicUiController)
local TeamMenuController = require(script.Parent.TeamMenuController)

local player = Players.LocalPlayer

local AdminBarController = {}

-- name, usage
local COMMANDS = {
	{ "anxiety", "anxiety <me|all|name> [1-10] [seconds|off]" },
	{ "thought", "thought <me|all|name> <text>" },
	{ "lang", "lang <me|all|name> <Eldian|Marleyan|Both>" },
	{ "shifter", "shifter <me|all|name> <TitanName|none>" },
	{ "blimps", "blimps on|off|spawn [n]|clear|status|max n|every a [b]|fire a [b]|shells a [b]|range n|alt a [b]|radius n|speed n|here" },
	{ "armoredtitanintro", "armoredtitanintro   (typewriter speech, camera finds the Armored Titan)" },
	{ "shirt", "shirt <me|all|name> <id|none|reset> [true|false = persist across lives]" },
	{ "pants", "pants <me|all|name> <id|none|reset> [true|false = persist across lives]" },
	{ "titan", "titan <TitanName>   (gives yourself a Titan)" },
	{ "strike", "strike [me|name]   (calls an artillery barrage)" },
	{ "bossbar", "bossbar <player|npc> [title]   |   bossbar off [name|all]" },
	{ "yellto", "yellto <me|all|name> <text>" },
	{ "yell", "yell <text>   (carries a short distance)" },
	{ "music", "music play|add <id|name> | skip | pause | resume | stop | volume <0-100> | loop | shuffle | ui" },
	{ "cursor", "cursor <image id | preset | default | list>   (your own mouse cursor)" },
	{ "flare", "flare <red|blue|purple|yellow|green|black|white|orange>   (or press V)" },
	{ "mymusic", "mymusic <0-100>   (your own music volume)" },
	{ "announce", "announce line one | line two | ..." },
	{ "rank", "rank <me|name> <rank>" },
	{ "round", "round status | start | end [Eldian|Marleyan|draw] | lives <team> <n>" },
	{ "team", "team   (opens the team menu)" },
	{ "cmds", "cmds" },
	{ "t", "t <private thought>" },
	{ "eldian", "eldian" },
	{ "marleyan", "marleyan" },
}

local OPEN_KEY = Enum.KeyCode.Semicolon

local bar: Frame
local box: TextBox
local hint: TextLabel
local history: { string } = {}
local historyIndex = 0
local openedAt = 0

local function isAdmin(): boolean
	return PlayerState.get(player, "IsAdmin") == true
end

local function updateHint()
	local typed = box.Text:gsub("^[/;]", ""):lower()
	local word = typed:match("^(%S*)") or ""
	local matches = {}
	for _, entry in COMMANDS do
		if word == "" or entry[1]:sub(1, #word) == word then
			table.insert(matches, entry)
		end
	end
	if #matches == 0 then
		hint.Text = "No such command. Try: cmds"
	elseif #matches == 1 or typed:find("%s") then
		hint.Text = matches[1][2]
	else
		local names = {}
		for _, entry in matches do
			table.insert(names, entry[1])
		end
		hint.Text = table.concat(names, "   ")
	end
end

local function close()
	if box:IsFocused() then
		box:ReleaseFocus()
	end
	bar.Visible = false
	box.Text = ""
	historyIndex = 0
end

local function submit()
	local text = box.Text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^[/;]+", "")
	if text == "" then
		return
	end
	if history[#history] ~= text then
		table.insert(history, text)
	end
	local name, args = text:match("^(%S+)%s*(.*)$")
	if name and (MusicUiController.tryLocal(name, args) or TeamMenuController.tryLocal(name)) then
		return
	end
	if name then
		Remotes.ChatCommand:FireServer(name:lower(), args)
	end
end

local function open()
	if bar.Visible or not isAdmin() then
		return
	end
	openedAt = os.clock()
	bar.Visible = true
	box.Text = ""
	historyIndex = 0
	updateHint()
	box:CaptureFocus()

	bar.Position = UDim2.new(0.5, 0, 0, -10)
	TweenService:Create(bar, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 22),
	}):Play()
end

function AdminBarController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "AdminBar"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = player:WaitForChild("PlayerGui")

	bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 22)
	bar.Size = UDim2.fromOffset(540, 62)
	bar.BackgroundColor3 = Color3.fromRGB(16, 18, 22)
	bar.BackgroundTransparency = 0.1
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bar
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(110, 160, 235)
	stroke.Transparency = 0.4
	stroke.Parent = bar

	local prefix = Instance.new("TextLabel")
	prefix.BackgroundTransparency = 1
	prefix.Position = UDim2.fromOffset(14, 6)
	prefix.Size = UDim2.fromOffset(16, 28)
	prefix.Font = Enum.Font.GothamBold
	prefix.Text = ";"
	prefix.TextSize = 20
	prefix.TextColor3 = Color3.fromRGB(110, 160, 235)
	prefix.Parent = bar

	box = Instance.new("TextBox")
	box.BackgroundTransparency = 1
	box.Position = UDim2.fromOffset(34, 6)
	box.Size = UDim2.new(1, -48, 0, 28)
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.Code
	box.PlaceholderText = "command...   (Enter to run, Esc to close)"
	box.PlaceholderColor3 = Color3.fromRGB(110, 116, 128)
	box.Text = ""
	box.TextSize = 18
	box.TextColor3 = Color3.fromRGB(236, 238, 242)
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Parent = bar

	hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.Position = UDim2.fromOffset(14, 38)
	hint.Size = UDim2.new(1, -28, 0, 18)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 12
	hint.TextColor3 = Color3.fromRGB(150, 156, 168)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Text = ""
	hint.Parent = bar

	box:GetPropertyChangedSignal("Text"):Connect(function()
		-- The ";" that opened the bar would otherwise be typed into it
		if os.clock() - openedAt < 0.2 and box.Text:find(";", 1, true) then
			box.Text = box.Text:gsub(";", "")
			return
		end
		if bar.Visible then
			updateHint()
		end
	end)

	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submit()
		end
		close()
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == OPEN_KEY and not processed then
			open()
		elseif bar.Visible and box:IsFocused() and #history > 0 then
			if input.KeyCode == Enum.KeyCode.Up then
				historyIndex = math.min(historyIndex + 1, #history)
				box.Text = history[#history - historyIndex + 1]
				box.CursorPosition = #box.Text + 1
			elseif input.KeyCode == Enum.KeyCode.Down then
				historyIndex = math.max(historyIndex - 1, 0)
				box.Text = if historyIndex == 0 then "" else history[#history - historyIndex + 1]
				box.CursorPosition = #box.Text + 1
			end
		end
	end)
end

return AdminBarController
