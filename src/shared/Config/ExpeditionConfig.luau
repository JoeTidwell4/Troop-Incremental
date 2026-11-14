--!strict
-- Expeditions (Phase 13g). Safe to tweak.
--
-- Send spare Generals (owned, not fielded) on timed missions that bring back loot. Real
-- time, also while offline. Missions always succeed: team power only changes HOW MUCH
-- comes back (x0.5 .. x1.5 of the base). A bonus roll on return (odds shown) can add more.
-- No new permanent bonuses: Expeditions only pay currencies the game already has.
-- Sized against offline earnings (8 h away = 2 h of gold at 25%): three full-power teams
-- on 8 h gold missions bring back ~4.5 h of gold; on Honor ~0.9 of an Ascend's Honor.
--
-- Board: BOARD_SIZE missions; a mission you send is replaced by a new one right away, and
-- the whole board is new every DailyConfig day. REROLLS_PER_DAY free rerolls.
-- Slots: SLOTS missions at once (+1 at THIRD_SLOT_STAGE). The Scout Party (no Generals,
-- SCOUT_POWER) can always go, on one mission at a time.
--
-- Team power = sum over the Generals of stars x (1 + LEVEL_STEP x (level - 1)), x
-- HOUSE_BONUS for those of the mission's House (the Marshal counts for every House).
-- Reward scale = clamp(power / the duration's recommended power, MIN_SCALE, MAX_SCALE).

local RunService = game:GetService("RunService")

local Types = require(script.Parent.Parent.Types)

local isStudio = RunService:IsStudio()

local ExpeditionConfig = {
	UNLOCK_STAGE = 40,
	SLOTS = 2,
	THIRD_SLOT_STAGE = 100,
	BOARD_SIZE = 4,
	REROLLS_PER_DAY = 1,
	TEAM_SIZE = 3,

	LEVEL_STEP = 0.05,
	HOUSE_BONUS = 1.5,
	SCOUT_POWER = 1.5,
	MIN_SCALE = 0.5,
	MAX_SCALE = 1.5,

	DURATION_ORDER = { "Short", "Medium", "Long" } :: { string },
	-- seconds = real length (Studio: seconds, to test); power = recommended team power.
	-- Rewards per duration (x the reward scale): rewards[type] = amount; a type missing
	-- here can't roll for that duration. gold = minutes of army gold, honor = share of an
	-- Ascend's Honor at your best stage, relic = minimum rarity (one relic, not scaled).
	DURATIONS = {
		Short = {
			id = "Short", name = "30 minutes", seconds = if isStudio then 30 else 1800, power = 2,
			rewards = { Dust = 12, Gold = 8, Honor = 0.015 },
		},
		Medium = {
			id = "Medium", name = "2 hours", seconds = if isStudio then 60 else 7200, power = 4,
			rewards = { Dust = 50, Gold = 20, Honor = 0.05, Scrolls = 1, Relic = "Rare" },
		},
		Long = {
			id = "Long", name = "8 hours", seconds = if isStudio then 120 else 28800, power = 7,
			rewards = { Dust = 200, Gold = 60, Honor = 0.2, Scrolls = 2, Relic = "Epic", HeroChest = 1 },
		},
	} :: { [string]: Types.ExpeditionDuration },

	-- Reward types: display name + how often they show up on the board.
	REWARD_ORDER = { "Dust", "Gold", "Honor", "Scrolls", "Relic", "HeroChest" } :: { string },
	REWARDS = {
		Dust = { name = "Relic Dust", weight = 30 },
		Gold = { name = "Gold", weight = 25 },
		Honor = { name = "Honor", weight = 20 },
		Scrolls = { name = "Recruit Scrolls", weight = 14 },
		Relic = { name = "A relic", weight = 8 },
		HeroChest = { name = "A Hero Chest", weight = 3 },
	} :: { [string]: { name: string, weight: number } },

	-- Bonus roll when a team comes back. Shown in the UI.
	BONUS = {
		{ id = "None", weight = 60, text = "Nothing extra" },
		{ id = "Bountiful", weight = 25, text = "Bountiful: +50% of the haul" },
		{ id = "Scroll", weight = 12, text = "+1 Recruit Scroll" },
		{ id = "Relic", weight = 3, text = "An Epic or better relic" },
	} :: { { id: string, weight: number, text: string } },
	BOUNTIFUL = 1.5,

	REQUESTS_PER_SECOND = 2,
	REQUESTS_BURST = 6,
}

return table.freeze(ExpeditionConfig)
