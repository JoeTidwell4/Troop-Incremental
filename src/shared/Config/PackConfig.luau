--!strict
-- Gear packs. Gold only, never Robux. Safe to tweak.
--
-- A pack picks a random troop, a random slot (Weapon/Armor), and a random rarity.
--   Better than that slot's current rarity -> the slot upgrades (keeps its level).
--   Same or worse                         -> DUPLICATE_REFUND of the pack price back in gold.
-- Price = gold per kill at your highest stage * PRICE_IN_KILLS, so it stays relevant.
-- Bad-luck protection: if PITY_EVERY packs in a row miss PITY_MIN_RARITY, the next one hits it.
-- One free pack is granted the first time you beat each boss.

local PackConfig = {
	-- Percent chance per rarity, same order as GearConfig.RARITIES. Must add up to 100.
	ODDS = { 60, 25, 10, 4, 1 } :: { number },

	PRICE_IN_KILLS = 25, -- was 40
	DUPLICATE_REFUND = 0.5,

	PITY_EVERY = 20, -- was 30
	PITY_MIN_RARITY = 4, -- Epic

	FREE_PACKS_PER_NEW_BOSS = 1,

	REQUESTS_PER_SECOND = 2,
	REQUESTS_BURST = 4,
}

return table.freeze(PackConfig)
