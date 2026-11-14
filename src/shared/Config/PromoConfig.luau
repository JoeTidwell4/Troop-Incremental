--!strict
-- Promo codes + the owner's ADMIN panel (PromoService, AdminService). Safe to tweak.
--
-- Codes give in-game rewards only, never Robux passes (a public code for Double Gold
-- would end its sales); free passes are given per person from the ADMIN panel. Each
-- player can redeem a code once. Codes are letters and numbers, not case sensitive.

local PromoConfig = {
	CODE_PATTERN = "^[A-Z0-9]+$",
	CODE_MIN = 3,
	CODE_MAX = 20,
	MAX_DAYS = 365,
	MAX_CODES = 50, -- live codes at once (the owner's list)
	MAX_GRANTS = 200, -- free-pass players listed in the panel

	-- Reward fields a code can give, in panel order, with a cap per code.
	REWARD_ORDER = { "packs", "heroChests", "scrolls", "spins", "goldMinutes", "dust" } :: { string },
	REWARDS = {
		packs = { name = "Gear packs", max = 50 },
		heroChests = { name = "Hero Chests", max = 10 },
		scrolls = { name = "Recruit Scrolls", max = 50 },
		spins = { name = "Wheel spins", max = 3 },
		goldMinutes = { name = "Minutes of gold", max = 600 },
		dust = { name = "Relic Dust", max = 5000 },
	} :: { [string]: { name: string, max: number } },

	REDEEM_BURST = 3,
	REDEEM_PER_SECOND = 0.1, -- ~6 tries a minute: no guessing codes by brute force
}

return table.freeze(PromoConfig)
