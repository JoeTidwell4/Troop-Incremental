--!strict
-- Offline earnings. Safe to tweak.
--
-- While you're away, your army keeps fighting normal enemies on the highest stage you
-- cleared this run, at EFFICIENCY of its normal gold rate, for up to CAP_HOURS.
-- Stages don't advance while offline (no skipping bosses). Field Rations (Honor shop)
-- adds to the cap and efficiency.

local OfflineConfig = {
	EFFICIENCY = 0.25,
	CAP_HOURS = 8,
	-- Absences shorter than this give nothing (so quick rejoins don't spam the popup).
	MIN_SECONDS = 60,
	-- How often the server records "last seen" while you play, so a crash doesn't lose it.
	SAVE_INTERVAL = 60,
}

return table.freeze(OfflineConfig)
