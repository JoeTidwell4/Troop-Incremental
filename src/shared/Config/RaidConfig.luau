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
	BOSS_NAME = "The Iron Colossus",
	BOSS_COLOR = Color3.fromRGB(230, 120, 40),

	ATTACKS_PER_DAY = 3,
	ATTACK_SECONDS = 30,
	UNITS_CAP_PER_ATTACK = 60,

	-- Cumulative clan units needed for each tier.
	TIERS = { 100, 300, 600, 1000, 1600, 2500, 3600, 5000, 7000, 10000 } :: { number },
	HONOR_PER_TIER = 2,
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
