--!strict
-- Analytics (Roblox AnalyticsService, server only). Results show up in the Creator
-- Dashboard under Analytics: Onboarding funnel, Progression (bosses), Economy (Honor)
-- and Custom events (Ascend, SessionEnd). Nothing here affects gameplay.

local AnalyticsConfig = {
	-- Onboarding funnel stage milestones (see AnalyticsService ONBOARDING for the order).
	STAGE_STEPS = { 5, 11, 20, 30, 50 },

	-- Safety cap so we never come near Roblox's per-server event limits.
	MAX_EVENTS_PER_PLAYER_PER_MINUTE = 30,

	-- How often (seconds) to check whether a player reached the next onboarding step.
	CHECK_INTERVAL = 1,

	-- Custom-field buckets: best stage is reported in groups of this many stages, so the
	-- dashboard gets a few dozen values instead of thousands.
	STAGE_BUCKET = 10,

	-- In Studio nothing is sent; with this on, each event is printed to Output instead so
	-- you can see them fire while testing.
	PRINT_IN_STUDIO = true,
}

return table.freeze(AnalyticsConfig)
