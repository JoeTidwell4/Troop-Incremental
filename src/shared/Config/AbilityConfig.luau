--!strict
-- Commander abilities. Safe to tweak.
-- An ability can use any mix of these effects:
--   duration + damageMultiplier  -> troop and click damage multiplied while active
--   duration + goldMultiplier    -> gold from kills multiplied while active
--   burstDpsSeconds              -> instant hit worth that many seconds of army DPS
-- Unlocks are based on the highest stage you've ever reached.
--
-- UPGRADES: bought with Honor (HonorService), permanent (kept on Ascend). Each adds
-- perLevel to one stat of its ability per level, up to maxLevel. Capped on purpose:
-- active play should stay about 2-3x idle (see CLAUDE.md "Active play").
-- Cost of the next level = baseCost * costGrowth ^ (current level), rounded.

local Types = require(script.Parent.Parent.Types)

local AbilityConfig = {
	ORDER = { "Rally", "Barrage", "Plunder" } :: { Types.AbilityId },

	ABILITIES = {
		Rally = {
			id = "Rally",
			displayName = "Rally",
			description = "x2 troop damage for 10s",
			cooldown = 60,
			unlockStage = 5,
			duration = 10,
			damageMultiplier = 2,
			key = Enum.KeyCode.One,
		},
		Barrage = {
			id = "Barrage",
			displayName = "Barrage",
			description = "Instant hit: 20s of army damage",
			cooldown = 45,
			unlockStage = 15,
			burstDpsSeconds = 20,
			key = Enum.KeyCode.Two,
		},
		Plunder = {
			id = "Plunder",
			displayName = "Plunder",
			description = "x2 gold for 15s",
			cooldown = 120,
			unlockStage = 25,
			duration = 15,
			goldMultiplier = 2,
			key = Enum.KeyCode.Three,
		},
	} :: { [string]: Types.AbilityDef },

	UPGRADE_ORDER = {
		"RallyPower",
		"RallyDuration",
		"BarragePower",
		"BarrageCooldown",
		"PlunderPower",
		"PlunderDuration",
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
	} :: { [string]: Types.AbilityUpgradeDef },

	-- Ability requests per second a player may send.
	REQUESTS_PER_SECOND = 4,
	REQUESTS_BURST = 6,
}

return table.freeze(AbilityConfig)
