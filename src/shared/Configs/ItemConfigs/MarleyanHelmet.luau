return {
	DisplayName = "Marleyan Helmet",

	EquipAnimation = "", -- "rbxassetid://..." (R6 animation). Blank = no animation, just the delay
	EquipTime = 0.9,     -- seconds between clicking and the helmet being on your head

    TakeOffAnimation = "", -- animation when you take it off (blank = none)
	TakeOffTime = 0.6,

	-- Hangs here while in your inventory (same system as the guns)
	Sling = { Part = "Torso", Offset = Vector3.new(-0.85, -0.9, 0.3), Rotation = Vector3.new(80, 20, 0) },

	-- Sits here while worn
	Worn = { Part = "Head", Offset = Vector3.new(0, 0, 0), Rotation = Vector3.new(0, 0, 0) },

	KnockSpeed = 24,    -- how hard it flies off on a headshot
	DropLifetime = 90,  -- seconds a dropped helmet stays on the ground
	PickupDistance = 8,
	PickupHold = 0.4,

	-- Used when there is no custom Tool in assets/tools
	Placeholder = { Size = Vector3.new(1.4, 1.4, 1.4), Color = Color3.fromRGB(70, 78, 66), Material = Enum.Material.Metal },
}