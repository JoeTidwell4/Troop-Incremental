--!strict
-- Boss stages. Safe to tweak.
--
-- Every BOSS_EVERY-th stage is a single boss instead of normal enemies.
-- Boss HP      = normal enemy HP on that stage * BOSS_HP_MULTIPLIER
-- Boss gold    = normal gold per kill on that stage * BOSS_GOLD_MULTIPLIER
-- Boss damage  = normal enemy HP on that stage * BOSS_DPS_FACTOR, per second, dealt to
--                your army's total HP. You lose if army HP hits 0 OR the timer runs out.
-- Losing drops you back one stage and turns auto-advance off until you press Fight Boss.

local BossConfig = {
	BOSS_EVERY = 10,
	BOSS_HP_MULTIPLIER = 12,
	BOSS_GOLD_MULTIPLIER = 10,
	BOSS_DPS_FACTOR = 0.12,
	BOSS_TIME_LIMIT = 30, -- seconds
}

return table.freeze(BossConfig)
