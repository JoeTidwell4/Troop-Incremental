--!strict
-- Commander abilities. Safe to tweak.
-- An ability can use any mix of these effects:
--   duration + damageMultiplier  -> troop and click damage multiplied while active
--   duration + goldMultiplier    -> gold from kills multiplied while active
--   burstDpsSeconds              -> instant hit worth that many seconds of army DPS
-- Unlocks are based on the highest stage you've ever reached.

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

	-- Ability requests per second a player may send.
	REQUESTS_PER_SECOND = 4,
	REQUESTS_BURST = 6,
}

return table.freeze(AbilityConfig)
