--!strict
-- General economy settings. Safe to tweak.

local EconomyConfig = {
	-- Gold a brand-new player starts with (enough for their first Swordsman).
	STARTING_GOLD = 10,

	-- Buy requests per second a player may send, plus a short burst allowance.
	BUY_REQUESTS_PER_SECOND = 10,
	BUY_REQUESTS_BURST = 15,
}

return table.freeze(EconomyConfig)
