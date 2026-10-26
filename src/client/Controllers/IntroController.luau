--[[
	IntroController (client)
	Plays the cinematic intros from Config.Intros (e.g. /armoredtitanintro):

	  * the text types out near the bottom middle of the screen, typewriter style
	  * when the Trigger phrase has been typed, the camera turns to the Titan's holder and slowly
	    closes in; everyone else gets random inner thoughts and a wave of anxiety
	  * after Focus.HoldSeconds the camera returns to normal, the text finishes, holds, fades
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local Remotes = require(Shared.Remotes)

local AnxietyController = require(script.Parent.AnxietyController)
local CameraController = require(script.Parent.CameraController)
local ThoughtController = require(script.Parent.ThoughtController)

local player = Players.LocalPlayer
local rng = Random.new()

local IntroController = {}

local running = false

-- Extra pause after punctuation, so it reads like someone typing a speech
local PAUSE = { [","] = 0.22, [";"] = 0.3, ["."] = 0.55, ["!"] = 0.55, ["?"] = 0.55 }

local function buildGui(): (ScreenGui, TextLabel, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Intro"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 40
	gui.Parent = player:WaitForChild("PlayerGui")

	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(0.5, 0, 1, -64)
	holder.Size = UDim2.new(0.62, 0, 0, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(820, 400)
	limit.MinSize = Vector2.new(260, 0)
	limit.Parent = holder

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = Enum.Font.SpecialElite
	label.TextSize = 22
	label.TextColor3 = Color3.fromRGB(236, 232, 220)
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Bottom
	label.MaxVisibleGraphemes = 0
	label.Parent = holder
	local outline = Instance.new("UIStroke")
	outline.Thickness = 1.5
	outline.Transparency = 0.35
	outline.Color = Color3.new(0, 0, 0)
	outline.Parent = label

	return gui, label, holder
end

-- The camera / thoughts / anxiety part, run when the trigger phrase appears
local function playMoment(config: any, holderUserId: number)
	local holderPlayer = if holderUserId ~= 0 then Players:GetPlayerByUserId(holderUserId) else nil
	local isHolder = holderPlayer == player

	if holderPlayer and not isHolder then
		CameraController.focusOn(holderPlayer, config.Focus)
		task.delay(config.Focus.HoldSeconds, CameraController.releaseFocus)
	end

	if isHolder then
		if config.HolderThought then
			ThoughtController.push(config.HolderThought, "Thought")
		end
		return
	end

	AnxietyController.apply(config.AnxietyLevel, config.AnxietySeconds)
	local pool = table.clone(config.Thoughts)
	for _ = 1, math.min(config.ThoughtCount, #pool) do
		local index = rng:NextInteger(1, #pool)
		ThoughtController.push(table.remove(pool, index), "Thought")
		task.wait(rng:NextNumber(1.6, 2.6))
	end
end

function IntroController.play(id: string, holderUserId: number)
	local config = GameConfig.Intros[id]
	if not config or running then
		return
	end
	running = true

	local gui, label, holder = buildGui()
	label.Text = config.Text
	ThoughtController.setLift(150)

	local sound: Sound? = nil
	if config.Sound and config.Sound ~= "" then
		sound = Instance.new("Sound")
		sound.Name = "IntroSound"
		sound.SoundId = config.Sound
		sound.Volume = config.SoundVolume or 1
		sound.Parent = gui
		sound:Play()
	end

	local _, triggerEnd = string.find(config.Text, config.Trigger, 1, true)
	local total = utf8.len(config.Text) or #config.Text
	local triggered = false

	for i = 1, total do
		label.MaxVisibleGraphemes = i
		if not triggered and triggerEnd and i >= triggerEnd then
			triggered = true
			task.spawn(playMoment, config, holderUserId)
		end
		local character = string.sub(config.Text, i, i)
		task.wait(1 / config.CharsPerSecond + (PAUSE[character] or 0))
	end

	task.wait(config.EndHold)
	TweenService:Create(label, TweenInfo.new(1.4), { TextTransparency = 1 }):Play()
	TweenService:Create(label.UIStroke, TweenInfo.new(1.4), { Transparency = 1 }):Play()
	task.wait(1.5)
	ThoughtController.setLift(0)
	if sound then
		TweenService:Create(sound, TweenInfo.new(0.8), { Volume = 0 }):Play() -- ease out if it is still going
		task.wait(0.8)
	end
	gui:Destroy()
	running = false
end

function IntroController.start()
	Remotes.Intro.OnClientEvent:Connect(function(data)
		if typeof(data) == "table" and typeof(data.Id) == "string" then
			task.spawn(IntroController.play, data.Id, if typeof(data.HolderUserId) == "number" then data.HolderUserId else 0)
		end
	end)
end

return IntroController
