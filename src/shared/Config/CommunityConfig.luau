--!strict
-- The game's Roblox group ("Community"). Safe to tweak.
--
-- Members get (owner's call: a real incentive to join):
--   * GOLD_BONUS more gold while they're in the group (re-checked every RECHECK_SECONDS,
--     so leaving the group turns it off),
--   * WELCOME_GIFT once per account (data.community.welcomed, so leave + rejoin can't
--     farm it),
--   * MEMBER_ITEM, a commander cosmetic (looks only; kept once earned).
-- Kept small on purpose: joining is free, so it must not feel mandatory. (+10% gold is
-- about 1 stage of progress.) Checked on join, when the in-game join prompt closes
-- (Settings > Join our group), and every RECHECK_SECONDS.

local CommunityConfig = {
	GROUP_ID = 1048329670,
	MEMBER_ITEM = "CommandersPennant",
	GOLD_BONUS = 0.1,
	WELCOME_GIFT = { packs = 3, heroChests = 1 },
	RECHECK_SECONDS = 600,
	CHECK_REQUESTS_BURST = 2,
	CHECK_REQUESTS_PER_SECOND = 0.2,
}

return table.freeze(CommunityConfig)
