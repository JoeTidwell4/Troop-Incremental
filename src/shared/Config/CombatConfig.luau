--!strict
-- Combat simulation, tapping, and anti-autoclicker limits. Safe to tweak.
--
-- Damage per tap = TAP_FLAT_DAMAGE + (army DPS * TAP_ARMY_DPS_FRACTION)
-- At ~7 taps/sec that makes active play about 1.7x idle. Phase 2 abilities add the rest.

local CombatConfig = {
	-- How many times per second the server updates every player's fight.
	TICK_RATE = 5,

	TAP_FLAT_DAMAGE = 1,
	-- Critical clicks (Phase 13a): each click has CRIT_CHANCE to deal CRIT_MULTIPLIER x
	-- damage, rolled on the server. On average that's +24% click damage.
	CRIT_CHANCE = 0.08,
	CRIT_MULTIPLIER = 4,
	TAP_ARMY_DPS_FRACTION = 0.08,

	-- Server-side tap cap. Taps above this rate are thrown away.
	TAP_MAX_PER_SECOND = 15,
	TAP_BURST = 20,

	-- The client groups taps and sends them this often (seconds).
	TAP_SEND_INTERVAL = 0.25,
	-- Max taps one message may claim, and how many tap messages per second are allowed.
	TAP_MAX_PER_PACKET = 20,
	TAP_PACKETS_PER_SECOND = 8,
	TAP_PACKETS_BURST = 12,

	-- How often the server sends each player their updated state (seconds).
	SYNC_INTERVAL = 0.25,
}

return table.freeze(CombatConfig)
