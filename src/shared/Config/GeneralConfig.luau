--!strict
-- Generals (Phase 13c). Safe to tweak.
--
-- Recruited with Recruit Scrolls (EARN-ONLY, never Robux: random characters for Robux
-- would be paid random items). Odds and pity are shown in the UI. Field FIELD_SLOTS at a
-- time; only fielded Generals give their bonuses. The roster, stars and levels are kept
-- forever (Ascend and Legacy too).
--
-- Each General has:
--   passive  one stat (damage / armyHp / gold / tap): +passive.value, scaled by power
--   trait    a fixed effect: troopDamage / troopHp (one troop type, x(1 + value * power)),
--            or one of critChance, bossTime, goldenChance, bossDamageTaken (scaled too)
-- power = (1 + LEVEL_STEP * (level - 1)) * (1 + STAR_STEP * (stars - 1)) for passives;
-- traits use only the star part (levels make the passive grow, stars make both grow).
--
-- Stars come from duplicates: STAR_COPIES[n] more copies to go from n to n+1 stars.
-- Max level = stars * LEVELS_PER_STAR. Copies past max stars turn into Scroll shards
-- (SHARDS_PER_EXTRA; SHARDS_PER_SCROLL shards = 1 Recruit Scroll).

local Types = require(script.Parent.Parent.Types)

local GeneralConfig = {
	FIELD_SLOTS = 3,
	MAX_STARS = 5,
	STAR_COPIES = { 1, 2, 3, 5 } :: { number }, -- 1->2, 2->3, 3->4, 4->5 stars
	LEVELS_PER_STAR = 10,
	LEVEL_STEP = 0.05,
	STAR_STEP = 0.25,
	SHARDS_PER_EXTRA = 2,
	SHARDS_PER_SCROLL = 5,

	-- Gold to level up: LEVEL_COST_KILLS kills' worth of gold at your ALL-TIME best stage
	-- (Generals are kept forever, like wardrobe gear) x LEVEL_COST_GROWTH^(level - 1)
	-- x the rarity's costMultiplier.
	LEVEL_COST_KILLS = 30,
	LEVEL_COST_GROWTH = 1.12,

	RARITIES = {
		Rare = { name = "Rare", color = Color3.fromRGB(70, 140, 255), odds = 62, costMultiplier = 1, order = 1 },
		Epic = { name = "Epic", color = Color3.fromRGB(180, 90, 240), odds = 28, costMultiplier = 1.5, order = 2 },
		Legendary = { name = "Legendary", color = Color3.fromRGB(255, 170, 40), odds = 9, costMultiplier = 2.5, order = 3 },
		Mythic = { name = "Mythic", color = Color3.fromRGB(255, 70, 110), odds = 1, costMultiplier = 4, order = 4 },
	} :: { [string]: { name: string, color: Color3, odds: number, costMultiplier: number, order: number } },
	RARITY_ORDER = { "Rare", "Epic", "Legendary", "Mythic" } :: { string },

	-- Bad-luck protection: a Legendary or better every PITY_LEGENDARY recruits without one,
	-- and a Mythic every PITY_MYTHIC without one.
	PITY_LEGENDARY = 25,
	PITY_MYTHIC = 120,

	-- Where Recruit Scrolls come from (GeneralService):
	SCROLLS = {
		PER_ASCEND_STAGES = 40, -- 1 scroll per this many stages of the run you Ascend from
		ACHIEVEMENT = 1, -- each achievement claimed
		-- (also: 1 from the daily "finish all quests" bonus and 3 on login day 7, set in DailyConfig)
		GOLDEN_CHANCE = 0.05, -- chance a golden enemy also drops one
		LEGACY = 10,
		FIRST_SCROLLS = 3, -- given once, the first time Generals unlock
	},
	UNLOCK_STAGE = 20, -- best stage to see the Generals tab

	ORDER = {
		"Aldric", "Lyra", "Brannoc", "Pip",
		"Morwen", "Garrick", "Thessa", "Rook",
		"Isolde", "Varkas", "Seren",
		"Marshal",
	} :: { string },

	GENERALS = {
		-- Rare
		Aldric = { id = "Aldric", name = "Sir Aldric", title = "the Steadfast", rarity = "Rare", passive = { stat = "damage", value = 0.05 }, trait = { kind = "troopDamage", troopId = "Swordsman", value = 0.5, text = "Swordsmen +{v}% damage" } },
		Lyra = { id = "Lyra", name = "Lyra Swiftbow", title = "Ranger Captain", rarity = "Rare", passive = { stat = "gold", value = 0.05 }, trait = { kind = "troopDamage", troopId = "Archer", value = 0.5, text = "Archers +{v}% damage" } },
		Brannoc = { id = "Brannoc", name = "Brannoc Ironhide", title = "Shield of the Realm", rarity = "Rare", passive = { stat = "armyHp", value = 0.06 }, trait = { kind = "troopHp", troopId = "Knight", value = 0.6, text = "Knights +{v}% HP" } },
		Pip = { id = "Pip", name = "Pip", title = "the Quartermaster", rarity = "Rare", passive = { stat = "gold", value = 0.06 }, trait = { kind = "goldenChance", value = 0.15, text = "+{v}% golden enemy chance" } },
		-- Epic
		Morwen = { id = "Morwen", name = "Morwen", title = "the Arcane", rarity = "Epic", passive = { stat = "damage", value = 0.08 }, trait = { kind = "troopDamage", troopId = "Mage", value = 0.6, text = "Mages +{v}% damage" } },
		Garrick = { id = "Garrick", name = "Garrick Stormrider", title = "Lord of Horses", rarity = "Epic", passive = { stat = "damage", value = 0.08 }, trait = { kind = "troopDamage", troopId = "Cavalry", value = 0.6, text = "Cavalry +{v}% damage" } },
		Thessa = { id = "Thessa", name = "Thessa", title = "Bladedancer", rarity = "Epic", passive = { stat = "tap", value = 0.12 }, trait = { kind = "critChance", value = 0.03, text = "+{v}% crit chance" } },
		Rook = { id = "Rook", name = "Old Rook", title = "the Engineer", rarity = "Epic", passive = { stat = "damage", value = 0.08 }, trait = { kind = "troopDamage", troopId = "Siege", value = 0.6, text = "Siege +{v}% damage" } },
		-- Legendary
		Isolde = { id = "Isolde", name = "Queen Isolde", title = "the Unbroken", rarity = "Legendary", passive = { stat = "armyHp", value = 0.12 }, trait = { kind = "bossDamageTaken", value = -0.1, text = "Bosses deal {v}% less damage" } },
		Varkas = { id = "Varkas", name = "Varkas", title = "the Conqueror", rarity = "Legendary", passive = { stat = "damage", value = 0.12 }, trait = { kind = "bossTime", value = 3, text = "+{v}s on every boss timer" } },
		Seren = { id = "Seren", name = "Seren Goldhand", title = "Merchant Princess", rarity = "Legendary", passive = { stat = "gold", value = 0.12 }, trait = { kind = "goldenChance", value = 0.4, text = "+{v}% golden enemy chance" } },
		-- Mythic
		Marshal = { id = "Marshal", name = "The Eternal Marshal", title = "Who Commands Kings", rarity = "Mythic", passive = { stat = "damage", value = 0.18 }, trait = { kind = "allTroopDamage", value = 0.25, text = "Every troop +{v}% damage" } },
	} :: { [string]: Types.GeneralDef },

	REQUESTS_PER_SECOND = 4,
	REQUESTS_BURST = 8,
	MAX_RECRUIT_AT_ONCE = 10,
}

return table.freeze(GeneralConfig)
