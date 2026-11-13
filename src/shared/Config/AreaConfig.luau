--!strict
-- Areas: every boss you beat moves you into the next area. Looks only, no gameplay effect.
-- Area N covers stages (N-1)*10+1 to N*10 (the boss is the last stage of each area).
-- After the last theme, they repeat with "II", "III", ... added to the name.

local Types = require(script.Parent.Parent.Types)

local AreaConfig = {
	THEMES = {
		{
			name = "Whispering Forest",
			bossName = "Old Grimbark",
			groundColor = Color3.fromRGB(96, 140, 80),
			groundMaterial = Enum.Material.Grass,
			enemyColor = Color3.fromRGB(150, 110, 70),
			bossColor = Color3.fromRGB(90, 60, 40),
			enemyShape = Enum.PartType.Block,
			clockTime = 14,
			tint = Color3.fromRGB(255, 255, 255),
		},
		{
			name = "Sunscorch Dunes",
			bossName = "The Sand Tyrant",
			groundColor = Color3.fromRGB(215, 185, 120),
			groundMaterial = Enum.Material.Sand,
			enemyColor = Color3.fromRGB(200, 120, 60),
			bossColor = Color3.fromRGB(170, 70, 30),
			enemyShape = Enum.PartType.Cylinder,
			clockTime = 12,
			tint = Color3.fromRGB(255, 240, 215),
		},
		{
			name = "Frozen Pass",
			bossName = "Frost Wyrm",
			groundColor = Color3.fromRGB(225, 235, 245),
			groundMaterial = Enum.Material.Snow,
			enemyColor = Color3.fromRGB(120, 180, 230),
			bossColor = Color3.fromRGB(60, 120, 200),
			enemyShape = Enum.PartType.Ball,
			clockTime = 9,
			tint = Color3.fromRGB(220, 235, 255),
		},
		{
			name = "Mirefen Swamp",
			bossName = "The Bog Hag",
			groundColor = Color3.fromRGB(80, 95, 60),
			groundMaterial = Enum.Material.Mud,
			enemyColor = Color3.fromRGB(110, 150, 70),
			bossColor = Color3.fromRGB(70, 110, 50),
			enemyShape = Enum.PartType.Block,
			clockTime = 17,
			tint = Color3.fromRGB(225, 245, 215),
		},
		{
			name = "Ember Peaks",
			bossName = "Magma Colossus",
			groundColor = Color3.fromRGB(70, 50, 45),
			groundMaterial = Enum.Material.Basalt,
			enemyColor = Color3.fromRGB(230, 100, 40),
			bossColor = Color3.fromRGB(200, 50, 20),
			enemyShape = Enum.PartType.Cylinder,
			clockTime = 18.5,
			tint = Color3.fromRGB(255, 220, 200),
		},
		{
			name = "Shadow Keep",
			bossName = "The Hollow King",
			groundColor = Color3.fromRGB(55, 55, 70),
			groundMaterial = Enum.Material.Slate,
			enemyColor = Color3.fromRGB(130, 90, 170),
			bossColor = Color3.fromRGB(90, 40, 140),
			enemyShape = Enum.PartType.Ball,
			clockTime = 0,
			tint = Color3.fromRGB(215, 205, 255),
		},
	} :: { Types.AreaTheme },
}

return table.freeze(AreaConfig)
