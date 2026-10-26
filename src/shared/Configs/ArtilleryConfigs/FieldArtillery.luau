--[[
	Field Artillery - a Marleyan-style barrage called in with a signal flare tool.
	Equip it, aim with the mouse, click: a flare marks the spot, then after `Delay`
	seconds a salvo of shells lands around it. The size of the pattern and of each blast
	is random every time (RadiusScale / BlastScale), and nothing is drawn on the ground.

	All numbers are gameplay placeholders. Distances in studs, times in seconds.
]]

return {
	DisplayName = "Artillery Signal",

	MinRange = 30, -- can't call it on top of yourself
	MaxRange = 500,
	Cooldown = 45,

	Delay = 4.5, -- from click to FIRST impact
	FallTime = 2.2, -- how long each shell whistles down before landing (must be < Delay)
	Shells = 6,
	ShellInterval = 0.5, -- gap between impacts
	SpreadRadius = 22, -- shells land randomly inside this circle
	BlastRadius = 14,
	-- Random size: multipliers applied each strike. RadiusScale resizes the whole pattern
	-- (SpreadRadius), BlastScale resizes every individual shell's blast.
	RadiusScale = { Min = 0.6, Max = 1.7 },
	BlastScale = { Min = 0.7, Max = 1.5 },

	DamageCenter = 150, -- humans at the centre of a blast
	DamageEdge = 40, -- humans at the edge
	TitanDamage = 450, -- per shell at the centre of the blast
	Knockback = 90,

	WarnExtraRadius = 30, -- players this close to the danger zone get a warning thought
	WarnThoughts = {
		"That's a signal flare... *artillery*. I need to get out of here!",
		"Shells are coming. **Move!**",
		"A barrage is about to land. Get clear!",
	},

	CallThoughts = {
		"Signal sent. Now we wait.",
		"The flare is up. They'll fire soon.",
	},
	CooldownThought = "The battery needs more time before it can fire again.",
	OutOfRangeThought = "That's out of the battery's range.",

	-- Anxiety: players in the danger zone get a rising dread while the shells are coming,
	-- and anyone near an impact gets slammed with it.
	Anxiety = {
		WarnLevel = 0.5, -- when the flare goes up (scaled down toward the edge of the danger zone)
		ImpactLevel = 1, -- right at an impact
		ImpactRadiusScale = 3.5, -- impacts affect players within BlastRadius * this
		ImpactDuration = 16,
	},

	-- Presentation. All client-side, so it costs the server nothing.
	Visual = {
		Scale = 1.8, -- explosion size relative to BlastRadius
		ShakeRange = 260, -- studs: camera shakes within this distance
		ShakeMax = 5, -- shake strength at the centre
		FlashRange = 3.5, -- white-out when closer than BlastRadius * this
		DeafenRange = 2.2, -- muffled hearing when closer than BlastRadius * this
		SpeedOfSound = 700, -- studs/s: far-away impacts are seen first, heard later
	},

	-- Sound slots ("rbxassetid://..."). These defaults are Roblox's built-in client sounds so
	-- it works out of the box; replace them with real artillery whistles / explosions.
	-- Blank = silent. The whistle loops while a shell falls, speeding up and getting louder.
	Sounds = {
		Whistle = "rbxasset://sounds/Rocket whoosh 01.wav",
		Explosion = "rbxasset://sounds/impact_explosion_03.mp3",
	},
}
