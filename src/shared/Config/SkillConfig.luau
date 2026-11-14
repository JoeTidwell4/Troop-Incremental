--!strict
-- Commander Level + skill tree (Phase 13b). Safe to tweak.
--
-- XP: mostly from beating bosses (more for later bosses, double for a first clear), plus
-- Ascending, daily quests, achievements and boss weak points. The level never resets
-- (not even on Legacy). Every level after 1 gives SKILL_POINTS_PER_LEVEL point.
--
-- Tree: 3 branches. A node's `tier` needs that many points already spent IN ITS BRANCH
-- (TIER_POINTS). Nodes with the same `fork` in a branch are pick-one. Respec (all points
-- back) is free once a day (DailyConfig days).
--
-- Effects (summed over ranks by Formulas.skillEffects):
--   damage / armyHp / gold / tap      multipliers, per rank: x(1 + value)
--   bossDamageDealt                   extra multiplier on damage vs bosses
--   bossDamageTaken                   multiplier on boss damage to your army (e.g. -0.1)
--   bossTime                          +seconds on every boss timer
--   bossGold                          extra multiplier on boss kill gold
--   critChance / critMultiplier       added to CombatConfig's
--   goldenChance / goldenGold         extra multipliers on golden enemy chance / gold
--   offlineHours / offlineEfficiency  added to the offline cap / efficiency
--   ascendHonor                       extra multiplier on Honor from Ascending
--   abilityCooldown / abilityDuration extra multipliers (e.g. -0.1 = 10% shorter cooldowns)
--   weakPointDamage                   extra multiplier on weak point bursts
--   extraSlots                        more ability loadout slots
--   lastStand                         damage multiplier while army HP < 25% in a boss
-- Multipliers combine as x(1 + total), so 5 ranks of +0.05 = x1.25.

local Types = require(script.Parent.Parent.Types)

local SkillConfig = {
	-- XP to go from level L to L+1 = floor(LEVEL_XP_BASE * LEVEL_XP_GROWTH ^ (L - 1)).
	LEVEL_XP_BASE = 80,
	LEVEL_XP_GROWTH = 1.1,
	MAX_LEVEL = 100,
	SKILL_POINTS_PER_LEVEL = 1,

	XP = {
		BOSS_BASE = 10, -- + bossStage // BOSS_STAGE_DIVISOR
		BOSS_STAGE_DIVISOR = 5,
		FIRST_CLEAR_MULTIPLIER = 2,
		ASCEND_PER_STAGE = 0.5, -- x highest stage of the run
		QUEST = { 20, 40, 60 }, -- by quest difficulty
		ACHIEVEMENT = 30,
		WEAK_POINT = 1,
		TOWER_FLOOR = 8, -- each new Tower floor cleared (TowerConfig)
		CHALLENGE_TIER = 40, -- each challenge tier cleared (ChallengeConfig)
	},

	TIER_POINTS = { 0, 3, 6, 9, 14 } :: { number }, -- tier n needs TIER_POINTS[n] spent in the branch
	LAST_STAND_HP = 0.25,

	BRANCHES = {
		{ id = "Warlord", displayName = "Warlord", description = "Your army: damage, HP, bosses", color = Color3.fromRGB(220, 90, 70) },
		{ id = "Quartermaster", displayName = "Quartermaster", description = "Gold, golden enemies, offline, Honor", color = Color3.fromRGB(240, 190, 60) },
		{ id = "Tactician", displayName = "Tactician", description = "Clicks, crits, abilities", color = Color3.fromRGB(90, 160, 240) },
	} :: { { id: string, displayName: string, description: string, color: Color3 } },

	NODES = {
		---------------------------------------------------------------- Warlord
		DrillSergeant = { id = "DrillSergeant", branch = "Warlord", tier = 1, order = 1, displayName = "Drill Sergeant", description = "+5% army damage per rank", maxRank = 5, cost = 1, effects = { damage = 0.05 } },
		ThickHides = { id = "ThickHides", branch = "Warlord", tier = 1, order = 2, displayName = "Thick Hides", description = "+6% army HP per rank", maxRank = 5, cost = 1, effects = { armyHp = 0.06 } },
		GlassCannon = { id = "GlassCannon", branch = "Warlord", tier = 2, order = 1, fork = "W2", displayName = "Glass Cannon", description = "+35% army damage, -15% army HP", maxRank = 1, cost = 2, effects = { damage = 0.35, armyHp = -0.15 } },
		IronWall = { id = "IronWall", branch = "Warlord", tier = 2, order = 2, fork = "W2", displayName = "Iron Wall", description = "+35% army HP, bosses deal 10% less", maxRank = 1, cost = 2, effects = { armyHp = 0.35, bossDamageTaken = -0.1 } },
		GiantSlayer = { id = "GiantSlayer", branch = "Warlord", tier = 3, order = 1, displayName = "Giant Slayer", description = "+8% damage to bosses per rank", maxRank = 3, cost = 1, effects = { bossDamageDealt = 0.08 } },
		BattleHardened = { id = "BattleHardened", branch = "Warlord", tier = 4, order = 1, displayName = "Battle Hardened", description = "+2s on every boss timer per rank", maxRank = 3, cost = 1, effects = { bossTime = 2 } },
		LastStand = { id = "LastStand", branch = "Warlord", tier = 5, order = 1, displayName = "Last Stand", description = "x2 damage while your army is under 25% HP in a boss", maxRank = 1, cost = 3, effects = { lastStand = 1 } },

		---------------------------------------------------------------- Quartermaster
		TaxCollector = { id = "TaxCollector", branch = "Quartermaster", tier = 1, order = 1, displayName = "Tax Collector", description = "+6% gold per rank", maxRank = 5, cost = 1, effects = { gold = 0.06 } },
		LuckyFind = { id = "LuckyFind", branch = "Quartermaster", tier = 1, order = 2, displayName = "Lucky Find", description = "+20% golden enemy chance per rank", maxRank = 3, cost = 1, effects = { goldenChance = 0.2 } },
		Midas = { id = "Midas", branch = "Quartermaster", tier = 2, order = 1, fork = "Q2", displayName = "Midas", description = "+25% gold, golden enemies pay +50%", maxRank = 1, cost = 2, effects = { gold = 0.25, goldenGold = 0.5 } },
		FieldCamp = { id = "FieldCamp", branch = "Quartermaster", tier = 2, order = 2, fork = "Q2", displayName = "Field Camp", description = "+3h offline cap, +15% offline gold", maxRank = 1, cost = 2, effects = { offlineHours = 3, offlineEfficiency = 0.15 } },
		SupplyLines = { id = "SupplyLines", branch = "Quartermaster", tier = 3, order = 1, displayName = "Supply Lines", description = "+5% offline gold per rank", maxRank = 3, cost = 1, effects = { offlineEfficiency = 0.05 } },
		HonorGuard = { id = "HonorGuard", branch = "Quartermaster", tier = 4, order = 1, displayName = "Honor Guard", description = "+5% Honor from Ascending per rank", maxRank = 3, cost = 1, effects = { ascendHonor = 0.05 } },
		WarProfits = { id = "WarProfits", branch = "Quartermaster", tier = 5, order = 1, displayName = "War Profits", description = "Bosses pay x3 gold", maxRank = 1, cost = 3, effects = { bossGold = 2 } },

		---------------------------------------------------------------- Tactician
		QuickHands = { id = "QuickHands", branch = "Tactician", tier = 1, order = 1, displayName = "Quick Hands", description = "+8% click damage per rank", maxRank = 5, cost = 1, effects = { tap = 0.08 } },
		Precision = { id = "Precision", branch = "Tactician", tier = 1, order = 2, displayName = "Precision", description = "+2% crit chance per rank", maxRank = 3, cost = 1, effects = { critChance = 0.02 } },
		DeadlyStrikes = { id = "DeadlyStrikes", branch = "Tactician", tier = 2, order = 1, fork = "T2", displayName = "Deadly Strikes", description = "Crits deal x6 instead of x4", maxRank = 1, cost = 2, effects = { critMultiplier = 2 } },
		RapidRecovery = { id = "RapidRecovery", branch = "Tactician", tier = 2, order = 2, fork = "T2", displayName = "Rapid Recovery", description = "Ability cooldowns 10% shorter", maxRank = 1, cost = 2, effects = { abilityCooldown = -0.1 } },
		Focus = { id = "Focus", branch = "Tactician", tier = 3, order = 1, displayName = "Focus", description = "Abilities last 10% longer per rank", maxRank = 3, cost = 1, effects = { abilityDuration = 0.1 } },
		WeakSpot = { id = "WeakSpot", branch = "Tactician", tier = 4, order = 1, displayName = "Weak Spot", description = "+20% weak point damage per rank", maxRank = 3, cost = 1, effects = { weakPointDamage = 0.2 } },
		GrandTactician = { id = "GrandTactician", branch = "Tactician", tier = 5, order = 1, displayName = "Grand Tactician", description = "A 4th ability slot (key 4)", maxRank = 1, cost = 3, effects = { extraSlots = 1 } },
	} :: { [string]: Types.SkillNodeDef },

	REQUESTS_PER_SECOND = 4,
	REQUESTS_BURST = 8,
}

return table.freeze(SkillConfig)
