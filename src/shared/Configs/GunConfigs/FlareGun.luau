--[[
	Flare Gun - Eldian signal pistol (given to Eldians when they spawn: Config.TeamGuns).
	Fires a coloured flare along the same ballistic path as a bullet, but slower and shorter
	ranged: it flies fairly straight for FalloffDistance studs, then arcs down gently
	(GravityScale is low). Where it lands it keeps burning for Flare.BurnTime seconds.

	Pick the colour with V (cycles) or /flare <colour>.
	Replace the model by putting a Tool named "FlareGun" in assets/guns (Handle + "Muzzle" Attachment).
]]

return {
	DisplayName = "Flare Gun",

	BodyDamage = 8, -- a flare in the face hurts a little
	HeadshotDamage = 14,
	LimbDamage = 4,

	Ammo = 1,
	RPM = 40,
	ReloadTime = 2.6,

	BulletSpeed = 330, -- studs per second (rifle: 1100)
	FalloffDistance = 70, -- flies straight this far, then starts to arc
	GravityScale = 0.35, -- gentle arc (rifle: 0.5)
	MaxRange = 650, -- rifle: 1600
	MaxLifetime = 6,

	AnimationGroup = "Pistol",
	Type = "SemiAuto",
	Recoil = 0.8,
	Casing = false, -- no ejected brass
	Tracer = "Default",
	Sounds = { Fire = "", FireVolume = 1.2, FireDistance = 700, Reload = "", ReloadVolume = 0.8 }, -- asset ids, blank = silent

	AimFov = 62,
	AimWalkSpeed = 7,
	AimTurnSpeed = 18,

	-- Flare colours. Order is the order V cycles through.
	ColorOrder = { "Red", "Blue", "Purple", "Yellow", "Green", "Black", "White", "Orange" },
	DefaultColor = "Red",
	Colors = {
		Red = Color3.fromRGB(255, 50, 40),
		Blue = Color3.fromRGB(60, 110, 255),
		Purple = Color3.fromRGB(165, 70, 255),
		Yellow = Color3.fromRGB(255, 225, 60),
		Green = Color3.fromRGB(60, 235, 90),
		Black = Color3.fromRGB(22, 22, 24),
		White = Color3.fromRGB(245, 245, 250),
		Orange = Color3.fromRGB(255, 135, 30),
	},

	Flare = {
		BurnTime = 14, -- seconds it keeps burning where it lands
		LightRange = 46,
		LightBrightness = 3,
	},

	-- Used only when assets/guns has no "FlareGun" tool
	Placeholder = {
		Size = Vector3.new(0.35, 0.9, 1.3),
		Color = Color3.fromRGB(70, 74, 60),
		Material = Enum.Material.Metal,
	},
}
