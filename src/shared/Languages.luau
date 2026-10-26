--[[
	Languages (shared)
	Eldian and Marleyan chat. Each player has:
	  SpeakLanguage   - what their chat messages are written in
	  KnownLanguages  - what they can read ("Eldian,Marleyan")
	Anyone who doesn't know the speaker's language sees scrambled pseudo-words of the
	same length and capitalisation instead. The syllables below are invented stand-ins,
	not real languages - edit freely.

	NOTE: scrambling happens on the READER's client (see ChatController). It stops
	normal players reading things they shouldn't, but it is not tamper-proof.
]]

local Languages = {}

Languages.List = { "Eldian", "Marleyan" }

Languages.Info = {
	Eldian = {
		Tag = "ELD", -- shown as [ELD] before the speaker's name and in speech bubbles
		Color = Color3.fromRGB(150, 205, 170),
		Syllables = { "ar", "el", "ia", "en", "ri", "sha", "ven", "lu", "ora", "ith", "an", "na", "mi", "ke", "dor", "ael", "ys", "eth" },
	},
	Marleyan = {
		Tag = "MAR", -- shown as [MAR]
		Color = Color3.fromRGB(215, 170, 110),
		Syllables = { "ach", "ung", "ver", "sch", "ek", "ott", "ras", "hel", "dun", "ig", "kor", "bar", "stren", "tz", "ur", "lan", "gen", "mut" },
	},
}

-- "marleyan" / "MARLEYAN" -> "Marleyan"; nil if it isn't a language
function Languages.canonical(name: string): string?
	local lowered = name:lower()
	for _, language in Languages.List do
		if language:lower() == lowered then
			return language
		end
	end
	return nil
end

function Languages.parseKnown(text: string): { [string]: boolean }
	local set = {}
	for part in text:gmatch("[^,]+") do
		local language = Languages.canonical(part)
		if language then
			set[language] = true
		end
	end
	return set
end

function Languages.formatKnown(set: { [string]: boolean }): string
	local parts = {}
	for _, language in Languages.List do
		if set[language] then
			table.insert(parts, language)
		end
	end
	return table.concat(parts, ",")
end

-- Pure check: does this "Eldian,Marleyan" string include the language?
function Languages.knows(knownText: string, language: string): boolean
	return Languages.parseKnown(knownText)[language] == true
end

local function hash(text: string): number
	local h = 5381
	for i = 1, #text do
		h = (h * 33 + text:byte(i)) % 2147483647
	end
	return h
end

-- Replaces every word with a same-length pseudo-word. Same word + same language always
-- gives the same result, so repeated words look consistent. Punctuation/spaces/digits
-- and the *formatting asterisks* are left alone.
function Languages.garble(text: string, language: string): string
	local info = Languages.Info[language]
	if not info then
		return text
	end
	local syllables = info.Syllables

	return (text:gsub("%a+", function(word)
		local seed = hash(language .. word:lower())
		local built = ""
		while #built < #word do
			seed = (seed * 1103515245 + 12345) % 2147483648
			built ..= syllables[seed % #syllables + 1]
		end
		built = built:sub(1, #word)
		if word:sub(1, 1):match("%u") then
			built = built:sub(1, 1):upper() .. built:sub(2)
		end
		return built
	end))
end

return Languages
