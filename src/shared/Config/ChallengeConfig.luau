--!strict
-- Challenge runs (Phase 13e). Safe to tweak.
--
-- After the first Ascend a player can start a Challenge: a fresh run from stage 1 with
-- one nasty rule. Their main run (gold, troops, gear, stage) is PARKED and comes back
-- exactly as it was when they leave. Beating the boss of each goal stage in TIER_GOALS
-- clears a tier: a small permanent bonus (`reward`, per tier) and a one-off prize
-- (TIER_REWARDS, the first time only). One run can clear several tiers. Tiers are kept
-- forever (also through Legacy).
--
-- No free boss packs, Ascend, Legacy or raid attacks inside a challenge. Gold rewards and
-- gold purchases made during one are held and paid out on the main run when you leave.
--
-- rules (all optional):
--   onlyTroop      only this troop type can be bought
--   noClicks       clicks, abilities and weak points do nothing
--   oneLife        losing a boss fight ends the challenge
--   bossTimeScale  boss timers x this
--   goldScale      gold x this
--   noGear         gear levels and rarity count for nothing
--   allBossMoves   every boss has Enrage, Shield and Summon
--   bossHpScale    boss HP x this
--   noExtras       skills, Generals and relics are switched off
-- reward.stat: damage | armyHp | gold | tap | bossDamageDealt (all +perTier each tier),
--   bossTime (+seconds), offline (+ to offline earnings), xp (+ to Commander XP).
--
-- Goals were checked with the simulator: with fixed goals 30-110 a player a few hours in
-- cleared every tier in two minutes, so the ladder went to 210; the balance pass after
-- Phase 13 (tools/balance_v3.py: 6 h players now reach ~250) moved it to 40-265, every
-- 25. Tiers already cleared stay cleared.

local Types = require(script.Parent.Parent.Types)

local ChallengeConfig = {
	UNLOCK_ASCENDS = 1, -- Ascends before the first challenges open

	-- Tier n is cleared by beating the boss of stage TIER_GOALS[n].
	TIER_GOALS = { 40, 65, 90, 115, 140, 165, 190, 215, 240, 265 } :: { number },

	-- One-off prize the first time a tier is cleared (same for every challenge).
	-- honorShare = share of an Ascend's Honor at your best stage; honor = the minimum.
	TIER_REWARDS = {
		{ honorShare = 0.03, honor = 5 },
		{ honorShare = 0.05, honor = 8, relicDust = 40 },
		{ honorShare = 0.08, honor = 12, scrolls = 1 },
		{ honorShare = 0.1, honor = 20, relicDust = 80 },
		{ honorShare = 0.15, honor = 30, heroChests = 1 },
		{ honorShare = 0.2, honor = 50, scrolls = 2, relicDust = 120 },
		{ honorShare = 0.25, honor = 80, relicDust = 160 },
		{ honorShare = 0.3, honor = 120, scrolls = 2 },
		{ honorShare = 0.4, honor = 200, relicDust = 250 },
		{ honorShare = 0.5, honor = 400, scrolls = 3, heroChests = 1 },
	} :: { Types.ChallengeTierReward },

	ORDER = { "LoneLegion", "HandsOff", "Poverty", "AgainstTheClock", "BareHands", "GlassArmy", "Tyrants", "BackToBasics" } :: { string },
	CHALLENGES = {
		LoneLegion = {
			id = "LoneLegion",
			name = "Lone Legion",
			rule = "Only Swordsmen can be trained.",
			color = Color3.fromRGB(210, 90, 80),
			unlockAscends = 1,
			rules = { onlyTroop = "Swordsman" },
			reward = { stat = "damage", perTier = 0.03, text = "+{v}% army damage" },
		},
		HandsOff = {
			id = "HandsOff",
			name = "Hands Off",
			rule = "Clicks, abilities and weak points do nothing. Your army is on its own.",
			color = Color3.fromRGB(120, 160, 230),
			unlockAscends = 1,
			rules = { noClicks = true },
			reward = { stat = "offline", perTier = 0.04, text = "+{v}% offline earnings" },
		},
		Poverty = {
			id = "Poverty",
			name = "Poverty",
			rule = "Enemies drop only 10% of their gold.",
			color = Color3.fromRGB(200, 170, 70),
			unlockAscends = 2,
			rules = { goldScale = 0.1 },
			reward = { stat = "gold", perTier = 0.03, text = "+{v}% gold" },
		},
		AgainstTheClock = {
			id = "AgainstTheClock",
			name = "Against the Clock",
			rule = "Boss timers are cut to a third.",
			color = Color3.fromRGB(240, 140, 60),
			unlockAscends = 3,
			rules = { bossTimeScale = 1 / 3 },
			reward = { stat = "bossTime", perTier = 0.5, text = "+{v}s on boss timers" },
		},
		BareHands = {
			id = "BareHands",
			name = "Bare Hands",
			rule = "Gear does nothing: no weapon or armor levels, no rarity.",
			color = Color3.fromRGB(170, 130, 100),
			unlockAscends = 4,
			rules = { noGear = true },
			reward = { stat = "tap", perTier = 0.03, text = "+{v}% click damage" },
		},
		GlassArmy = {
			id = "GlassArmy",
			name = "Glass Army",
			rule = "One life: lose a single boss fight and the challenge is over.",
			color = Color3.fromRGB(150, 220, 235),
			unlockAscends = 5,
			rules = { oneLife = true },
			reward = { stat = "armyHp", perTier = 0.03, text = "+{v}% army HP" },
		},
		Tyrants = {
			id = "Tyrants",
			name = "Tyrants",
			rule = "Every boss enrages, shields AND summons, and has double HP.",
			color = Color3.fromRGB(190, 80, 200),
			unlockAscends = 7,
			rules = { allBossMoves = true, bossHpScale = 2 },
			reward = { stat = "bossDamageDealt", perTier = 0.03, text = "+{v}% damage to bosses" },
		},
		BackToBasics = {
			id = "BackToBasics",
			name = "Back to Basics",
			rule = "Skills, Generals and relics are switched off.",
			color = Color3.fromRGB(140, 200, 120),
			unlockAscends = 10,
			rules = { noExtras = true },
			reward = { stat = "xp", perTier = 0.03, text = "+{v}% Commander XP" },
		},
	} :: { [string]: Types.ChallengeDef },

	REQUESTS_PER_SECOND = 1,
	REQUESTS_BURST = 4,
}

return table.freeze(ChallengeConfig)
