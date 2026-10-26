--[[
	MusicParse (shared) - pure helpers for the music commands and panel (unit tested).
]]

local MusicParse = {}

-- "123", "rbxassetid://123", "https://create.roblox.com/store/asset/123/Name" -> 123.
-- Returns every id found, in order, up to `max`. Ignores tiny numbers (volume etc).
function MusicParse.ids(text: string, max: number?): { number }
	local limit = max or 10
	local found = {}
	for digits in text:gmatch("%d+") do
		if #digits >= 5 and #digits <= 16 then
			table.insert(found, tonumber(digits) :: number)
			if #found >= limit then
				break
			end
		end
	end
	return found
end

-- First library entry whose title or category contains `query` (case-insensitive).
-- Exact title matches win.
function MusicParse.search(library: { any }, query: string): any?
	local needle = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if needle == "" then
		return nil
	end
	local partial = nil
	for _, entry in library do
		local title = entry.Title:lower()
		if title == needle then
			return entry
		end
		if not partial and (title:find(needle, 1, true) or (entry.Category and entry.Category:lower():find(needle, 1, true))) then
			partial = entry
		end
	end
	return partial
end

-- 125 -> "2:05"
function MusicParse.time(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

return MusicParse
