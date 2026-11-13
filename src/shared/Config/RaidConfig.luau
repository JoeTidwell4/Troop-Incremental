--!strict
-- Weekly clan raid boss. Safe to tweak.
--
-- Each member gets ATTACKS_PER_DAY live attacks of ATTACK_SECONDS against the raid boss on
-- their own battlefield (clicks and abilities count). Damage is converted to "raid units":
--   units = damage / (normal enemy HP at your best stage this run) * Warbanners perk
-- i.e. how many of your own kills that damage was worth, so a veteran and a new player
-- contribute comparably for the same effort. Capped at UNITS_CAP_PER_ATTACK per attack.
-- The clan's units add up all week; every TIERS threshold passed is one tier.
-- When the week ends, everyone who attacked gets HONOR_PER_TIER Honor per tier and a free
-- gear pack every PACK_EVERY_TIERS tiers, claimed automatically next time they play.

local RunService = game:GetService("RunService")

local isStudio = RunService:IsStudio()

local RaidConfig = {
	BOSS_NAME = "The Iron Colossus", -- the first boss in the rotation (older code / fallback)
	BOSS_COLOR = Color3.fromRGB(230, 120, 40),

	-- Raid boss rotation (Phase 11d G): a different boss each raid week, in this order.
	-- Multipliers change how each damage source counts against this boss:
	--   troopMultiplier  your army's damage    queuedMultiplier  clicks, abilities, weak points
	--   weakPointInterval  how often weak points appear (x the normal gap; lower = more often)
	BOSSES = {
		{
			id = "Colossus",
			name = "The Iron Colossus",
			kind = "Colossus",
			color = Color3.fromRGB(230, 120, 40),
			description = "A steady giant. No tricks.",
			troopMultiplier = 1,
			queuedMultiplier = 1,
			weakPointInterval = 1,
		},
		{
			id = "Kraken",
			name = "The Abyssal Kraken",
			kind = "Kraken",
			color = Color3.fromRGB(120, 50, 140),
			description = "Thick hide: troops -20%, clicks and abilities +50%.",
			troopMultiplier = 0.8,
			queuedMultiplier = 1.5,
			weakPointInterval = 1,
		},
		{
			id = "FrostWyrm",
			name = "The Elder Frost Wyrm",
			kind = "FrostWyrm",
			color = Color3.fromRGB(140, 200, 255),
			description = "Brittle scales: weak points appear twice as often.",
			troopMultiplier = 1,
			queuedMultiplier = 1,
			weakPointInterval = 0.5,
		},
		{
			id = "MagmaTitan",
			name = "The Molten Titan",
			kind = "MagmaTitan",
			color = Color3.fromRGB(150, 50, 25),
			description = "Slow and huge: troops +30%, clicks and abilities -30%.",
			troopMultiplier = 1.3,
			queuedMultiplier = 0.7,
			weakPointInterval = 1,
		},
	} :: { { id: string, name: string, kind: string, color: Color3, description: string, troopMultiplier: number, queuedMultiplier: number, weakPointInterval: number } },

	ATTACKS_PER_DAY = 3,
	ATTACK_SECONDS = 30,
	UNITS_CAP_PER_ATTACK = 60,

	-- Cumulative clan units needed for each tier.
	TIERS = { 100, 300, 600, 1000, 1600, 2500, 3600, 5000, 7000, 10000 } :: { number },
	HONOR_PER_TIER = 2, -- minimum per tier (what you get before stage 50)
	HONOR_SHARE_PER_TIER = 0.03, -- per tier: 3% of an Ascend's Honor at your best stage
	PACK_EVERY_TIERS = 2,

	-- Raid weeks start Monday 00:00 UTC like faction wars. Studio: short weeks/days for testing.
	WEEK_ANCHOR = 345600,
	WEEK_SECONDS = if isStudio then 600 else 7 * 86400,
	DAY_SECONDS = if isStudio then 120 else 86400,

	POLL_INTERVAL = if isStudio then 15 else 60, -- re-read raid progress for clans online here
	TOP_COUNT = 10,
	IS_STUDIO_TEST_MODE = isStudio,
}

return table.freeze(RaidConfig)
