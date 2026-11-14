--!strict
-- Daily login rewards and daily quests. Safe to tweak.
--
-- Days roll over at 00:00 UTC (in Studio, every DAY_SECONDS so you can test quickly).
-- Login calendar: claim once per day. Claiming on consecutive days walks through the 7
-- rewards; missing a day starts again at day 1. After day 7 it loops.
-- Gold rewards are "minutes of your army's gold", so they're worth the same at any stage.

local RunService = game:GetService("RunService")

local Types = require(script.Parent.Parent.Types)

local isStudio = RunService:IsStudio()

local DailyConfig = {
	DAY_SECONDS = if isStudio then 180 else 86400,
	IS_STUDIO_TEST_MODE = isStudio,

	LOGIN_REWARDS = {
		{ goldMinutes = 15 },
		{ packs = 1 },
		{ goldMinutes = 30, honor = 2, honorShare = 0.05 },
		{ packs = 2 },
		{ goldMinutes = 60 },
		{ packs = 3 },
		{ heroChests = 1, honor = 10, honorShare = 0.25, scrolls = 3, spins = 1 }, -- Epic+ pack, Honor, 3 Recruit Scrolls, a Fortune Wheel spin
	} :: { Types.RewardDef },

	-- Gold rewards always give at least this much (e.g. before you own troops).
	GOLD_MINIMUM = 50,

	QUESTS_PER_DAY = 3,
	REROLLS_PER_DAY = 1,
	ALL_QUESTS_BONUS = { heroChests = 1, honor = 5, honorShare = 0.1, scrolls = 1, spins = 1 } :: Types.RewardDef,

	-- Each quest also pays Honor by difficulty: a share of what an Ascend at your best
	-- stage gives (Formulas.scaledHonor), never less than QUEST_HONOR_MIN.
	QUEST_HONOR_SHARE = { 0.02, 0.04, 0.08 } :: { number },
	QUEST_HONOR_MIN = { 1, 2, 3 } :: { number },

	-- Quest pool. Each quest rolls one difficulty: target and gold reward go together.
	-- `requires` hides quests you can't do yet: "abilities" (Rally unlocked), "gear"
	-- (best stage 10+), "faction", "clan".
	QUESTS = {
		{ key = "Kill", activity = "Kill", text = "Defeat {n} enemies", targets = { 150, 300, 600 }, minutes = { 10, 20, 30 } },
		{ key = "Boss", activity = "BossWin", text = "Defeat {n} boss(es)", targets = { 1, 2, 3 }, minutes = { 15, 25, 40 }, requires = "gear" },
		{ key = "WeakPoint", activity = "WeakPoint", text = "Hit {n} boss weak point(s)", targets = { 3, 6, 10 }, minutes = { 10, 20, 30 }, requires = "gear" },
		{ key = "Ability", activity = "Ability", text = "Use abilities {n} times", targets = { 8, 15, 25 }, minutes = { 10, 20, 30 }, requires = "abilities" },
		{ key = "Troops", activity = "TroopBuy", text = "Train {n} troops", targets = { 20, 50, 100 }, minutes = { 10, 20, 30 } },
		{ key = "Gear", activity = "GearUpgrade", text = "Upgrade gear {n} times", targets = { 5, 10, 20 }, minutes = { 10, 20, 30 }, requires = "gear" },
		{ key = "Packs", activity = "PackOpen", text = "Open {n} gear pack(s)", targets = { 1, 2, 4 }, minutes = { 10, 15, 25 }, requires = "gear" },
		{ key = "War", activity = "WarPoints", text = "Earn {n} war points", targets = { 150, 400, 800 }, minutes = { 15, 25, 40 }, requires = "faction" },
		{ key = "Raid", activity = "RaidAttack", text = "Make {n} raid attack(s)", targets = { 1, 2, 3 }, minutes = { 15, 25, 40 }, requires = "clan" },
		{ key = "Donate", activity = "Donate", text = "Donate {n} Supplies to your clan", targets = { 30, 80, 150 }, minutes = { 10, 20, 30 }, requires = "clan" },
	} :: { Types.QuestDef },

	REQUESTS_PER_SECOND = 3,
	REQUESTS_BURST = 6,
}

return table.freeze(DailyConfig)
