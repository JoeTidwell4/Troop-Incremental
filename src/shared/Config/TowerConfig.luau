--!strict
-- The Endless Tower (Phase 13f). Safe to tweak.
--
-- A ladder of one-off boss fights, open from best stage UNLOCK_STAGE. You fight the floor
-- above your best with your current army: a timer, no gold, no farming, and losing costs
-- nothing. Your best floor is kept forever (through Ascend and Legacy).
--
-- Floors have a FIXED strength (not scaled to the player): floor F is about as tough as
-- the boss of stage BASE_STAGE + STAGES_PER_FLOOR x F. So you climb when your run is
-- strong; right after an Ascend you can't.
--
-- Tower Laws make floors different from normal bosses. The laws of a floor are fixed by
-- its number (Formulas.towerFloor), so players can tell each other about a floor:
--   floors 1-2: none        every 5th floor: two laws + a Tower Chest
--   other floors: one       every 10th floor: a Guardian (all three boss moves, more HP)
-- No area traits in the Tower.
--
-- Law effects (all optional):
--   troopMultiplier / queuedMultiplier   scale troop damage / clicks + abilities + weak points
--   troopDamage { [troopId] = x }        that troop type's damage x this
--   regen          the boss heals this share of its max HP per second
--   bossDamage     it hits the army x this
--   timeScale      the timer x this
--   noClicks       your own clicks do nothing (weak points still work)
--   noAbilities    abilities can't be used
--   weakPointGap   time between weak points x this (below 1 = more often)
--
-- Rewards: every floor the first time = Relic Dust + a little Honor; every CHEST_EVERY-th
-- a Tower Chest (random prize, odds shown, never sold); every BONUS_EVERY-th +BONUS_PER_STEP
-- damage and gold forever; once a day the Tribute, bigger the higher your best floor.

local Types = require(script.Parent.Parent.Types)

local TowerConfig = {
	UNLOCK_STAGE = 75,

	BASE_STAGE = 58,
	STAGES_PER_FLOOR = 2,
	TIME_LIMIT = 30, -- seconds (+ boss timer bonuses, x a law's timeScale)
	INTRO_SECONDS = 1.5,
	-- A floor loses at most this share of its HP per second, so floors far below you fall
	-- in ~2 seconds (normal bosses: 12%, 8 seconds) and catching up doesn't take all day.
	MAX_DAMAGE_PER_SECOND_FRACTION = 0.5,
	NEXT_FLOOR_DELAY = 2.2, -- seconds between a win and the next floor (keeps climbing)

	FREE_FLOORS = 2, -- the first floors have no law
	DOUBLE_LAW_EVERY = 5,
	GUARDIAN_EVERY = 10,
	GUARDIAN_HP = 1.5,

	LAW_ORDER = { "Warded", "ThickHide", "AntiMagic", "PikeWall", "Stoneskin", "Regenerating", "Frenzied", "Hasty", "Silence", "Exposed" } :: { string },
	LAWS = {
		Warded = { id = "Warded", name = "Warded", text = "Your clicks do nothing", effects = { noClicks = true } },
		ThickHide = { id = "ThickHide", name = "Thick Hide", text = "Troops deal half, clicks and abilities double", effects = { troopMultiplier = 0.5, queuedMultiplier = 2 } },
		AntiMagic = { id = "AntiMagic", name = "Anti-magic", text = "Mages deal no damage", effects = { troopDamage = { Mage = 0 } } },
		PikeWall = { id = "PikeWall", name = "Pike Wall", text = "Cavalry deal no damage", effects = { troopDamage = { Cavalry = 0 } } },
		Stoneskin = { id = "Stoneskin", name = "Stoneskin", text = "Siege deals no damage", effects = { troopDamage = { Siege = 0 } } },
		Regenerating = { id = "Regenerating", name = "Regenerating", text = "Heals 2% of its HP every second", effects = { regen = 0.02 } },
		Frenzied = { id = "Frenzied", name = "Frenzied", text = "Hits your army twice as hard", effects = { bossDamage = 2 } },
		Hasty = { id = "Hasty", name = "Hasty", text = "The timer is 40% shorter", effects = { timeScale = 0.6 } },
		Silence = { id = "Silence", name = "Silence", text = "Abilities can't be used", effects = { noAbilities = true } },
		Exposed = { id = "Exposed", name = "Exposed", text = "Weak points appear twice as often", effects = { weakPointGap = 0.5 } },
	} :: { [string]: Types.TowerLawDef },

	-- Guardian models take turns (the biome bosses), in the Tower's own colors.
	MODELS = { "HollowKing", "MagmaTitan", "FrostWyrm", "Treant", "PrismQueen", "Sandworm", "JadeIdol", "BogHag", "Kraken", "Griffin" } :: { string },
	COLOR = Color3.fromRGB(150, 110, 220),
	GUARDIAN_COLOR = Color3.fromRGB(235, 190, 80),

	-- Every floor, first clear.
	FLOOR_DUST_BASE = 5,
	FLOOR_DUST_PER_FLOOR = 0.5,
	FLOOR_HONOR_SHARE = 0.01, -- of an Ascend's Honor at your best stage
	FLOOR_HONOR_MIN = 2,

	-- Tower Chest: one random prize. Weights are shown in the UI as percentages.
	CHEST_EVERY = 5,
	CHEST_PRIZES = {
		{ id = "Relic", weight = 35, text = "A relic, Epic or better" },
		{ id = "Scrolls", weight = 25, text = "3 Recruit Scrolls", scrolls = 3 },
		{ id = "Dust", weight = 25, text = "A pile of Relic Dust" }, -- CHEST_DUST_BASE + CHEST_DUST_PER_FLOOR x floor
		{ id = "HeroChest", weight = 12, text = "A Hero Chest", heroChests = 1 },
		{ id = "Jackpot", weight = 3, text = "JACKPOT: a Legendary or better relic + 5 Recruit Scrolls", scrolls = 5 },
	} :: { Types.TowerPrizeDef },
	CHEST_DUST_BASE = 100,
	CHEST_DUST_PER_FLOOR = 4,

	-- Permanent: +BONUS_PER_STEP damage and gold for every BONUS_EVERY floors of your best.
	BONUS_EVERY = 10,
	BONUS_PER_STEP = 0.02,

	-- Daily Tribute (once per DailyConfig day, needs at least floor 1).
	TRIBUTE_GOLD_MINUTES_BASE = 15,
	TRIBUTE_GOLD_MINUTES_PER_FLOOR = 1,
	TRIBUTE_GOLD_MINUTES_MAX = 180,
	TRIBUTE_DUST_BASE = 10,
	TRIBUTE_DUST_PER_FLOOR = 1,

	REQUESTS_PER_SECOND = 1,
	REQUESTS_BURST = 4,
}

return table.freeze(TowerConfig)
