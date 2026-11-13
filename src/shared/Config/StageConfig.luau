--!strict
-- How stages scale. Safe to tweak any number here.
--
-- Enemy HP on stage S   = ENEMY_HP_BASE * ENEMY_HP_GROWTH ^ (S - 1)
-- Gold per kill on stage S = GOLD_BASE * GOLD_GROWTH ^ (S - 1)
-- HP grows faster than gold on purpose: that's what eventually slows you down.

local StageConfig = {
	ENEMIES_PER_STAGE = 10,

	ENEMY_HP_BASE = 8,
	ENEMY_HP_GROWTH = 1.17,

	GOLD_BASE = 1.5,
	GOLD_GROWTH = 1.15,

	-- Max stages a player can clear in one server tick (extra damage is wasted).
	-- Stops a huge damage spike from skipping dozens of stages at once.
	MAX_STAGE_CLEARS_PER_TICK = 1,
}

return table.freeze(StageConfig)
