--[[
	ChatService (server)
	Handles slash commands sent by ChatController (the client registers the commands
	with TextChatService and forwards them here), plus language setup.

	Everyone:
	  /t <text>                  inner thought - only you and admins can read it
	  /eldian   /marleyan        choose the language your chat messages are written in
	Admins:
	  /thought <me|all|name> <text>   pop a thought up on someone's screen
	  /lang <me|all|name> <Eldian|Marleyan|Both>   set which languages someone understands
	  /titan <TitanName>              change which Titan you wield (human form only)
	  /cmds                           list commands
]]

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local Languages = require(Shared.Languages)
local PlayerState = require(Shared.PlayerState)
local Remotes = require(Shared.Remotes)
local TitanConfigs = require(Shared.Configs.TitanConfigs)

local AdminService = require(script.Parent.AdminService)
local AnxietyService = require(script.Parent.AnxietyService)
local ArtilleryService = require(script.Parent.ArtilleryService)
local BlimpService = require(script.Parent.BlimpService)
local BossBarService = require(script.Parent.BossBarService)
local IntroService = require(script.Parent.IntroService)
local MessageService = require(script.Parent.MessageService)
local MorphService = require(script.Parent.MorphService)
local MusicService = require(script.Parent.MusicService)
local RoundService = require(script.Parent.RoundService)
local TeamService = require(script.Parent.TeamService)
local YellService = require(script.Parent.YellService)
local ShifterService = require(script.Parent.ShifterService)
local ThoughtService = require(script.Parent.ThoughtService)
local SlingService = require(script.Parent.SlingService)

local ChatService = {}

local MAX_COMMAND_LENGTH = 400
local COMMAND_COOLDOWN = 0.4
local lastCommand: { [Player]: number } = {}

local function trim(text: string): string
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

----------------------------------------------------------------------
-- Languages
----------------------------------------------------------------------

function ChatService.initPlayer(player: Player)
	local known = table.concat(GameConfig.Languages.DefaultKnown, ",")
	PlayerState.set(player, "KnownLanguages", known)
	PlayerState.set(player, "SpeakLanguage", GameConfig.Languages.Default)
end

local function setSpeak(player: Player, language: string)
	if not Languages.knows(PlayerState.get(player, "KnownLanguages"), language) then
		ThoughtService.system(player, ("I don't know how to speak %s."):format(language))
		return
	end
	PlayerState.set(player, "SpeakLanguage", language)
	ThoughtService.system(player, ("I'll speak %s from now on."):format(language))
end

local function setKnown(player: Player, set: { [string]: boolean })
	PlayerState.set(player, "KnownLanguages", Languages.formatKnown(set))
	-- If they no longer know what they were speaking, move them to one they do know
	if not set[PlayerState.get(player, "SpeakLanguage")] then
		for _, language in Languages.List do
			if set[language] then
				PlayerState.set(player, "SpeakLanguage", language)
				break
			end
		end
	end
end

----------------------------------------------------------------------
-- Commands: handler(player, argsText)
----------------------------------------------------------------------

local playerCommands: { [string]: (Player, string) -> () } = {}
local adminCommands: { [string]: (Player, string) -> () } = {}

playerCommands.t = function(player, args)
	local text = trim(args)
	if text == "" then
		ThoughtService.system(player, "Usage: /t <your thought>")
		return
	end
	text = text:sub(1, GameConfig.Thoughts.MaxLength)

	local targets: { ThoughtService.Target } = { { Player = player, Kind = "Thought" } }
	for _, other in Players:GetPlayers() do
		if other ~= player and AdminService.isAdmin(other) then
			table.insert(targets, { Player = other, Kind = "Overheard", Source = player.DisplayName })
		end
	end
	ThoughtService.sendFiltered(player, text, targets)
end

playerCommands.eldian = function(player)
	setSpeak(player, "Eldian")
end

playerCommands.marleyan = function(player)
	setSpeak(player, "Marleyan")
end

-- /morph                       list your side's uniforms
-- /morph <name>                change your own uniform
-- ADMIN: /morph <me|all|player> <name>   force a uniform (locks it; Side:Name for another side)
--        /morph <me|all|player> reset    lift the force
playerCommands.morph = function(player, args)
	local text = trim(args)
	local team = TeamService.getName(player)

	if AdminService.isAdmin(player) and text ~= "" then
		local first, rest = text:match("^(%S+)%s+(.+)$")
		local targets = if first then AdminService.resolveTargets(player, first) else {}
		if first and #targets > 0 then
			rest = trim(rest)
			if rest:lower() == "reset" or rest:lower() == "unlock" then
				for _, target in targets do
					MorphService.release(target)
					ThoughtService.system(target, "My uniform is my own again.")
				end
				ThoughtService.system(player, ("Uniform released for %d player(s)."):format(#targets))
				return
			end
			local done, lastMessage = 0, ""
			for _, target in targets do
				local ok, message = MorphService.force(target, rest)
				if ok then
					done += 1
					lastMessage = message
					if target ~= player then
						ThoughtService.system(target, "I've been given a new uniform.")
					end
				else
					ThoughtService.system(player, message)
					return
				end
			end
			ThoughtService.system(player, ("Uniform %s forced onto %d player(s)."):format(lastMessage, done))
			return
		end
	end

	if not team then
		ThoughtService.system(player, "Join a side first.")
		return
	end
	if text == "" then
		ThoughtService.system(player, ("Uniforms: %s  (now: %s). Use /morph <name>."):format(table.concat(MorphService.list(team), ", "), tostring(player:GetAttribute("Morph"))))
		return
	end
	local _, message = MorphService.choose(player, text)
	ThoughtService.system(player, message)
end

playerCommands.yell = function(player, args)
	local text = trim(args)
	if text == "" then
		ThoughtService.system(player, "Usage: /yell <text>")
		return
	end
	if not YellService.send(player, text, YellService.nearby(player)) then
		ThoughtService.system(player, "I can't yell again yet.")
	end
end

-- /yellto <me|all|name> <text>
adminCommands.yellto = function(player, args)
	local targetText, text = args:match("^%s*(%S+)%s+(.+)$")
	if not targetText then
		ThoughtService.system(player, "Usage: /yellto <me|all|name> <text>")
		return
	end
	local players = AdminService.resolveTargets(player, targetText)
	if #players == 0 then
		ThoughtService.system(player, ("No player matches '%s'."):format(targetText))
		return
	end
	YellService.send(player, trim(text), players, false)
end

-- /bossbar <player|npc name> [title]   |   /bossbar off [name|all]
adminCommands.bossbar = function(player, args)
	local first, rest = args:match("^%s*(%S+)%s*(.*)$")
	if not first then
		ThoughtService.system(player, "Usage: /bossbar <player|npc> [title]  or  /bossbar off [name|all]")
		return
	end

	if first:lower() == "off" then
		local name = trim(rest)
		if name == "" or name:lower() == "all" then
			BossBarService.clear()
			ThoughtService.system(player, "All boss bars removed.")
		else
			local target = BossBarService.find(name)
			ThoughtService.system(player, if target and BossBarService.remove(target) then "Boss bar removed." else "No boss bar for that target.")
		end
		return
	end

	local target = BossBarService.find(first)
	if not target then
		ThoughtService.system(player, ("Nobody or no NPC named '%s'."):format(first))
		return
	end
	local title = trim(rest)
	BossBarService.add(target, if title ~= "" then title:sub(1, 80) else nil)
	ThoughtService.system(player, "Boss bar added.")
end

-- /announce line one | line two | line three   (cinematic server message to everyone)
adminCommands.announce = function(player, args)
	local lines = {}
	for part in (args .. "|"):gmatch("([^|]*)|") do
		part = trim(part)
		if part ~= "" then
			table.insert(lines, part:sub(1, 120))
		end
	end
	if #lines == 0 then
		ThoughtService.system(player, "Usage: /announce line one | line two")
		return
	end
	MessageService.broadcast(lines)
end

-- /rank <me|name> <rank>    e.g. /rank Bob Lieutenant   (ranks: Config.Ranks, per team)
adminCommands.rank = function(player, args)
	local targetText, rankText = args:match("^%s*(%S+)%s+(.+)$")
	if not targetText then
		ThoughtService.system(player, "Usage: /rank <me|name> <rank>")
		return
	end
	local players = AdminService.resolveTargets(player, targetText)
	if #players == 0 then
		ThoughtService.system(player, ("No player matches '%s'."):format(targetText))
		return
	end
	for _, target in players do
		local rank = TeamService.setRank(target, rankText)
		ThoughtService.system(
			player,
			if rank then ("%s is now a %s."):format(target.DisplayName, rank) else ("%s: no such rank on their team (or no team)."):format(target.DisplayName)
		)
	end
end

-- /round status | start | end [Eldian|Marleyan|draw] | lives <team> <n>
adminCommands.round = function(player, args)
	local action, rest = args:match("^%s*(%S+)%s*(.*)$")
	action = action and action:lower() or "status"
	if action == "start" then
		RoundService.forceStart()
		ThoughtService.system(player, "Starting the round now.")
	elseif action == "end" then
		local result = Languages.canonical(trim(rest)) or "Draw"
		RoundService.forceEnd(result)
		ThoughtService.system(player, ("Ending the round: %s."):format(result))
	elseif action == "lives" then
		local teamText, amount = rest:match("^(%S+)%s+(%d+)")
		local team = teamText and (Languages.canonical(teamText))
		if team and RoundService.setLives(team, tonumber(amount) :: number) then
			ThoughtService.system(player, ("%s now has %s lives."):format(team, amount))
		else
			ThoughtService.system(player, "Usage: /round lives <Eldian|Marleyan> <number>")
		end
	else
		ThoughtService.system(player, RoundService.status())
	end
end

-- /music <play|add|skip|pause|...>  (the panel opens client-side with "/music ui")
adminCommands.music = function(player, args)
	ThoughtService.system(player, MusicService.runCommand(player, args))
end

adminCommands.thought = function(player, args)
	local targetText, text = args:match("^%s*(%S+)%s+(.+)$")
	if not targetText then
		ThoughtService.system(player, "Usage: /thought <me|all|name> <text>")
		return
	end
	local players = AdminService.resolveTargets(player, targetText)
	if #players == 0 then
		ThoughtService.system(player, ("No player matches '%s'."):format(targetText))
		return
	end

	local targets: { ThoughtService.Target } = {}
	for _, target in players do
		table.insert(targets, { Player = target, Kind = "Thought" })
	end
	ThoughtService.sendFiltered(player, trim(text):sub(1, GameConfig.Thoughts.MaxLength), targets)
end

adminCommands.lang = function(player, args)
	local targetText, languageText = args:match("^%s*(%S+)%s+(%S+)%s*$")
	if not targetText then
		ThoughtService.system(player, "Usage: /lang <me|all|name> <Eldian|Marleyan|Both>")
		return
	end

	local set: { [string]: boolean }
	if languageText:lower() == "both" then
		set = { Eldian = true, Marleyan = true }
	else
		local language = Languages.canonical(languageText)
		if not language then
			ThoughtService.system(player, "Languages: Eldian, Marleyan, Both")
			return
		end
		set = { [language] = true }
	end

	local players = AdminService.resolveTargets(player, targetText)
	if #players == 0 then
		ThoughtService.system(player, ("No player matches '%s'."):format(targetText))
		return
	end
	for _, target in players do
		setKnown(target, set)
		ThoughtService.system(target, ("I now understand: %s."):format(PlayerState.get(target, "KnownLanguages")))
	end
end

-- /shifter <me|all|name> <TitanName|none>   (nobody is a shifter until you say so)
adminCommands.shifter = function(player, args)
	local targetText, titanText = args:match("^%s*(%S+)%s*(.*)$")
	if not targetText then
		ThoughtService.system(player, "Usage: /shifter <me|all|name> <Titan|none>")
		return
	end
	local players = AdminService.resolveTargets(player, targetText)
	if #players == 0 then
		ThoughtService.system(player, ("No player matches '%s'."):format(targetText))
		return
	end

	local wanted = trim(titanText):lower():gsub("%s+", "")
	local remove = wanted == "none" or wanted == "off" or wanted == "remove"
	local titanName: string? = nil
	for name in TitanConfigs do
		if name:lower() == wanted then
			titanName = name
		end
	end
	if not remove and not titanName then
		local names = {}
		for name in TitanConfigs do
			table.insert(names, name)
		end
		table.sort(names)
		ThoughtService.system(player, "Titans: " .. table.concat(names, ", ") .. "  (or: none)")
		return
	end

	local changed = 0
	for _, target in players do
		local ok = if remove then ShifterService.unassign(target) else ShifterService.assign(target, titanName :: string)
		if ok then
			changed += 1
			ThoughtService.system(
				target,
				if remove then "The power of the Titan leaves me." else ("I carry the power of the %s."):format(TitanConfigs[titanName :: string].DisplayName)
			)
		end
	end
	ThoughtService.system(player, ("Shifter updated for %d player(s) (shifted players are skipped)."):format(changed))
end

-- /shirt and /pants <me|all|name> <id|none|reset> [true|false]
-- The optional true / false makes the clothing persist across lives (default false).
local function clothingCommand(kind: string, word: string)
	return function(player: Player, args: string)
		local usage = ("Usage: /%s <me|all|name> <id|none|reset> [persist: true|false]"):format(word)
		local first, rest = args:match("^%s*(%S+)%s*(.*)$")
		if not first then
			ThoughtService.system(player, usage)
			return
		end
		-- "/shirt 12345" = yourself
		local lowered = first:lower()
		local targetText = first
		if tonumber(first) or lowered == "none" or lowered == "reset" then
			targetText = "me"
			rest = args
		end
		local idText, persistText = rest:match("^%s*(%S+)%s*(%S*)")
		if not idText then
			ThoughtService.system(player, usage)
			return
		end
		local persist = ({ ["true"] = true, yes = true, on = true, ["1"] = true })[persistText:lower()] == true

		local targets = AdminService.resolveTargets(player, targetText)
		if #targets == 0 then
			ThoughtService.system(player, ("No player matches '%s'."):format(targetText))
			return
		end

		local idLower = idText:lower()
		if idLower == "reset" or idLower == "default" then
			for _, target in targets do
				MorphService.reset(target, kind)
			end
			ThoughtService.system(player, ("Remembered %s cleared for %d player(s): their own avatar returns next life."):format(word, #targets))
			return
		end

		local template: string? = nil
		if idLower ~= "none" and idLower ~= "off" then
			local id = tonumber(idText)
			if not id or id <= 0 or id ~= math.floor(id) then
				ThoughtService.system(player, usage)
				return
			end
			template = MorphService.resolve(kind, id)
		end
		for _, target in targets do
			MorphService.set(target, kind, template, persist)
		end
		ThoughtService.system(
			player,
			("%s %s for %d player(s) (%s)."):format(word, if template then "set" else "removed", #targets, if persist then "persists across lives" else "this life only")
		)
	end
end
adminCommands.shirt = clothingCommand("Shirt", "shirt")
adminCommands.pants = clothingCommand("Pants", "pants")

-- /blimps on|off|status|spawn|... (BlimpService has the full list)
adminCommands.blimps = function(player, args)
	ThoughtService.system(player, BlimpService.handleCommand(player, args))
end

-- /armoredtitanintro: typewriter speech + camera on the Armored Titan's holder
adminCommands.armoredtitanintro = function(player)
	local _, holder = IntroService.play("ArmoredTitan")
	if holder then
		ThoughtService.system(player, ("Intro started. The camera will find %s."):format(holder))
	else
		ThoughtService.system(player, "Intro started, but nobody holds the Armored Titan (use /shifter <player> ArmoredTitan), so the camera won't move.")
	end
end

adminCommands.sling = function(player, args)
	ThoughtService.system(player, SlingService.tune(player, args))
end

adminCommands.titan = function(player, args)
	local wanted = trim(args):lower()
	for name in TitanConfigs do
		if name:lower() == wanted then
			if not ShifterService.assign(player, name) then
				ThoughtService.system(player, "I can't change Titans right now.")
			else
				ThoughtService.system(player, ("I carry the %s."):format(TitanConfigs[name].DisplayName))
			end
			return
		end
	end
	local names = {}
	for name in TitanConfigs do
		table.insert(names, name)
	end
	table.sort(names)
	ThoughtService.system(player, "Titans: " .. table.concat(names, ", "))
end

-- /anxiety <me|all|name> [level 1-10] [seconds]   or   /anxiety <target> off
adminCommands.anxiety = function(player, args)
	local targetText, rest = args:match("^%s*(%S+)%s*(.*)$")
	if not targetText then
		ThoughtService.system(player, "Usage: /anxiety <me|all|name> [1-10] [seconds]  or  /anxiety <target> off")
		return
	end
	local players = AdminService.resolveTargets(player, targetText)
	if #players == 0 then
		ThoughtService.system(player, ("No player matches '%s'."):format(targetText))
		return
	end

	if rest:lower():match("^off") or rest:lower():match("^clear") then
		for _, target in players do
			AnxietyService.clear(target)
		end
		ThoughtService.system(player, ("Anxiety cleared for %d player(s)."):format(#players))
		return
	end

	local levelText, secondsText = rest:match("^(%S*)%s*(%S*)")
	local level = math.clamp(tonumber(levelText) or 6, 1, 10) / 10
	local seconds = math.clamp(tonumber(secondsText) or 20, 1, 600)
	for _, target in players do
		AnxietyService.apply(target, level, seconds)
	end
	ThoughtService.system(player, ("Anxiety %d/10 for %ds on %d player(s)."):format(level * 10, seconds, #players))
end

-- /strike [me|name] : calls a barrage on that player's position (testing / events)
adminCommands.strike = function(player, args)
	local targetText = trim(args)
	if targetText == "" then
		targetText = "me"
	end
	local players = AdminService.resolveTargets(player, targetText)
	local struck = 0
	for _, target in players do
		local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			ArtilleryService.strike(player, "FieldArtillery", root.Position, target.Character)
			struck += 1
		end
	end
	ThoughtService.system(player, if struck > 0 then ("Barrage called on %d target(s)."):format(struck) else "Nobody to strike.")
end

adminCommands.cmds = function(player)
	ThoughtService.system(
		player,
		"/thought <target> <text>  |  /lang <target> <Eldian|Marleyan|Both>  |  /shifter <target> <Titan|none>  |  /armoredtitanintro  |  /blimps on|off|spawn|clear|status|max|...  \n  /shirt /pants <target> <id|none|reset> [persist true|false]  |  /anxiety <target> [1-10] [secs|off]  |  /strike [target]  |  /yellto <target> <text>  |  /bossbar <name> [title]|off  \n  /music <play|add|skip|...|ui>  |  /announce a | b  |  /rank <target> <rank>  |  /round status|start|end|lives   (press ; for the command bar) \n /morph <target> <name|Side:Name|reset>"
	)
end

----------------------------------------------------------------------

-- Local chat: decide, per recipient, whether a message is delivered at all.
-- (Runs on the server, so a client can't "listen in" by editing its own scripts.)
local function setupProximity()
	local channels = TextChatService:WaitForChild("TextChannels", 30)
	local general = channels and channels:WaitForChild("RBXGeneral", 30)
	if not general or not general:IsA("TextChannel") then
		warn("[ChatService] RBXGeneral not found; chat range is not enforced (is TextChatService enabled?)")
		return
	end

	local function rootOf(player: Player): BasePart?
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		return if root and root:IsA("BasePart") then root else nil
	end

	general.ShouldDeliverCallback = function(message: TextChatMessage, recipientSource: TextSource): boolean
		local chat = GameConfig.Chat
		-- ":armoredtitanintro" style commands run instead of being said out loud
		local word = message.Text:match("^:(%a+)")
		if word and message.TextSource and (adminCommands[word:lower()] or playerCommands[word:lower()]) then
			return false
		end
		if chat.GlobalChat then
			return true
		end
		local senderSource = message.TextSource
		if not senderSource then
			return true -- system message
		end
		if senderSource.UserId == recipientSource.UserId then
			return true
		end
		local sender = Players:GetPlayerByUserId(senderSource.UserId)
		local recipient = Players:GetPlayerByUserId(recipientSource.UserId)
		if not sender or not recipient then
			return false
		end
		if chat.AdminsHearAll and AdminService.isAdmin(recipient) then
			return true
		end
		local a, b = rootOf(sender), rootOf(recipient)
		if not a or not b then
			return false
		end
		return (a.Position - b.Position).Magnitude <= chat.ProximityRange
	end
end

function ChatService.start()
	task.spawn(setupProximity)

	Remotes.ChatCommand.OnServerEvent:Connect(function(player: Player, name: any, args: any)
		if typeof(name) ~= "string" or typeof(args) ~= "string" or #args > MAX_COMMAND_LENGTH or #name > 20 then
			return
		end

		local now = os.clock()
		if now - (lastCommand[player] or 0) < COMMAND_COOLDOWN then
			return
		end
		lastCommand[player] = now

		name = name:lower()
		local handler = playerCommands[name]
		if not handler and adminCommands[name] then
			if not AdminService.isAdmin(player) then
				ThoughtService.system(player, "Only admins can do that.")
				return
			end
			handler = adminCommands[name]
		end
		if handler then
			handler(player, args)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastCommand[player] = nil
	end)
end

return ChatService
