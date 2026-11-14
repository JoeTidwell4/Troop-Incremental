--!strict
-- The game's Roblox group ("Community"). Safe to tweak.
--
-- Members get MEMBER_ITEM, a commander cosmetic (looks only, no stats: joining is free,
-- so it must never be power). The game checks membership on join and again when the
-- player closes the in-game join prompt (Settings > Join our group). The item is kept
-- once earned.

local CommunityConfig = {
	GROUP_ID = 1048329670,
	MEMBER_ITEM = "CommandersPennant",
	CHECK_REQUESTS_BURST = 2,
	CHECK_REQUESTS_PER_SECOND = 0.2,
}

return table.freeze(CommunityConfig)
