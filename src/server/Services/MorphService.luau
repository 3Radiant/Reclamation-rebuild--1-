--[[
	MorphService (server)
	The start of the morph system: custom shirt / pants on a player's human body.

	  /shirt <me|all|name> <id|none|reset> [true|false]
	  /pants <me|all|name> <id|none|reset> [true|false]

	The last argument is "persist". true = the clothing is remembered and re-applied every time
	the player respawns (until they leave the server or you /shirt <target> reset). false (the
	default) = it only lasts for this life.

	<id> is the catalog item id of a shirt / pants (the number in its web page URL). The
	catalog id is not the same as the texture id, so we load the item and read its template; if
	that fails the number is used as a texture id directly.

	Remembered clothing lives in memory only (it ends with the server). To keep it between
	sessions, save MorphService.getSaved(player) to a DataStore and restore it with setSaved.
]]

local InsertService = game:GetService("InsertService")


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Morphs = require(ReplicatedStorage:WaitForChild("Shared").Configs.Morphs)

local MorphService = {}

type Saved = { Shirt: (string | boolean)?, Pants: (string | boolean)? } -- false = "bare" (no clothing)

local saved: { [Player]: Saved } = {}
local templateCache: { [string]: string } = {}

local CLASS = { Shirt = "Shirt", Pants = "Pants" }
local PROPERTY = { Shirt = "ShirtTemplate", Pants = "PantsTemplate" }

-- Catalog item id -> texture content id. Yields. nil if nothing usable.
function MorphService.resolve(kind: string, id: number): string?
	local key = kind .. id
	if templateCache[key] then
		return templateCache[key]
	end
	local template: string? = nil
	local ok, asset = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if ok and asset then
		local item = asset:FindFirstChildOfClass(CLASS[kind], true)
		if item then
			template = (item :: any)[PROPERTY[kind]]
		end
		asset:Destroy()
	end
	if not template or template == "" then
		template = "rbxassetid://" .. id -- maybe they gave us the texture id already
	end
	templateCache[key] = template
	return template
end

local function applyTo(character: Model, kind: string, value: string | boolean | nil)
	if character:GetAttribute("IsTitan") then
		return
	end
	local old = character:FindFirstChildOfClass(CLASS[kind])
	while old do
		old:Destroy()
		old = character:FindFirstChildOfClass(CLASS[kind])
	end
	if type(value) == "string" then
		local item = Instance.new(CLASS[kind])
		;(item :: any)[PROPERTY[kind]] = value
		item.Parent = character
	end
end

-- template: texture content id, or nil to take the clothing off.
-- persist: also remember it for future lives.
function MorphService.set(player: Player, kind: string, template: string?, persist: boolean)
	assert(CLASS[kind], "kind must be Shirt or Pants")
	if persist then
		local entry = saved[player] or {}
		saved[player] = entry
		entry[kind] = if template then template else false
	end
	if player.Character then
		applyTo(player.Character, kind, template)
	end
end

-- Forget remembered clothing (back to the player's own avatar from the next life)
function MorphService.reset(player: Player, kind: string?)
	local entry = saved[player]
	if not entry then
		return
	end
	if kind then
		entry[kind] = nil
	else
		saved[player] = nil
	end
end

function MorphService.getSaved(player: Player): Saved?
	return saved[player]
end

function MorphService.setSaved(player: Player, data: Saved)
	saved[player] = data
end

-- Called by PlayerService when a fresh human body spawns. Yields briefly for the avatar's own
-- clothes to load so ours go on top.
function MorphService.list(team: string): { string }
	local names = {}
	local side = (Morphs :: any)[team]
	for name in (side and side.List) or {} do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

local function findMorph(team: string, wanted: string): (string?, any?)
	local side = (Morphs :: any)[team]
	for name, morph in (side and side.List) or {} do
		if name:lower() == wanted:lower() or (morph.Display or ""):lower() == wanted:lower() then
			return name, morph
		end
	end
	return nil, nil
end

-- Accessories entries are either "Name" or { Name = "Name", Offset = Vector3, Rotation = Vector3 (degrees) }
local function accessoryEntry(entry: any): (string, Vector3, Vector3)
	if type(entry) == "string" then
		return entry, Vector3.zero, Vector3.zero
	end
	return entry.Name, entry.Offset or Vector3.zero, entry.Rotation or Vector3.zero
end

-- Which side's list the player's morph comes from (normally their own side; admins can force another)
local function morphTeamOf(player: Player): string
	return player:GetAttribute("MorphTeam") or (player.Team and player.Team.Name) or ""
end

-- Dress a human body in the player's current morph (shirt, pants, accessories)
function MorphService.applyMorph(player: Player, character: Model)
	if character:GetAttribute("IsTitan") then
		return
	end
	local morphTeam = morphTeamOf(player)
	local _, morph = findMorph(morphTeam, player:GetAttribute("Morph") or "")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not morph or not humanoid then
		return
	end

	-- Each pass gets a number; if a newer pass starts while this one is waiting, this one stops
	local pass = (character:GetAttribute("MorphPass") or 0) + 1
	character:SetAttribute("MorphPass", pass)

	for _, child in character:GetChildren() do
		if child:GetAttribute("MorphItem") then
			child:Destroy() -- previous morph's accessories
		end
	end

	if morph.Shirt ~= nil then
		applyTo(character, "Shirt", if morph.Shirt then MorphService.resolve("Shirt", morph.Shirt) else nil)
	end
	if morph.Pants ~= nil then
		applyTo(character, "Pants", if morph.Pants then MorphService.resolve("Pants", morph.Pants) else nil)
	end

	if character:GetAttribute("MorphPass") ~= pass then
		return
	end

	local folder = ServerStorage:FindFirstChild("Morphs")
	local sideFolder = folder and folder:FindFirstChild(morphTeam)
	for _, entry in morph.Accessories or {} do
		if character:GetAttribute("MorphPass") ~= pass then
			return
		end
		local accessoryName, offset, rotation = accessoryEntry(entry)
		local template = sideFolder and sideFolder:FindFirstChild(accessoryName)
		if template and template:IsA("Accessory") then
			local accessory = template:Clone()
			accessory:SetAttribute("MorphItem", true)
			humanoid:AddAccessory(accessory)
			-- Offset / rotation: shift the weld that holds it to the body
			if offset ~= Vector3.zero or rotation ~= Vector3.zero then
				local handle = accessory:FindFirstChild("Handle")
				local weld = handle and handle:WaitForChild("AccessoryWeld", 2)
				if weld and weld:IsA("Weld") then
					weld.C0 = weld.C0 * CFrame.new(offset) * CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
				end
			end
		else
			warn(("[MorphService] Accessory '%s' not found in ServerStorage > Morphs > %s"):format(accessoryName, morphTeam))
		end
	end
end

local function refreshBody(player: Player)
	if player.Character then
		task.spawn(MorphService.applyMorph, player, player.Character)
	end
end

-- Player picks a morph from their own side. Returns ok, message.
function MorphService.choose(player: Player, wanted: string): (boolean, string)
	local team = player.Team and player.Team.Name
	if not team or not (Morphs :: any)[team] then
		return false, "Join a side first."
	end
	if player:GetAttribute("MorphLocked") then
		return false, "This uniform was assigned to you. You can't change it."
	end
	if not Morphs.AllowSwitch then
		return false, "Uniforms can't be changed right now."
	end
	local name, morph = findMorph(team, wanted)
	if not name then
		return false, ("No uniform called '%s'. Options: %s"):format(wanted, table.concat(MorphService.list(team), ", "))
	end
	player:SetAttribute("Morph", name)
	player:SetAttribute("MorphTeam", nil)
	refreshBody(player)
	return true, ("Uniform: %s."):format(morph.Display or name)
end

-- ADMIN: force a morph onto someone. "Name" is searched in their own side first, then the others;
-- "Marleyan:Officer" picks a side explicitly. Locked until MorphService.release.
function MorphService.force(target: Player, wanted: string): (boolean, string)
	local sideName: string? = nil
	local morphName = wanted
	local prefix, rest = wanted:match("^(%a+):(.+)$")
	if prefix then
		for key in Morphs :: any do
			if type(key) == "string" and key:lower() == prefix:lower() and type((Morphs :: any)[key]) == "table" then
				sideName, morphName = key, rest
			end
		end
	end

	local name, morph
	if sideName then
		name, morph = findMorph(sideName, morphName)
	else
		local own = target.Team and target.Team.Name
		local order = { own }
		for _, other in { "Eldian", "Marleyan" } do
			if other ~= own then
				table.insert(order, other)
			end
		end
		for _, candidate in order do
			name, morph = findMorph(candidate, morphName)
			if name then
				sideName = candidate
				break
			end
		end
	end
	if not name or not sideName then
		return false, ("No uniform called '%s'."):format(wanted)
	end

	target:SetAttribute("Morph", name)
	target:SetAttribute("MorphTeam", sideName)
	target:SetAttribute("MorphLocked", true)
	refreshBody(target)
	return true, ("%s (%s)"):format(morph.Display or name, sideName)
end

-- ADMIN: lift a forced morph; the player goes back to their side's Default
function MorphService.release(target: Player)
	target:SetAttribute("MorphLocked", nil)
	target:SetAttribute("MorphTeam", nil)
	local team = target.Team and target.Team.Name
	local side = team and (Morphs :: any)[team]
	target:SetAttribute("Morph", side and side.Default or nil)
	refreshBody(target)
end

-- Keep their choice if it exists on the new side, otherwise the Default (a forced morph stays)
function MorphService.onTeamChanged(player: Player, team: string)
	if player:GetAttribute("MorphLocked") then
		return
	end
	local side = (Morphs :: any)[team]
	if side and not findMorph(team, player:GetAttribute("Morph") or "") then
		player:SetAttribute("Morph", side.Default)
	end
end

-- Morph first, then any admin /shirt /pants overrides on top
function MorphService.onSpawn(player: Player, character: Model)
	local function dress()
		if character.Parent == nil then
			return
		end
		MorphService.applyMorph(player, character)
		local entry = saved[player]
		if entry then
			for kind in CLASS do
				local value = (entry :: any)[kind]
				if value ~= nil then
					applyTo(character, kind, value)
				end
			end
		end
	end

	local loaded = false
	local connection = player.CharacterAppearanceLoaded:Connect(function(loadedCharacter)
		if loadedCharacter == character then
			loaded = true
			task.spawn(dress) -- the final pass: runs after the avatar's own items are on
		end
	end)
	task.delay(15, function()
		connection:Disconnect()
	end)

	local limit = if player:HasAppearanceLoaded() then 1.5 else 5
	local started = os.clock()
	while not loaded and os.clock() - started < limit and character.Parent ~= nil do
		task.wait(0.1)
	end
	if not loaded then
		dress() -- the event may still fire later; that runs one more pass
	end
end

function MorphService.remove(player: Player)
	saved[player] = nil
end

return MorphService
