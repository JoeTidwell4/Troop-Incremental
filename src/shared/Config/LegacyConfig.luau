--!strict
-- Legacy: the second prestige (Phase 12b). A much bigger reset than Ascend, for Crowns
-- that buy permanent upgrades. Tuned with `python tools/balance_v2.py legacy`: an active
-- player's first Legacy is around stage 200 (~27 Crowns); they get back past their old
-- best in about 1h45m and then reach 40-50 stages further each Legacy.
--
-- Resets: everything Ascend resets, plus Honor, Honor upgrades and ability upgrades.
-- Kept: Crowns + Crown upgrades, wardrobe gear, clan, faction, achievements, login
-- streak, Clan Tokens, passes + purchases, troop / ability unlocks (all-time best
-- stage), unopened packs and chests.

local Types = require(script.Parent.Parent.Types)

local LegacyConfig = {
	-- Best stage reached during THIS Legacy needed to Legacy again. Was 150; raised to
	-- 200 in the balance pass after Phase 13 (tools/balance_v3.py: players now reach 150
	-- in ~1.5 h and stall around 250-290, and Legacy should unlock near the stall).
	MIN_STAGE = 200,

	-- Crowns = floor(CROWN_SCALE * (Honor earned this Legacy / CROWN_HONOR_UNIT) ^ CROWN_EXPONENT)
	CROWN_SCALE = 3,
	CROWN_HONOR_UNIT = 100000,
	CROWN_EXPONENT = 0.5,

	ORDER = { "Armory", "Guard", "Treasury", "Glory" } :: { string },
	UPGRADES = {
		Armory = {
			id = "Armory",
			displayName = "Royal Armory",
			description = "x1.6 army damage per level",
			baseCost = 1,
			costGrowth = 1.6,
			stat = "damage",
			multiplier = 1.6,
		},
		Guard = {
			id = "Guard",
			displayName = "Royal Guard",
			description = "x1.6 army HP per level",
			baseCost = 1,
			costGrowth = 1.6,
			stat = "armyHp",
			multiplier = 1.6,
		},
		Treasury = {
			id = "Treasury",
			displayName = "Royal Treasury",
			description = "x1.6 gold per level",
			baseCost = 1,
			costGrowth = 1.6,
			stat = "gold",
			multiplier = 1.6,
		},
		Glory = {
			id = "Glory",
			displayName = "Eternal Glory",
			description = "x1.25 Honor from Ascending per level",
			baseCost = 2,
			costGrowth = 1.7,
			stat = "ascendHonor",
			multiplier = 1.25,
		},
	} :: { [string]: Types.CrownUpgradeDef },

	-- Your commander's aura by how many Legacies you've done (highest reached wins).
	RANKS = {
		{ count = 1, name = "Bronze Legacy", color = Color3.fromRGB(205, 127, 50) },
		{ count = 3, name = "Silver Legacy", color = Color3.fromRGB(200, 210, 225) },
		{ count = 5, name = "Golden Legacy", color = Color3.fromRGB(255, 200, 60) },
		{ count = 10, name = "Royal Legacy", color = Color3.fromRGB(170, 90, 255) },
		{ count = 20, name = "Eternal Legacy", color = Color3.fromRGB(90, 230, 255) },
	} :: { { count: number, name: string, color: Color3 } },

	REQUESTS_PER_SECOND = 4,
	REQUESTS_BURST = 6,
}

return table.freeze(LegacyConfig)
