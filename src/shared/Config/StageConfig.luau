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

	-- Golden enemies (Phase 13a): after each kill on a normal stage, the next enemy has
	-- this chance to be golden: more HP, and its kill pays GOLDEN_GOLD_KILLS kills' worth
	-- of gold, with GOLDEN_PACK_CHANCE of a free gear pack on top.
	-- 1% x 20 kills' worth = about +19% gold on normal stages overall.
	GOLDEN_CHANCE = 0.01,
	GOLDEN_HP_MULTIPLIER = 3,
	GOLDEN_GOLD_KILLS = 20,
	GOLDEN_PACK_CHANCE = 0.2,
}

return table.freeze(StageConfig)
