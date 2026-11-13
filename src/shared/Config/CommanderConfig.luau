--!strict
-- Commander gear: things your avatar wears, each giving a small bonus while equipped.
-- One item per slot. Each slot boosts its own stat:
--   Helmet -> army HP    Cape -> gold    Weapon -> click damage    Back -> army damage
-- RULE (owner-approved): gear with stats is EARNED only (stages, Ascends, the login
-- streak, Clan War, the clan shop). Anything sold for Robux is looks-only (no stat), so
-- the game never becomes pay-to-win. Safe to tweak numbers and add items.
--
-- unlock.kind:
--   "default"     everyone has it
--   "stage"       reach all-time best stage `value`
--   "ascensions"  Ascend `value` times
--   "loginStreak" reach a `value`-day login streak
--   "clanWar"     your clan finishes the weekly Clan War in the top `value` (granted by ClanWarService)
--   "pass"        own the Robux pass `pass` (cosmetic items only)
--   "clanShop"    bought in the clan shop (Phase 11d)

local Types = require(script.Parent.Parent.Types)

local CommanderConfig = {
	SLOTS = { "Helmet", "Cape", "Weapon", "Back" } :: { string },
	SLOT_STATS = {
		Helmet = "armyHp",
		Cape = "gold",
		Weapon = "tap",
		Back = "damage",
	} :: { [string]: string },
	STAT_NAMES = {
		armyHp = "army HP",
		gold = "gold",
		tap = "click damage",
		damage = "army damage",
	} :: { [string]: string },

	-- Display order inside each slot.
	ORDER = {
		"LeatherCap",
		"IronHelm",
		"HornedHelm",
		"DawnCrown",
		"TravelersCloak",
		"CrimsonCape",
		"RoyalMantle",
		"PhoenixCape",
		"IronSword",
		"SteelBlade",
		"Frostbrand",
		"SunfireBlade",
		"GoldenSword",
		"Quiver",
		"TowerShield",
		"WarBanner",
		"SeraphWings",
	} :: { string },

	ITEMS = {
		-- Helmets: army HP
		LeatherCap = { id = "LeatherCap", slot = "Helmet", displayName = "Leather Cap", rarity = 1, multiplier = 1.05, style = "Cap", color = Color3.fromRGB(130, 90, 55), unlock = { kind = "stage", value = 10 } },
		IronHelm = { id = "IronHelm", slot = "Helmet", displayName = "Iron Helm", rarity = 3, multiplier = 1.1, style = "Helm", color = Color3.fromRGB(170, 175, 185), unlock = { kind = "stage", value = 50 } },
		HornedHelm = { id = "HornedHelm", slot = "Helmet", displayName = "Horned Helm", rarity = 4, multiplier = 1.2, style = "Horned", color = Color3.fromRGB(120, 110, 100), unlock = { kind = "stage", value = 100 } },
		DawnCrown = { id = "DawnCrown", slot = "Helmet", displayName = "Dawn Crown", rarity = 5, multiplier = 1.35, style = "Crown", color = Color3.fromRGB(255, 205, 70), unlock = { kind = "stage", value = 200 } },
		-- Capes: gold
		TravelersCloak = { id = "TravelersCloak", slot = "Cape", displayName = "Traveler's Cloak", rarity = 1, multiplier = 1.05, style = "Cloak", color = Color3.fromRGB(90, 110, 80), unlock = { kind = "loginStreak", value = 7 } },
		CrimsonCape = { id = "CrimsonCape", slot = "Cape", displayName = "Crimson Cape", rarity = 3, multiplier = 1.1, style = "Cape", color = Color3.fromRGB(170, 35, 40), unlock = { kind = "ascensions", value = 1 } },
		RoyalMantle = { id = "RoyalMantle", slot = "Cape", displayName = "Royal Mantle", rarity = 4, multiplier = 1.2, style = "Mantle", color = Color3.fromRGB(100, 50, 160), unlock = { kind = "ascensions", value = 10 } },
		PhoenixCape = { id = "PhoenixCape", slot = "Cape", displayName = "Phoenix Cape", rarity = 5, multiplier = 1.35, style = "Phoenix", color = Color3.fromRGB(255, 120, 40), unlock = { kind = "stage", value = 150 } },
		-- Weapons: click damage (they restyle the commander's sword)
		IronSword = { id = "IronSword", slot = "Weapon", displayName = "Iron Sword", rarity = 1, multiplier = 1.05, style = "Blade", color = Color3.fromRGB(200, 205, 215), unlock = { kind = "default" } },
		SteelBlade = { id = "SteelBlade", slot = "Weapon", displayName = "Steel Blade", rarity = 3, multiplier = 1.15, style = "Blade", color = Color3.fromRGB(150, 190, 230), unlock = { kind = "stage", value = 25 } },
		Frostbrand = { id = "Frostbrand", slot = "Weapon", displayName = "Frostbrand", rarity = 4, multiplier = 1.3, style = "Glow", color = Color3.fromRGB(130, 220, 255), unlock = { kind = "stage", value = 31 } },
		SunfireBlade = { id = "SunfireBlade", slot = "Weapon", displayName = "Sunfire Blade", rarity = 5, multiplier = 1.5, style = "Glow", color = Color3.fromRGB(255, 150, 40), unlock = { kind = "stage", value = 120 } },
		GoldenSword = { id = "GoldenSword", slot = "Weapon", displayName = "Golden Sword", rarity = 5, style = "Glow", color = Color3.fromRGB(255, 200, 60), unlock = { kind = "pass", pass = "GoldenSword" } }, -- Robux: looks only
		-- Back: army damage
		Quiver = { id = "Quiver", slot = "Back", displayName = "Quiver", rarity = 1, multiplier = 1.05, style = "Quiver", color = Color3.fromRGB(120, 80, 50), unlock = { kind = "stage", value = 15 } },
		TowerShield = { id = "TowerShield", slot = "Back", displayName = "Tower Shield", rarity = 3, multiplier = 1.1, style = "Shield", color = Color3.fromRGB(90, 110, 170), unlock = { kind = "stage", value = 75 } },
		WarBanner = { id = "WarBanner", slot = "Back", displayName = "War Banner", rarity = 4, multiplier = 1.2, style = "Banner", color = Color3.fromRGB(200, 60, 50), unlock = { kind = "clanWar", value = 10 } },
		SeraphWings = { id = "SeraphWings", slot = "Back", displayName = "Seraph Wings", rarity = 5, multiplier = 1.35, style = "Wings", color = Color3.fromRGB(255, 245, 210), unlock = { kind = "clanWar", value = 1 } },
	} :: { [string]: Types.CommanderItemDef },

	EQUIP_REQUESTS_BURST = 6,
	EQUIP_REQUESTS_PER_SECOND = 3,
}

return table.freeze(CommanderConfig)
