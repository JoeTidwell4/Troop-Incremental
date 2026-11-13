--!strict
-- Honor shop: permanent upgrades bought with Honor. They survive Ascending. Safe to tweak.
--
-- Cost of the next level = baseCost * costGrowth ^ (current level), rounded.
-- Effects per level (an upgrade can have any of these):
--   damageMultiplier / goldMultiplier / armyHpMultiplier / tapMultiplier
--       -> multiplied together per level, e.g. 1.25 at level 3 = x1.95
--   startGoldMultiplier -> gold you start each new run with = STARTING_GOLD * this ^ level
--   offlineHoursPerLevel / offlineEfficiencyPerLevel -> added to the offline cap / efficiency

local Types = require(script.Parent.Parent.Types)

local HonorConfig = {
	ORDER = { "Drills", "WarChest", "Fortitude", "Might", "HeadStart", "Rations" } :: { string },

	UPGRADES = {
		Drills = {
			id = "Drills",
			displayName = "Battle Drills",
			description = "x1.25 army damage per level",
			baseCost = 3,
			costGrowth = 1.5,
			damageMultiplier = 1.25,
		},
		WarChest = {
			id = "WarChest",
			displayName = "War Chest",
			description = "x1.2 gold per level",
			baseCost = 3,
			costGrowth = 1.5,
			goldMultiplier = 1.2,
		},
		Fortitude = {
			id = "Fortitude",
			displayName = "Fortitude",
			description = "x1.25 army HP per level",
			baseCost = 3,
			costGrowth = 1.5,
			armyHpMultiplier = 1.25,
		},
		Might = {
			id = "Might",
			displayName = "Commander's Might",
			description = "x1.5 click damage per level",
			baseCost = 2,
			costGrowth = 1.5,
			tapMultiplier = 1.5,
		},
		HeadStart = {
			id = "HeadStart",
			displayName = "Head Start",
			description = "x8 starting gold per level",
			baseCost = 5,
			costGrowth = 1.8,
			startGoldMultiplier = 8,
		},
		Rations = {
			id = "Rations",
			displayName = "Field Rations",
			description = "+1h offline cap, +5% offline gold",
			baseCost = 4,
			costGrowth = 1.6,
			maxLevel = 16,
			offlineHoursPerLevel = 1,
			offlineEfficiencyPerLevel = 0.05,
		},
	} :: { [string]: Types.HonorUpgradeDef },

	REQUESTS_PER_SECOND = 8,
	REQUESTS_BURST = 12,
}

return table.freeze(HonorConfig)
