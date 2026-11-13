--!strict
-- Gear packs. Gold only, never Robux. Safe to tweak.
--
-- A pack picks a random troop, a random slot (Weapon/Armor), and a random rarity.
--   Better than that slot's current rarity -> the slot upgrades (keeps its level).
--   Same or worse                         -> DUPLICATE_REFUND of the pack price back in gold.
-- Three tiers, all bought with gold. Price = gold per kill at your highest stage this run
-- * the tier's priceInKills, so prices stay relevant at every stage. Pricier tiers skip
-- the low rarities and are slightly better value per gold for Epic/Legendary (a small
-- bulk bonus), so they're worth it but never mandatory.
-- Epic Forge tokens (Robux product, see MonetizationConfig) make a chosen troop + slot
-- FORGE_RARITY. Not random, so it's allowed for Robux.
-- Bad-luck protection: if PITY_EVERY packs in a row miss PITY_MIN_RARITY, the next one hits it.
-- One free pack is granted the first time you beat each boss.

local Types = require(script.Parent.Parent.Types)

local BASIC_ODDS = { 60, 25, 10, 4, 1 }

local PackConfig = {
	-- Percent chance per rarity, same order as GearConfig.RARITIES. Each must add up to 100.
	-- Free packs and Hero Chests use the Basic odds (Hero Chests force Epic or better).
	ODDS = BASIC_ODDS :: { number },

	TIER_ORDER = { "Basic", "Elite", "Royal" } :: { string },
	TIERS = {
		Basic = { id = "Basic", displayName = "Basic Pack", priceInKills = 25, odds = BASIC_ODDS, unlockStage = 0 },
		Elite = { id = "Elite", displayName = "Elite Pack", priceInKills = 70, odds = { 0, 50, 35, 12, 3 }, unlockStage = 20 },
		Royal = { id = "Royal", displayName = "Royal Pack", priceInKills = 180, odds = { 0, 0, 60, 32, 8 }, unlockStage = 40 },
	} :: { [string]: Types.PackTierDef },

	DUPLICATE_REFUND = 0.5, -- of the price paid (free packs and chests refund the Basic price)
	FORGE_RARITY = 4, -- Epic

	PITY_EVERY = 20, -- was 30
	PITY_MIN_RARITY = 4, -- Epic

	FREE_PACKS_PER_NEW_BOSS = 1,

	REQUESTS_PER_SECOND = 2,
	REQUESTS_BURST = 4,
}

return table.freeze(PackConfig)
