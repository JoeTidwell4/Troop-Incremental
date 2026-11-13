--!strict
-- Factions and the weekly faction war. Safe to tweak.
--
-- Each faction boosts one troop type's damage AND HP by TROOP_BONUS.
-- You pick a faction after beating your first boss (or later). Switching has a cooldown,
-- and is locked during the last SWITCH_LOCK_SECONDS of a war.
--
-- War scoring (why it isn't raw kill counts: see CLAUDE.md "Design concerns"):
--   * Points come only from kills on stages within FRONTIER_WINDOW of your best stage this run.
--   * POINTS_PER_KILL per normal kill, POINTS_PER_BOSS per boss.
--   * At most DAILY_CAP points per player per war day.
--   * A member is "active" for the week after earning ACTIVE_THRESHOLD points.
--   * Faction score = total points / active members. Highest average wins.
-- Winners who were active get WINNER_GOLD_MULTIPLIER gold for the whole next week.
--
-- In Studio, wars are much shorter so you can watch one start and end.

local RunService = game:GetService("RunService")

local Types = require(script.Parent.Parent.Types)

local isStudio = RunService:IsStudio()

local FactionConfig = {
	ORDER = { "Iron", "Silverwood", "Dawn" } :: { string },

	FACTIONS = {
		Iron = {
			id = "Iron",
			displayName = "Iron Legion",
			troopId = "Swordsman",
			color = Color3.fromRGB(200, 80, 70),
			motto = "Strength in numbers.",
		},
		Silverwood = {
			id = "Silverwood",
			displayName = "Silverwood Rangers",
			troopId = "Archer",
			color = Color3.fromRGB(80, 180, 100),
			motto = "Strike from afar.",
		},
		Dawn = {
			id = "Dawn",
			displayName = "Order of the Dawn",
			troopId = "Knight",
			color = Color3.fromRGB(90, 130, 230),
			motto = "Stand unbroken.",
		},
	} :: { [string]: Types.FactionDef },

	TROOP_BONUS = 1.5, -- x damage and x HP for the faction's troop type
	PROMPT_AFTER_STAGE = 10, -- offer the faction picker once your best stage passes this
	SWITCH_COOLDOWN = 7 * 86400, -- seconds between faction changes (first pick is free)

	-- War timing. The war "week" starts Mondays 00:00 UTC (WEEK_ANCHOR is a Monday).
	WEEK_ANCHOR = 345600, -- 1970-01-05 00:00 UTC
	WEEK_SECONDS = if isStudio then 300 else 7 * 86400,
	DAYS_PER_WEEK = 7, -- the daily cap resets this many times per war
	SWITCH_LOCK_SECONDS = if isStudio then 60 else 86400,
	FINALIZE_DELAY = if isStudio then 20 else 600, -- wait for late points before picking a winner

	-- War points.
	FRONTIER_WINDOW = 5,
	POINTS_PER_KILL = 1,
	POINTS_PER_BOSS = 20,
	DAILY_CAP = 3000,
	ACTIVE_THRESHOLD = if isStudio then 20 else 200,
	WINNER_GOLD_MULTIPLIER = 1.2,

	-- Cross-server sync (see WarStore).
	SHARDS = 4, -- each faction's total is split over this many MemoryStore keys
	FLUSH_INTERVAL = if isStudio then 10 else 60, -- seconds between sending this server's points
	POLL_INTERVAL = if isStudio then 10 else 60, -- seconds between reading the standings
	BACKUP_INTERVAL = if isStudio then 30 else 300, -- leader copies totals to a DataStore
	LEADER_LOCK_SECONDS = if isStudio then 30 else 120,
	LEADERBOARD_WRITE_INTERVAL = if isStudio then 15 else 180,
	LEADERBOARD_READ_INTERVAL = if isStudio then 15 else 120,
	TOP_COUNT = 10,
	MEMORY_EXPIRATION = 14 * 86400, -- MemoryStore entries expire after this (max allowed is 45 days)

	REQUESTS_PER_SECOND = 1,
	REQUESTS_BURST = 3,

	IS_STUDIO_TEST_MODE = isStudio,
}

return table.freeze(FactionConfig)
