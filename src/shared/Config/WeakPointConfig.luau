--!strict
-- Weak points: during boss fights and raid attacks, a glowing target pops up on the
-- enemy now and then. Tap it before it closes for a burst of damage. Hits in a row
-- build a streak that makes each burst a bit bigger. Safe to tweak.
--
-- The server spawns every weak point and checks the timing of the tap, so a player can't
-- make them appear more often. A cheater could tap them automatically, but the bonus is
-- capped (a boss fight lasts 30s, so ~3 weak points = ~10-12s of extra army damage).

local WeakPointConfig = {
	FIRST_DELAY_MIN = 3, -- seconds into the fight before the first one
	FIRST_DELAY_MAX = 5,
	INTERVAL_MIN = 7, -- seconds between weak points
	INTERVAL_MAX = 9,
	WINDOW = 2, -- seconds the player has to tap it
	GRACE = 0.4, -- extra seconds allowed for network lag

	BURST_SECONDS = 3, -- a hit deals this many seconds of army DPS
	STREAK_BONUS = 0.1, -- +10% per hit in a row before this one
	MAX_STREAK_BONUS = 0.3,

	TICK = 0.2, -- how often the server checks fights (seconds)

	REQUESTS_BURST = 4,
	REQUESTS_PER_SECOND = 3,
}

return table.freeze(WeakPointConfig)
