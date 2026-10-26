local Shotgun = {
	DisplayName = "Trench Shotgun",

	-- Damage is PER PELLET. 8 pellets x 14 = 112 if every one hits at point-blank range.
	BodyDamage = 14,
	HeadshotDamage = 24,
	LimbDamage = 8,

	Pellets = 8,
	Spread = 5,
	SpreadCenterBias = 1,
	SpeedJitter = 0.06,
	AmmoPerShot = 1,
	DamageFalloff = { Start = 18, End = 60, MinScale = 0.15 },

	Ammo = 6,
	ReloadStyle = "Single",
	ReloadStartTime = 0.5,
	ReloadShellTime = 0.6,
	ReloadTime = 3.6, -- only used by normal-reload guns

	RPM = 70,
	Type = "Pump",

	BulletSpeed = 900,
	Tracer = "Default",

	Sounds = {
		Fire = "rbxassetid://132711300701696",
		FireVolume = 1.6,
		FireDistance = 900,
		Bolt = "rbxassetid://113837896417526", -- the pump, played 0.55 s after the shot
		BoltVolume = 0.8,
		Reload = "rbxassetid://139827026287805",
		ReloadVolume = 0.8,
	},

	Recoil = 3.2,

	FalloffDistance = 40,
	GravityScale = 0.8,
	MaxRange = 500,
	MaxLifetime = 1.5,

	AimFov = 70,
	AimWalkSpeed = 7,
	AimTurnSpeed = 16,

	AnimationGroup = "Rifle",

	Sling = { 
		Part = "Torso",
		Offset = Vector3.new(0.5, -0.5, 0.7),
		Rotation = Vector3.new(180, 0, 225) 
	},

	Placeholder = { Size = Vector3.new(0.35, 0.45, 3.2), Color = Color3.fromRGB(70, 55, 40), Material = Enum.Material.Wood },
}

return Shotgun