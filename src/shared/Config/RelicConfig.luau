--!strict
-- Relics (Phase 13d). Safe to tweak.
--
-- Bosses drop relics (from UNLOCK_STAGE): DROP_CHANCE per boss win (raid attacks too).
-- Each relic has a slot (one equipped per slot), a set, a rarity, a level and 1-4 rolled
-- stat lines. Equipped relics' lines add up (Formulas.relicBonuses); sets give bonuses
-- at 2 / 4 / 6 equipped pieces. Relic Dust (from salvaging) levels relics up and rerolls
-- a line. Relics are kept on Ascend; on Legacy they're turned into Dust (dust is kept).
-- Rolled on the server; odds and pity are shown in the UI. Never sold for Robux.

local Types = require(script.Parent.Parent.Types)

local RelicConfig = {
	UNLOCK_STAGE = 30,
	DROP_CHANCE = 0.35, -- per boss win
	RAID_DROP_CHANCE = 0.5, -- per raid attack
	MAX_ITEMS = 60, -- inventory; drops past this are salvaged straight into Dust
	MAX_LEVEL = 10,
	LEVEL_STEP = 0.1, -- +10% to every line per level

	SLOTS = { "Amulet", "Ring", "Charm", "Totem", "Sigil", "Crest" } :: { string },

	RARITY_ORDER = { "Common", "Rare", "Epic", "Legendary", "Mythic" } :: { string },
	RARITIES = {
		-- lines = stat lines rolled; range = scale on the stat's base value (min, max);
		-- dust = Dust from salvaging it (plus DUST_PER_LEVEL for each level it had).
		Common = { name = "Common", color = Color3.fromRGB(190, 190, 195), odds = 55, lines = 1, range = { 0.6, 1 }, dust = 5, order = 1 },
		Rare = { name = "Rare", color = Color3.fromRGB(70, 140, 255), odds = 28, lines = 2, range = { 0.8, 1.2 }, dust = 15, order = 2 },
		Epic = { name = "Epic", color = Color3.fromRGB(180, 90, 240), odds = 12, lines = 3, range = { 1, 1.5 }, dust = 40, order = 3 },
		Legendary = { name = "Legendary", color = Color3.fromRGB(255, 170, 40), odds = 4.5, lines = 4, range = { 1.3, 1.9 }, dust = 120, order = 4 },
		Mythic = { name = "Mythic", color = Color3.fromRGB(255, 70, 110), odds = 0.5, lines = 4, range = { 1.9, 2.6 }, dust = 400, order = 5 },
	} :: { [string]: { name: string, color: Color3, odds: number, lines: number, range: { number }, dust: number, order: number } },
	PITY_LEGENDARY = 20, -- a Legendary or better within this many drops
	PITY_MYTHIC = 100,
	DUST_PER_LEVEL = 8,

	-- Dust to go from level L to L+1 = UPGRADE_BASE x UPGRADE_GROWTH^L x the rarity's order.
	UPGRADE_BASE = 10,
	UPGRADE_GROWTH = 1.35,
	-- Dust to reroll one line = REROLL_BASE x the rarity's order.
	REROLL_BASE = 20,

	-- Stat lines a relic can roll. `value` = base amount (x the rarity range x level).
	-- Trimmed ~20-25% after the sim check: mid-game relics were adding ~+20 stages at 6 h.
	-- percent stats add to that multiplier (0.05 = +5%); critChance adds to the chance;
	-- bossTime adds seconds.
	STATS = {
		damage = { name = "army damage", value = 0.04, percent = true },
		armyHp = { name = "army HP", value = 0.05, percent = true },
		gold = { name = "gold", value = 0.04, percent = true },
		tap = { name = "click damage", value = 0.06, percent = true },
		critChance = { name = "crit chance", value = 0.01, percent = true },
		bossDamageDealt = { name = "damage to bosses", value = 0.05, percent = true },
		bossTime = { name = "boss timer", value = 0.6, percent = false },
	} :: { [string]: { name: string, value: number, percent: boolean } },
	STAT_ORDER = { "damage", "armyHp", "gold", "tap", "critChance", "bossDamageDealt", "bossTime" } :: { string },

	-- Sets: bonuses at 2, 4 and 6 equipped pieces (they stack: 6 pieces = all three).
	-- Effect fields like General sets: damage / armyHp / gold / tap (+), bossDamage
	-- (multiplier delta), bossDamageDealt (+), critChance / critMultiplier / bossTime /
	-- goldenChance (added).
	SET_ORDER = { "Inferno", "Glacier", "Tidecaller", "Tempest" } :: { string },
	SETS = {
		Inferno = {
			id = "Inferno",
			name = "Inferno",
			color = Color3.fromRGB(240, 90, 50),
			bonuses = {
				[2] = { text = "+15% army damage", effects = { damage = 0.15 } },
				[4] = { text = "+30% damage to bosses", effects = { bossDamageDealt = 0.3 } },
				[6] = { text = "+50% army damage", effects = { damage = 0.5 } },
			},
		},
		Glacier = {
			id = "Glacier",
			name = "Glacier",
			color = Color3.fromRGB(120, 200, 255),
			bonuses = {
				[2] = { text = "+15% army HP", effects = { armyHp = 0.15 } },
				[4] = { text = "+4s on boss timers", effects = { bossTime = 4 } },
				[6] = { text = "Bosses deal 30% less damage", effects = { bossDamage = -0.3 } },
			},
		},
		Tidecaller = {
			id = "Tidecaller",
			name = "Tidecaller",
			color = Color3.fromRGB(60, 190, 170),
			bonuses = {
				[2] = { text = "+15% gold", effects = { gold = 0.15 } },
				[4] = { text = "Golden enemies 50% more likely", effects = { goldenChance = 0.5 } },
				[6] = { text = "+50% gold", effects = { gold = 0.5 } },
			},
		},
		Tempest = {
			id = "Tempest",
			name = "Tempest",
			color = Color3.fromRGB(240, 220, 80),
			bonuses = {
				[2] = { text = "+20% click damage", effects = { tap = 0.2 } },
				[4] = { text = "+5% crit chance", effects = { critChance = 0.05 } },
				[6] = { text = "Crits hit x2 harder", effects = { critMultiplier = 2 } },
			},
		},
	} :: { [string]: Types.RelicSetDef },

	REQUESTS_PER_SECOND = 6,
	REQUESTS_BURST = 10,
}

return table.freeze(RelicConfig)
