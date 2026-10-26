--[[
	YellService (server)
	Yells: a card at the bottom of the screen with the text, the speaker's face on the right
	and their username bottom-left. Player text is filtered for every recipient.

		YellService.send(speaker, text, recipients)   recipients: { Player }
		YellService.nearby(speaker)                   everyone within Config.Yell.Range (+ the speaker)

	Chat: /yell <text>  (anyone, short range, cooldown)    /yellto <me|all|name> <text>  (admins)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local PlayerState = require(Shared.PlayerState)
local Remotes = require(Shared.Remotes)

local YellService = {}

local lastYell: { [Player]: number } = {}

function YellService.nearby(speaker: Player): { Player }
	local origin = speaker.Character and speaker.Character:FindFirstChild("HumanoidRootPart")
	local result = { speaker }
	if not origin or not origin:IsA("BasePart") then
		return result
	end
	for _, other in Players:GetPlayers() do
		local root = other ~= speaker and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - origin.Position).Magnitude <= GameConfig.Yell.Range then
			table.insert(result, other)
		end
	end
	return result
end

-- true if sent. Set rateLimit = false for admin yells.
function YellService.send(speaker: Player, text: string, recipients: { Player }, rateLimit: boolean?): boolean
	text = text:sub(1, GameConfig.Yell.MaxLength)
	if text:match("^%s*$") then
		return false
	end

	if rateLimit ~= false then
		local now = os.clock()
		if now - (lastYell[speaker] or -math.huge) < GameConfig.Yell.Cooldown then
			return false
		end
		lastYell[speaker] = now
	end

	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, speaker.UserId, Enum.TextFilterContext.PublicChat)
	end)
	local filterResult = nil
	if ok then
		filterResult = result
	elseif RunService:IsStudio() then
		warn("[YellService] Text filtering unavailable in Studio, showing raw text:", result)
	else
		return false -- never show unfiltered player text in a live game
	end

	local language = PlayerState.get(speaker, "SpeakLanguage")
	for _, recipient in recipients do
		local shown = text
		if filterResult then
			local okFilter, filtered = pcall(function()
				return filterResult:GetNonChatStringForUserAsync(recipient.UserId)
			end)
			if not okFilter then
				continue
			end
			shown = filtered
		end
		Remotes.Yell:FireClient(recipient, {
			Text = shown,
			Name = speaker.Name, -- the username, as asked
			UserId = speaker.UserId,
			Language = language,
		})
	end
	return true
end

Players.PlayerRemoving:Connect(function(player)
	lastYell[player] = nil
end)

return YellService
