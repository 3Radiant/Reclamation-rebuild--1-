local Kar98k = {
	DisplayName = "Kar98k",

	BodyDamage = 42,
	HeadshotDamage = 87,
	LimbDamage = 17,

	Ammo = 5, -- magazine size
	RPM = 55, -- shots per minute -> fire interval = 60 / RPM

	BulletSpeed = 1600, -- studs per second

	AnimationGroup = "Rifle", -- "Rifle" "Pistol"
	Type = "Bolt", -- "SemiAuto" "Auto" "Bolt" (Auto = hold click to keep firing)

	Tracer = "Default",

	-- Sounds: paste asset ids ("rbxassetid://123456"). Blank = silent. Everyone nearby hears Fire
	-- (louder / further with FireVolume / FireDistance); Bolt plays after the shot as the bolt is
	-- worked; Reload plays when you start reloading.
	Sounds = {
		Fire = "rbxassetid://75930687498135",
		FireVolume = 1.5,
		FireDistance = 900,
		Bolt = "rbxassetid://131265718595511",
		BoltVolume = 0.8,
		Reload = "rbxassetid://119170082022465",
		ReloadVolume = 0.8,
	}, -- see BulletVisuals.TracerStyles

	Sling = { 
		Part = "Torso",
		Offset = Vector3.new(0.3, -0.5, 0.5),
		Rotation = Vector3.new(0, 0, 270) 
	},

	Recoil = 1.6, -- camera kick in degrees when you fire (0 = none)

	-- Added for the projectile + stance system
	ReloadTime = 3.5,
	FalloffDistance = 750, -- bullet flies dead straight this far, THEN drops
	GravityScale = 0.5, -- fraction of workspace gravity once it starts dropping
	MaxRange = 1600,
	MaxLifetime = 6,
	-- Camera while aiming. Delete a line (or set it to nil) for "no change".
	AimFov = 70, -- field of view while aiming (normal is 70, 80 sprinting)
	AimZoom = nil, -- camera distance while aiming (nil = keep your current zoom)
	AimShoulder = nil, -- Vector3 camera offset while aiming (nil = none, normal Roblox camera)

	AimWalkSpeed = 6, -- the only speed allowed while aiming
	AimTurnSpeed = 24, -- how snappily you turn toward the mouse
}

return Kar98k
