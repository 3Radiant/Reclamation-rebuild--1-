--[[
	ChatController (client)
	Hooks the Roblox chat (TextChatService):
	  * registers the slash commands and forwards them to the server (ChatService)
	  * rewrites every chat-window message:
	      - *italic*, **bold**, ***bold italic***
	      - [ELD] / [MAR] tag in front of the name
	      - if you don't understand the speaker's language, the words are scrambled
	  * draws its OWN overhead speech bubbles (Roblox's native bubbles can't change the
	    text, so they could not scramble languages or show the tags)
	  * applies Config.Chat: chat window on/off (the input bar always stays)

	Who receives a message at all (local vs global chat) is decided on the server, in
	ChatService, using Config.Chat.GlobalChat / ProximityRange.

	Needs the new chat: default.project.json sets TextChatService.ChatVersion for you.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local Languages = require(Shared.Languages)
local PlayerState = require(Shared.PlayerState)
local Remotes = require(Shared.Remotes)
local TextFormat = require(Shared.TextFormat)

local CursorController = require(script.Parent.CursorController)
local GunController = require(script.Parent.GunController)
local MusicUiController = require(script.Parent.MusicUiController)
local TeamMenuController = require(script.Parent.TeamMenuController)

local player = Players.LocalPlayer

local ChatController = {}

-- name -> true. (Admin-only ones are still registered: the server refuses non-admins.)
local COMMANDS = {
	"t", "eldian", "marleyan", "yell", -- everyone
	"mymusic", -- everyone (your own music volume, handled on the client)
	"team", -- everyone (opens the team menu, client-side)
	"cursor", "flare", -- everyone (client-side: your own cursor / flare colour)
	"thought", "lang", "titan", "shifter", "shirt", "pants", "blimps", "armoredtitanintro", "cmds", "anxiety", "strike", "bossbar", "yellto", "music", -- admins
	"announce", "rank", "round", "sling", "morph", -- admins
}

-- Runs a command: client-side ones here, everything else on the server
local function runCommand(name: string, args: string)
	if MusicUiController.tryLocal(name, args) or TeamMenuController.tryLocal(name) or CursorController.tryLocal(name, args) or GunController.tryLocal(name, args) then
		return -- "/music ui", "/mymusic", "/cursor", "/flare": client-side
	end
	Remotes.ChatCommand:FireServer(name, args)
end

local function registerCommand(name: string)
	local command = Instance.new("TextChatCommand")
	command.Name = "Reclamation_" .. name
	command.PrimaryAlias = "/" .. name
	command.Triggered:Connect(function(_, unfilteredText: string)
		runCommand(name, unfilteredText:match("^%S+%s*(.*)$") or "")
	end)
	command.Parent = TextChatService
end

local function canUnderstand(sender: Player, language: string): boolean
	if sender == player then
		return true
	end
	if GameConfig.Languages.AdminsUnderstandAll and PlayerState.get(player, "IsAdmin") == true then
		return true
	end
	return Languages.knows(PlayerState.get(player, "KnownLanguages"), language)
end

local function tagFor(language: string): string
	local info = Languages.Info[language]
	return if info and info.Tag then info.Tag else string.upper(string.sub(language, 1, 3))
end

-- The text a given reader sees: scrambled if they don't know the speaker's language
local function readableText(sender: Player, language: string, text: string): string
	if canUnderstand(sender, language) then
		return text
	end
	return Languages.garble(text, language)
end

local function onIncomingMessage(message: TextChatMessage): TextChatMessageProperties?
	local source = message.TextSource
	if not source then
		return nil -- system message: leave it alone
	end
	local sender = Players:GetPlayerByUserId(source.UserId)
	if not sender then
		return nil
	end

	local language: string = PlayerState.get(sender, "SpeakLanguage")
	local info = Languages.Info[language]
	if not info then
		return nil
	end

	local properties = Instance.new("TextChatMessageProperties")
	properties.Text = TextFormat.format(readableText(sender, language, message.Text))
	properties.PrefixText = ("[%s] %s"):format(tagFor(language), message.PrefixText) -- plain, like normal Roblox chat
	return properties
end

----------------------------------------------------------------------
-- Overhead speech bubbles
----------------------------------------------------------------------

type BubbleHolder = { Gui: BillboardGui, List: Frame, Adornee: Instance }
local holders: { [Player]: BubbleHolder } = {}
local seenMessages: { [string]: boolean } = {}

local function getHolder(sender: Player): BubbleHolder?
	local character = sender.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end

	local holder = holders[sender]
	if holder and holder.Adornee == head and holder.Gui.Parent then
		return holder
	end
	if holder then
		holder.Gui:Destroy()
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "ReclamationBubbles"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(300, 220)
	gui.StudsOffset = Vector3.new(0, head.Size.Y / 2 + 0.6, 0)
	gui.MaxDistance = GameConfig.Chat.ProximityRange * 1.5
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Anchored so the newest bubble sits at the bottom of this frame, just over the head
	local list = Instance.new("Frame")
	list.AnchorPoint = Vector2.new(0.5, 1)
	list.Position = UDim2.fromScale(0.5, 0.5)
	list.Size = UDim2.fromScale(1, 0.5)
	list.BackgroundTransparency = 1
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	holder = { Gui = gui, List = list, Adornee = head }
	holders[sender] = holder
	return holder
end

local bubbleOrder = 0

-- Only the newest (bottom) bubble keeps its tail, like Roblox's chat
local function refreshTails(list: Instance)
	local newest: TextLabel? = nil
	for _, child in list:GetChildren() do
		if child:IsA("TextLabel") and (not newest or child.LayoutOrder > newest.LayoutOrder) then
			newest = child
		end
	end
	for _, child in list:GetChildren() do
		local tailPart = child:FindFirstChild("Tail")
		if tailPart then
			tailPart.Visible = child == newest
		end
	end
end

local function showBubble(sender: Player, rawText: string)
	local chat = GameConfig.Chat
	local holder = getHolder(sender)
	if not holder then
		return
	end
	local language: string = PlayerState.get(sender, "SpeakLanguage")
	local info = Languages.Info[language]
	if not info then
		return
	end

	local text = readableText(sender, language, string.sub(rawText, 1, chat.BubbleMaxChars))

	-- Looks like Roblox's own chat bubble: white, rounded, dark text, a little tail
	bubbleOrder += 1
	local bubble = Instance.new("TextLabel")
	bubble.LayoutOrder = bubbleOrder
	bubble.AutomaticSize = Enum.AutomaticSize.XY
	bubble.Size = UDim2.fromOffset(0, 0)
	bubble.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
	bubble.BackgroundTransparency = 0
	bubble.BorderSizePixel = 0
	bubble.RichText = true
	bubble.TextWrapped = true
	bubble.Font = Enum.Font.GothamMedium
	bubble.TextSize = 16
	bubble.TextColor3 = Color3.fromRGB(57, 59, 61)
	bubble.Text = ('<font color="#8A8D91">[%s]</font> %s'):format(tagFor(language), TextFormat.format(text))
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = bubble
	local padding = Instance.new("UIPadding")
	padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	padding.Parent = bubble
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(280, math.huge)
	limit.Parent = bubble
	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0.5, 0, 1, 0)
	tail.Size = UDim2.fromOffset(11, 11)
	tail.Rotation = 45
	tail.BackgroundColor3 = bubble.BackgroundColor3
	tail.BackgroundTransparency = bubble.BackgroundTransparency
	tail.BorderSizePixel = 0
	tail.ZIndex = 0
	tail.Visible = false
	tail.Parent = bubble
	bubble.Parent = holder.List

	-- Keep only the newest few
	local bubbles = {}
	for _, child in holder.List:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(bubbles, child)
		end
	end
	table.sort(bubbles, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #bubbles - chat.BubblesPerPlayer do
		bubbles[i]:Destroy()
	end
	refreshTails(holder.List)

	task.delay(chat.BubbleDuration, function()
		if bubble.Parent then
			local list = bubble.Parent
			bubble:Destroy()
			refreshTails(list)
		end
	end)
end

local function onMessageReceived(message: TextChatMessage)
	if not GameConfig.Chat.Bubbles then
		return
	end
	local source = message.TextSource
	if not source or seenMessages[message.MessageId] then
		return
	end
	seenMessages[message.MessageId] = true
	task.delay(30, function()
		seenMessages[message.MessageId] = nil
	end)

	local sender = Players:GetPlayerByUserId(source.UserId)
	if sender then
		showBubble(sender, message.Text)
	end
end

local function hookChannel(channel: Instance)
	if channel:IsA("TextChannel") and channel.Name ~= "RBXSystem" then
		channel.MessageReceived:Connect(onMessageReceived)
	end
end

----------------------------------------------------------------------

-- Commands that only make sense with "/" (they are handled on your own client)
local LOCAL_ONLY = { cursor = true, flare = true, team = true, mymusic = true }

function ChatController.start()
	local known = {}
	for _, name in COMMANDS do
		registerCommand(name)
		if not LOCAL_ONLY[name] then
			known[name] = true
		end
	end

	-- ":armoredtitanintro" works like "/armoredtitanintro". (The server hides the line from chat.)
	TextChatService.SendingMessage:Connect(function(message: TextChatMessage)
		local word, args = message.Text:match("^:(%a+)%s*(.*)$")
		if word and known[word:lower()] then
			runCommand(word:lower(), args)
		end
	end)

	-- Roblox's built-in "/t" is team chat. This game uses /t for inner thoughts instead.
	task.spawn(function()
		local team = TextChatService:WaitForChild("RBXTeamCommand", 10)
		if team and team:IsA("TextChatCommand") then
			team.Enabled = false
		end
	end)

	-- Window on/off from Config.Chat. The input bar stays so people can still type.
	pcall(function()
		TextChatService.ChatWindowConfiguration.Enabled = GameConfig.Chat.ShowChatWindow
		TextChatService.ChatInputBarConfiguration.Enabled = true
		TextChatService.BubbleChatConfiguration.Enabled = false -- we draw our own (tags + languages)
	end)

	TextChatService.OnIncomingMessage = onIncomingMessage

	-- Bubbles come from the channel itself, so they work even with the chat window hidden
	task.spawn(function()
		local channels = TextChatService:WaitForChild("TextChannels", 30)
		if not channels then
			return
		end
		for _, channel in channels:GetChildren() do
			hookChannel(channel)
		end
		channels.ChildAdded:Connect(hookChannel)
	end)

	Players.PlayerRemoving:Connect(function(leaving)
		local holder = holders[leaving]
		if holder then
			holder.Gui:Destroy()
			holders[leaving] = nil
		end
	end)
end

return ChatController
