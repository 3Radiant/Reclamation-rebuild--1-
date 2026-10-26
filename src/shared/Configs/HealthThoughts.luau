--[[
	HealthThoughts (shared) - what your character thinks when you press J.
	Tiers are checked from the top: the first tier whose Min <= your health fraction
	wins, and one of its Lines is picked at random. Add as many lines/tiers as you like.
	Supports *italic*, **bold**, ***both***.
]]

local HealthThoughts = {}

HealthThoughts.Human = {
	{ Min = 0.999, Lines = { "I currently feel perfect.", "Not a scratch on me. Good.", "My body feels light. I'm ready." } },
	{ Min = 0.75, Lines = { "A few scratches. Nothing I can't ignore.", "I'm bruised, but still standing." } },
	{ Min = 0.5, Lines = { "My injuries begin to hurt.", "Every breath is starting to ache.", "I can feel the blood... I'm slowing down." } },
	{ Min = 0.25, Lines = { "I'm in bad shape. I can't take much more.", "My vision is blurring. *Keep moving.*" } },
	{ Min = 0.1, Lines = { "At this rate, I will perish.", "I can barely stay on my feet...", "Is this how it ends?" } },
	{ Min = 0, Lines = { "...I can't feel my legs.", "It's getting dark." } },
}

HealthThoughts.Titan = {
	{ Min = 0.999, Lines = { "This body is mine. Nothing can stop me." } },
	{ Min = 0.75, Lines = { "Just scratches. The steam is already closing them." } },
	{ Min = 0.5, Lines = { "The wounds are deep... my body is struggling to keep up." } },
	{ Min = 0.25, Lines = { "This body is failing me. I can't hold this form much longer." } },
	{ Min = 0, Lines = { "One more strike and I'll be forced out of this body." } },
}

-- Pure helper so it can be tested: `roll` is a function(n) -> integer in [1, n]
function HealthThoughts.pick(tiers: { { Min: number, Lines: { string } } }, fraction: number, roll: (number) -> number): string?
	for _, tier in tiers do
		if fraction >= tier.Min then
			return tier.Lines[roll(#tier.Lines)]
		end
	end
	return nil
end

return HealthThoughts
