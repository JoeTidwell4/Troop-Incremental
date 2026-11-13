--!strict
-- Commander abilities. Safe to tweak.
-- An ability can use any mix of these effects:
--   duration + damageMultiplier  -> troop and click damage multiplied while active
--   duration + goldMultiplier    -> gold from kills multiplied while active
--   duration + tapMultiplier     -> click damage multiplied while active
--   duration + bossDamageTaken   -> boss damage to your army multiplied while active
--   duration + weakPointGapScale -> boss weak points come more often while active
--   burstDpsSeconds              -> instant hit worth that many seconds of army DPS
--     (+ executeThreshold/Multiplier: bigger if the enemy is low)
--   healFraction                 -> heals that share of army HP (bossOnly)
--   bountyKills + bountyGoldMultiplier -> the next N kills drop extra gold
-- Unlocks are based on the highest stage you've ever reached.
--
-- UPGRADES: bought with Honor (HonorService), permanent (kept on Ascend). Each adds
-- perLevel to one stat of its ability per level, up to maxLevel. Capped on purpose:
-- active play should stay about 2-3x idle (see CLAUDE.md "Active play").
-- Cost of the next level = baseCost * costGrowth ^ (current level), rounded.

local Types = require(script.Parent.Parent.Types)

local AbilityConfig = {
	-- Every ability, in the order the ARMY window lists them (unlock order).
	ORDER = { "Rally", "Frenzy", "Barrage", "Plunder", "ShieldWall", "Bounty", "Execute", "WarDrums", "Fortify" } :: { Types.AbilityId },

	-- Phase 13a: you equip LOADOUT_SLOTS of them (keys 1/2/3). Swapping only outside
	-- boss fights and raids; a freshly equipped ability needs SWAP_COOLDOWN seconds first
	-- (or its own remaining cooldown, if longer), so you can't chain every ability.
	LOADOUT_SLOTS = 3,
	DEFAULT_LOADOUT = { "Rally", "Barrage", "Plunder" } :: { Types.AbilityId },
	SWAP_COOLDOWN = 15,
	SLOT_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three } :: { Enum.KeyCode },

	-- Numeric fields copied into AbilityStats (Formulas.abilityStats) so upgrades can add to them.
	STAT_FIELDS = {
		"cooldown",
		"duration",
		"damageMultiplier",
		"goldMultiplier",
		"burstDpsSeconds",
		"tapMultiplier",
		"bossDamageTaken",
		"executeThreshold",
		"executeMultiplier",
		"healFraction",
		"bountyKills",
		"bountyGoldMultiplier",
		"weakPointGapScale",
	} :: { string },

	ABILITIES = {
		Rally = {
			id = "Rally",
			displayName = "Rally",
			description = "x2 troop damage for 10s",
			cooldown = 60,
			unlockStage = 5,
			duration = 10,
			damageMultiplier = 2,
		},
		Frenzy = {
			id = "Frenzy",
			displayName = "Frenzy",
			description = "x3 click damage for 10s",
			cooldown = 60,
			unlockStage = 10,
			duration = 10,
			tapMultiplier = 3,
		},
		Barrage = {
			id = "Barrage",
			displayName = "Barrage",
			description = "Instant hit: 20s of army damage",
			cooldown = 45,
			unlockStage = 15,
			burstDpsSeconds = 20,
		},
		Plunder = {
			id = "Plunder",
			displayName = "Plunder",
			description = "x2 gold for 15s",
			cooldown = 120,
			unlockStage = 25,
			duration = 15,
			goldMultiplier = 2,
		},
		ShieldWall = {
			id = "ShieldWall",
			displayName = "Shield Wall",
			description = "Bosses deal half damage for 8s",
			cooldown = 60,
			unlockStage = 35,
			duration = 8,
			bossDamageTaken = 0.5,
		},
		Bounty = {
			id = "Bounty",
			displayName = "Bounty",
			description = "Your next 15 kills drop x5 gold",
			cooldown = 60,
			unlockStage = 45,
			bountyKills = 15,
			bountyGoldMultiplier = 5,
		},
		Execute = {
			id = "Execute",
			displayName = "Execute",
			description = "Hit for 8s of army damage, x3 on enemies below 25% HP",
			cooldown = 50,
			unlockStage = 55,
			burstDpsSeconds = 8,
			executeThreshold = 0.25,
			executeMultiplier = 3,
		},
		WarDrums = {
			id = "WarDrums",
			displayName = "War Drums",
			description = "Boss weak points appear 2.5x as often for 15s",
			cooldown = 75,
			unlockStage = 65,
			duration = 15,
			weakPointGapScale = 0.4,
		},
		Fortify = {
			id = "Fortify",
			displayName = "Fortify",
			description = "Boss fights: heal your army 30%",
			cooldown = 75,
			unlockStage = 80,
			healFraction = 0.3,
			bossOnly = true,
		},
	} :: { [string]: Types.AbilityDef },

	UPGRADE_ORDER = {
		"RallyPower",
		"RallyDuration",
		"BarragePower",
		"BarrageCooldown",
		"PlunderPower",
		"PlunderDuration",
		"FrenzyPower",
		"ShieldWallDuration",
		"BountyKills",
		"ExecutePower",
		"WarDrumsDuration",
		"FortifyPower",
	} :: { string },
	UPGRADES = {
		RallyPower = {
			id = "RallyPower",
			abilityId = "Rally",
			displayName = "Rally Power",
			stat = "damageMultiplier",
			perLevel = 0.15, -- x2 -> x3.5
			maxLevel = 10,
			baseCost = 4,
			costGrowth = 1.7,
		},
		RallyDuration = {
			id = "RallyDuration",
			abilityId = "Rally",
			displayName = "Rally Duration",
			stat = "duration",
			perLevel = 0.5, -- 10s -> 15s
			maxLevel = 10,
			baseCost = 4,
			costGrowth = 1.7,
		},
		BarragePower = {
			id = "BarragePower",
			abilityId = "Barrage",
			displayName = "Barrage Power",
			stat = "burstDpsSeconds",
			perLevel = 1.5, -- 20s -> 35s of army damage (40s made active play ~4x idle at max)
			maxLevel = 10,
			baseCost = 5,
			costGrowth = 1.7,
		},
		BarrageCooldown = {
			id = "BarrageCooldown",
			abilityId = "Barrage",
			displayName = "Barrage Reload",
			stat = "cooldown",
			perLevel = -1, -- 45s -> 35s
			maxLevel = 10,
			baseCost = 5,
			costGrowth = 1.7,
		},
		PlunderPower = {
			id = "PlunderPower",
			abilityId = "Plunder",
			displayName = "Plunder Power",
			stat = "goldMultiplier",
			perLevel = 0.1, -- x2 -> x3
			maxLevel = 10,
			baseCost = 6,
			costGrowth = 1.7,
		},
		PlunderDuration = {
			id = "PlunderDuration",
			abilityId = "Plunder",
			displayName = "Plunder Duration",
			stat = "duration",
			perLevel = 0.7, -- 15s -> 22s
			maxLevel = 10,
			baseCost = 6,
			costGrowth = 1.7,
		},
		-- Phase 13a: one track per new ability.
		FrenzyPower = {
			id = "FrenzyPower",
			abilityId = "Frenzy",
			displayName = "Frenzy Power",
			stat = "tapMultiplier",
			perLevel = 0.2, -- x3 -> x5 clicks
			maxLevel = 10,
			baseCost = 4,
			costGrowth = 1.7,
		},
		ShieldWallDuration = {
			id = "ShieldWallDuration",
			abilityId = "ShieldWall",
			displayName = "Shield Wall Duration",
			stat = "duration",
			perLevel = 0.5, -- 8s -> 13s
			maxLevel = 10,
			baseCost = 5,
			costGrowth = 1.7,
		},
		BountyKills = {
			id = "BountyKills",
			abilityId = "Bounty",
			displayName = "Bounty Size",
			stat = "bountyKills",
			perLevel = 1.5, -- 15 -> 30 kills
			maxLevel = 10,
			baseCost = 6,
			costGrowth = 1.7,
		},
		ExecutePower = {
			id = "ExecutePower",
			abilityId = "Execute",
			displayName = "Execute Power",
			stat = "burstDpsSeconds",
			perLevel = 1, -- 8s -> 18s of army damage
			maxLevel = 10,
			baseCost = 6,
			costGrowth = 1.7,
		},
		WarDrumsDuration = {
			id = "WarDrumsDuration",
			abilityId = "WarDrums",
			displayName = "War Drums Duration",
			stat = "duration",
			perLevel = 1, -- 15s -> 25s
			maxLevel = 10,
			baseCost = 7,
			costGrowth = 1.7,
		},
		FortifyPower = {
			id = "FortifyPower",
			abilityId = "Fortify",
			displayName = "Fortify Power",
			stat = "healFraction",
			perLevel = 0.02, -- 30% -> 50%
			maxLevel = 10,
			baseCost = 8,
			costGrowth = 1.7,
		},
	} :: { [string]: Types.AbilityUpgradeDef },

	-- Ability requests per second a player may send.
	REQUESTS_PER_SECOND = 4,
	REQUESTS_BURST = 6,
}

return table.freeze(AbilityConfig)
