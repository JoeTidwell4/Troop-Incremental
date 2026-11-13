--!strict
-- Gear: every troop type has a Weapon slot (boosts that type's damage) and an Armor slot
-- (boosts that type's HP). Safe to tweak.
--
-- Slot multiplier = levelEffect * rarity multiplier
--   levelEffect   = (1 + EFFECT_PER_LEVEL * level) * TIER_MULTIPLIER ^ floor(level / TIER_EVERY)
-- Cost of the next level = troop baseCost * BASE_COST_MULTIPLIER * COST_GROWTH ^ level
-- Cost grows much faster than effect, so gear is great early and gets steadily worse value.

local Types = require(script.Parent.Parent.Types)

local GearConfig = {
	SLOTS = { "weapon", "armor" } :: { Types.GearSlot },

	SLOT_INFO = {
		weapon = { displayName = "Weapon", statName = "damage" },
		armor = { displayName = "Armor", statName = "HP" },
	} :: { [string]: { displayName: string, statName: string } },

	-- Item names per troop, used for display ("Rare Steel Bow").
	ITEM_NAMES = {
		weapon = { Swordsman = "Sword", Archer = "Bow", Knight = "Lance", Mage = "Staff", Cavalry = "Spear", Siege = "Catapult" },
		armor = { Swordsman = "Mail", Archer = "Leathers", Knight = "Plate", Mage = "Robes", Cavalry = "Barding", Siege = "Frame" },
	} :: { [string]: { [string]: string } },

	BASE_COST_MULTIPLIER = 5,
	COST_GROWTH = 1.9,
	EFFECT_PER_LEVEL = 0.10,
	TIER_EVERY = 10,
	TIER_MULTIPLIER = 2,
	MAX_LEVEL = 500,
	-- Max levels bought by one "Max" click.
	MAX_LEVELS_PER_REQUEST = 100,

	-- Tier names by level band (0-9 Iron, 10-19 Steel, ...). The last one repeats.
	TIERS = { "Iron", "Steel", "Mithril", "Adamant", "Dragonbone", "Celestial" } :: { string },

	-- Index 1 is the starting rarity. Packs can upgrade a slot's rarity.
	RARITIES = {
		{ name = "Common", multiplier = 1, color = Color3.fromRGB(190, 190, 195) },
		{ name = "Uncommon", multiplier = 1.5, color = Color3.fromRGB(90, 200, 100) },
		{ name = "Rare", multiplier = 2.5, color = Color3.fromRGB(70, 140, 255) },
		{ name = "Epic", multiplier = 4, color = Color3.fromRGB(180, 90, 240) },
		{ name = "Legendary", multiplier = 7, color = Color3.fromRGB(255, 170, 40) },
	} :: { Types.RarityDef },

	-- Gear upgrade requests per second a player may send.
	REQUESTS_PER_SECOND = 10,
	REQUESTS_BURST = 15,
}

return table.freeze(GearConfig)
