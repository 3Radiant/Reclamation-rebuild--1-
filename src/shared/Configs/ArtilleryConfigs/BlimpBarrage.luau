--[[
	Blimp Barrage - what Marleyan airships drop on the battlefield (BlimpService).
	Same fields as FieldArtillery, but nobody calls it: no flare, no range or cooldown, and
	the shells start at the blimp. Shells here is only a default; Config.Blimps.Shells
	picks a random count per volley.
]]

return {
	DisplayName = "Blimp Barrage",
	Flare = false,

	Delay = 2.6, -- from firing to the FIRST impact
	FallTime = 2.2,
	Shells = 3,
	ShellInterval = 0.45,
	SpreadRadius = 34,
	BlastRadius = 15,
	RadiusScale = { Min = 0.6, Max = 1.7 },
	BlastScale = { Min = 0.7, Max = 1.5 },

	DamageCenter = 150,
	DamageEdge = 40,
	TitanDamage = 450,
	Knockback = 90,

	WarnExtraRadius = 30,
	WarnThoughts = {
		"Those airships... they're shelling us. **Run!**",
		"Something is whistling down from the sky. *Move!*",
		"Marley's blimps are firing again. Get clear!",
	},

	Anxiety = {
		WarnLevel = 0.5,
		ImpactLevel = 1,
		ImpactRadiusScale = 3.5,
		ImpactDuration = 16,
	},

	Visual = {
		Scale = 1.8,
		ShakeRange = 260,
		ShakeMax = 5,
		FlashRange = 3.5,
		DeafenRange = 2.2,
		SpeedOfSound = 700,
	},

	Sounds = {
		Whistle = "rbxasset://sounds/Rocket whoosh 01.wav",
		Explosion = "rbxasset://sounds/impact_explosion_03.mp3",
	},
}
