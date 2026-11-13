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

	-- Fairness (Phase 11 balance pass). Boss HP and damage grow a fixed amount per stage
	-- but armies grow in big jumps, so later bosses were either instant or impossible.
	INTRO_SECONDS = 2, -- the boss can't be hurt and the timer waits while it makes its entrance
	MAX_DAMAGE_PER_SECOND_FRACTION = 0.12, -- a boss loses at most 12% of its max HP per second (fights last 8s+)
	-- The boss's hits are kept between these fractions of your army's max HP per second
	-- (before enrage doubles them): never a one-shot, never harmless. Army HP still matters
	-- inside the band (a tougher army sits nearer the minimum).
	ARMY_DAMAGE_MIN_FRACTION = 0.015,
	ARMY_DAMAGE_MAX_FRACTION = 0.06,
	-- Each failed attempt in a row on the same boss takes this much off its HP, up to the max.
	WEAKEN_PER_FAIL = 0.1,
	WEAKEN_MAX = 0.5,

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
