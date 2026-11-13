--!strict
-- Ascend (prestige). Safe to tweak.
--
-- Ascending resets your run (gold, troops, gear levels AND rarity, stage, boss free-pack
-- tracking) and gives Honor based on the highest stage reached THIS run.
-- Kept forever: Honor, Honor upgrades, unlocked abilities (they use your all-time best
-- stage), unopened free packs, the pack bad-luck counter, and stats.
--
-- Honor for a run = floor(HONOR_BASE * HONOR_GROWTH ^ (highest stage - MIN_STAGE))
-- With 10 and 1.08: stage 50 -> 10, 60 -> 21, 70 -> 46, 80 -> 100 (doubles every ~9 stages).

local AscendConfig = {
	MIN_STAGE = 50,
	HONOR_BASE = 10,
	HONOR_GROWTH = 1.08,

	REQUESTS_PER_SECOND = 1,
	REQUESTS_BURST = 2,
}

return table.freeze(AscendConfig)
