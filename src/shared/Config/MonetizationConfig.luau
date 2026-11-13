--!strict
-- Robux store: game passes (bought once, kept forever) and developer products (bought
-- as many times as you like). Safe to tweak.
--
-- HOW TO TURN AN ITEM ON: create it on create.roblox.com (your game > Monetization >
-- Passes or Developer Products), set its price there, copy its ID, and put it in `id`.
-- An id of 0 means the item is hidden and can't be bought. Prices live on Roblox's site,
-- not in code.
--
-- Design rules (keep these when adding items):
--   * Nothing random for Robux (no paid packs): Roblox requires odds disclosure for paid
--     random items and some countries restrict them.
--   * No auto-clicker: it would bypass the click rate limit everyone else plays under.
--   * Sell convenience, speed, and looks, not things that let payers win the faction war.

local Types = require(script.Parent.Parent.Types)

local MonetizationConfig = {
	PASS_ORDER = { "DoubleGold", "AutoAbilities", "GoldenSword" } :: { string },
	PASSES = {
		DoubleGold = {
			key = "DoubleGold",
			id = 2088398382,
			displayName = "2x Gold",
			description = "Double gold from every kill, forever.",
			goldMultiplier = 2,
		},
		AutoAbilities = {
			key = "AutoAbilities",
			id = 2089262362, -- created on Roblox as "Auto Clicker"; should be renamed "Auto Abilities" there
			displayName = "Auto Abilities",
			description = "Rally, Barrage and Plunder fire on their own whenever ready. Can be toggled.",
		},
		GoldenSword = {
			key = "GoldenSword",
			id = 0,
			displayName = "Golden Sword",
			description = "Your commander wields a glowing golden blade. Looks only.",
		},
	} :: { [string]: Types.PassDef },

	PRODUCT_ORDER = { "GoldSmall", "GoldLarge" } :: { string },
	PRODUCTS = {
		GoldSmall = {
			key = "GoldSmall",
			id = 0,
			displayName = "Pouch of Gold",
			description = "30 minutes of your army's gold, instantly.",
			goldMinutes = 30,
		},
		GoldLarge = {
			key = "GoldLarge",
			id = 0,
			displayName = "Chest of Gold",
			description = "4 hours of your army's gold, instantly.",
			goldMinutes = 240,
		},
	} :: { [string]: Types.ProductDef },

	-- Gold products always give at least this much (e.g. before you own any troops).
	GOLD_PRODUCT_MINIMUM = 100,
	-- How many recent purchase ids each save remembers (stops double-granting a purchase).
	PURCHASE_HISTORY_SIZE = 50,
	-- Seconds to wait for a purchase to be saved before telling Roblox to retry later.
	RECEIPT_SAVE_TIMEOUT = 30,
	-- How often owned Auto Abilities try to fire (seconds).
	AUTO_ABILITY_INTERVAL = 1,
}

return table.freeze(MonetizationConfig)
