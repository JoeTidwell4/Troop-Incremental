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

	-- Boss moves (which bosses use which is set per area in AreaConfig.bossMoves):
	--   Enrage: below ENRAGE_HP_FRACTION of its HP, the boss hits ENRAGE_MULTIPLIER times as hard.
	--   Shield: every SHIELD_EVERY seconds it raises a shield for SHIELD_SECONDS; your troops
	--           can't hurt it then, only clicks and abilities can.
	--   Summon: at SUMMON_AT_FRACTION of its HP it calls minions with SUMMON_HP_FRACTION of its
	--           max HP that must be beaten before the boss takes damage again.
	ENRAGE_HP_FRACTION = 0.3,
	ENRAGE_MULTIPLIER = 2,
	SHIELD_EVERY = 10,
	SHIELD_SECONDS = 3,
	SUMMON_AT_FRACTION = 0.6,
	SUMMON_HP_FRACTION = 0.15,
}

return table.freeze(BossConfig)
