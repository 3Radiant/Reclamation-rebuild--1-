return {
	AllowSwitch = false, -- false = /morph is disabled

	Eldian = {
		Default = "Scout",
		List = {
			Scout = { Display = "Scouting Legion", Shirt = 138009799437918, Pants = 91334638494668, Accessories = {} },
			-- Engineer = { Display = "Engineer", Shirt = 123456, Pants = 654321, Accessories = { "ToolBelt" } },
			MilitaryPolice = {
				Display = "Military Police", Shirt = 113107758645670, Pants = 91334638494668, 
				Accessories = { 
					{},
				},
			},

			RoyalMilitary = { Display = "Military No Jacket", Shirt = 105538996922152, Pants = 91334638494668, Accessories = {} },
		},
	},

	Marleyan = {
		Default = "Infantry",
		List = {
			Infantry = {
				Display = "Infantry", Shirt = 6166116888, Pants = 6166038240, 
				Accessories = { 
					{ Name = "Infantry", Offset = Vector3.new(0, -0.2, -0.5), Rotation = Vector3.new(0, 0, 0) },
				},
			},

			-- Officer = { Display = "Officer", Shirt = 123456, Pants = 654321, Accessories = { "OfficerRig", "Watch" } }
			--[[Warrior = {
				Display = "Warrior", Shirt = 111, Pants = 222,
				Accessories = {
					"ArmoredVest", -- plain name: normal position
					{ Name = "ChestRig", Offset = Vector3.new(0, -0.15, 0), Rotation = Vector3.new(0, 0, 10) },
				},
			},]]
		},
	},
	
}