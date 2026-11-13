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

	GOLD_BASE = 1.8, -- was 1.5 (+20% gold everywhere, owner asked for a little more gold)
	GOLD_GROWTH = 1.15,
}

return table.freeze(StageConfig)
