--[[
	YellController (client)
	Yells: a dark card at the bottom of the screen. The text is at the top-left, the
	speaker's face (a headshot of their avatar) fades in on the right, and their username
	sits bottom-left under the text, followed by their language tag ([ELD]/[MAR]).

	Newest yell at the bottom, older ones slide up; thought cards move up above them.
	If you don't understand the speaker's language the words are scrambled, like in chat.
	Server -> client: Remotes.Yell. Look and timing: Config.Yell.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local Languages = require(Shared.Languages)
local PlayerState = require(Shared.PlayerState)
local Remotes = require(Shared.Remotes)
local TextFormat = require(Shared.TextFormat)

local ThoughtController = require(script.Parent.ThoughtController)

local player = Players.LocalPlayer
local settings = GameConfig.Yell

local YellController = {}

local SLIDE = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local CARD_MIN_HEIGHT = 96
local GAP = 8
local PORTRAIT = 96

type Entry = { Frame: CanvasGroup, Height: number }

local container: Frame
local entries: { Entry } = {}
local thumbnails: { [number]: string } = {}

local function getThumbnail(userId: number): string?
	if thumbnails[userId] then
		return thumbnails[userId]
	end
	local ok, image = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	if ok and image then
		thumbnails[userId] = image
		return image
	end
	return nil
end

local function canUnderstand(speaker: Player?, language: string): boolean
	if speaker == player then
		return true
	end
	if GameConfig.Languages.AdminsUnderstandAll and PlayerState.get(player, "IsAdmin") == true then
		return true
	end
	return Languages.knows(PlayerState.get(player, "KnownLanguages"), language)
end

local function restack()
	local offset = 0
	for i = #entries, 1, -1 do
		local entry = entries[i]
		TweenService:Create(entry.Frame, SLIDE, { Position = UDim2.new(0.5, 0, 1, -offset) }):Play()
		offset += entry.Height + GAP
	end
	-- Thoughts sit above the yells
	ThoughtController.setLift(if offset > 0 then offset - GAP + 10 else 0)
end

local function dismiss(entry: Entry)
	local index = table.find(entries, entry)
	if not index then
		return
	end
	table.remove(entries, index)
	TweenService:Create(entry.Frame, TweenInfo.new(0.45), { GroupTransparency = 1 }):Play()
	task.delay(0.5, function()
		entry.Frame:Destroy()
	end)
	restack()
end

function YellController.show(data: { Text: string, Name: string, UserId: number, Language: string? })
	local speaker = Players:GetPlayerByUserId(data.UserId)
	local language = data.Language
	local info = if language then Languages.Info[language] else nil

	local text = data.Text
	if language and info and not canUnderstand(speaker, language) then
		text = Languages.garble(text, language)
	end
	local rich = TextFormat.format(text)

	local width = settings.Width
	local textWidth = width - PORTRAIT - 28
	local plain = text:gsub("%*", "")
	local bounds = TextService:GetTextSize(plain, settings.TextSize, Enum.Font.GothamMedium, Vector2.new(textWidth, 1000))
	local height = math.max(CARD_MIN_HEIGHT, 16 + bounds.Y + 34)

	local card = Instance.new("CanvasGroup")
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, 40)
	card.Size = UDim2.fromOffset(width, height)
	card.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
	card.BackgroundTransparency = 0.12
	card.BorderSizePixel = 0
	card.GroupTransparency = 1
	card.Parent = container
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.88
	stroke.Parent = card

	-- Portrait on the right, its left edge fading into the card
	local portrait = Instance.new("ImageLabel")
	portrait.AnchorPoint = Vector2.new(1, 1)
	portrait.Position = UDim2.fromScale(1, 1)
	portrait.Size = UDim2.fromOffset(PORTRAIT, math.min(PORTRAIT, height))
	portrait.BackgroundTransparency = 1
	portrait.ScaleType = Enum.ScaleType.Crop
	portrait.ImageTransparency = 1
	portrait.Parent = card
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 0),
		NumberSequenceKeypoint.new(1, 0),
	})
	fade.Parent = portrait
	task.spawn(function()
		local image = getThumbnail(data.UserId)
		if image and portrait.Parent then
			portrait.Image = image
			portrait.ImageTransparency = 0
		end
	end)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(14, 12)
	label.Size = UDim2.fromOffset(textWidth, bounds.Y + 4)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = settings.TextSize
	label.TextColor3 = Color3.fromRGB(245, 245, 245)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.RichText = true
	label.Text = rich
	label.Parent = card

	-- Username (and language tag) bottom-left, under the text
	local nameText = ("<b>%s</b>"):format(TextFormat.escape(data.Name))
	if info and info.Tag then
		nameText ..= ('  <font color="#%s">[%s]</font>'):format(info.Color:ToHex(), info.Tag)
	end
	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.AnchorPoint = Vector2.new(0, 1)
	nameLabel.Position = UDim2.new(0, 14, 1, -8)
	nameLabel.Size = UDim2.fromOffset(textWidth, 18)
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = Color3.fromRGB(205, 208, 214)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.RichText = true
	nameLabel.Text = nameText
	nameLabel.Parent = card

	local entry: Entry = { Frame = card, Height = height }
	table.insert(entries, entry)
	while #entries > settings.MaxVisible do
		dismiss(entries[1])
	end

	TweenService:Create(card, TweenInfo.new(0.3), { GroupTransparency = 0 }):Play()
	restack()

	local lifetime = math.min(settings.BaseLifetime + #data.Text * settings.PerCharLifetime, settings.MaxLifetime)
	task.delay(lifetime, function()
		dismiss(entry)
	end)
end

function YellController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Yells"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.Parent = player:WaitForChild("PlayerGui")

	container = Instance.new("Frame")
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 1, -settings.BottomOffset)
	container.Size = UDim2.fromOffset(settings.Width, 600)
	container.BackgroundTransparency = 1
	container.Active = false
	container.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = container
	local function fit()
		scale.Scale = math.clamp((gui.AbsoluteSize.X - 24) / settings.Width, 0.5, 1)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	Remotes.Yell.OnClientEvent:Connect(function(data)
		if
			typeof(data) == "table"
			and typeof(data.Text) == "string"
			and typeof(data.Name) == "string"
			and typeof(data.UserId) == "number"
		then
			YellController.show(data)
		end
	end)
end

return YellController
