--[[
	CursorController (client)
	/cursor - anyone can change their OWN mouse cursor. It only affects you.

	  /cursor <image id>        e.g. /cursor 1234567890  (a decal / image asset id, PNG up to 256x256)
	  /cursor rbxassetid://...  same thing
	  /cursor <preset name>     a name from Config.Cursor.Presets
	  /cursor default           back to the normal cursor
	  /cursor list              shows the presets

	The choice is kept until you leave. Add presets in Config.Cursor.Presets.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)

local ThoughtController = require(script.Parent.ThoughtController)

local CursorController = {}

local current = ""

local function apply(icon: string)
	current = icon
	UserInputService.MouseIcon = icon
end

local function say(text: string)
	ThoughtController.push(text, "System")
end

-- "/cursor ..." (client side). Returns true if it handled the command.
function CursorController.tryLocal(name: string, args: string): boolean
	if name:lower() ~= "cursor" then
		return false
	end
	local text = args:gsub("^%s+", ""):gsub("%s+$", "")
	local lowered = text:lower()
	local presets = GameConfig.Cursor.Presets

	if lowered == "" or lowered == "help" then
		say("Usage: /cursor <image id | preset | default | list>")
	elseif lowered == "default" or lowered == "reset" or lowered == "off" then
		apply("")
		say("Cursor reset.")
	elseif lowered == "list" then
		local names = {}
		for presetName in presets do
			table.insert(names, presetName)
		end
		table.sort(names)
		say(if #names > 0 then "Cursors: " .. table.concat(names, ", ") else "No presets yet. Use /cursor <image id>.")
	else
		local icon: string? = nil
		for presetName, value in presets do
			if presetName:lower() == lowered then
				icon = value
			end
		end
		if not icon then
			local id = lowered:match("^rbxassetid://(%d+)$") or lowered:match("^(%d+)$")
			if id then
				icon = "rbxassetid://" .. id
			end
		end
		if icon then
			apply(icon)
			say("Cursor changed.")
		else
			say("I don't know that cursor. Try an image id, or /cursor list.")
		end
	end
	return true
end

function CursorController.getCurrent(): string
	return current
end

return CursorController
