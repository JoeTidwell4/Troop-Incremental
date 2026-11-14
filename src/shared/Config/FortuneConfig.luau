--!strict
-- The Fortune Wheel (camp structure). Safe to tweak.
--
-- A FREE reward wheel. Spins are earned, never bought (no Robux, no gold, nothing you own
-- is ever put at stake), so a spin can only win: Roblox's gambling rules are about risking
-- something for a chance at more. Keep the look a war-camp wheel, never a casino.
--
-- Spins: 1 free every DailyConfig day (given automatically), +1 from the daily all-quests
-- bonus and +1 on login day 7 (RewardDef.spins in DailyConfig). At most MAX_SPINS saved.
-- Odds are shown in the window; a JACKPOT is guaranteed within PITY_JACKPOT spins.

local Types = require(script.Parent.Parent.Types)

local FortuneConfig = {
	UNLOCK_STAGE = 10,
	MAX_SPINS = 3,
	PITY_JACKPOT = 30,

	-- In wheel order (clockwise from the top). weight = percent. Rewards use RewardDef
	-- fields (DailyService.grant) plus `dust` and `relic` (minimum rarity; below best
	-- stage RelicConfig.UNLOCK_STAGE it pays RELIC_FALLBACK_DUST instead).
	PRIZES = {
		{ id = "Gold", name = "20 min of gold", weight = 24, color = Color3.fromRGB(240, 200, 70), reward = { goldMinutes = 20 } },
		{ id = "Dust", name = "80 Relic Dust", weight = 20, color = Color3.fromRGB(170, 120, 230), dust = 80, reward = {} },
		{ id = "Honor", name = "Honor", weight = 16, color = Color3.fromRGB(120, 180, 255), reward = { honorShare = 0.05, honor = 3 } },
		{ id = "Scrolls", name = "2 Recruit Scrolls", weight = 12, color = Color3.fromRGB(90, 200, 140), reward = { scrolls = 2 } },
		{ id = "BigGold", name = "60 min of gold", weight = 10, color = Color3.fromRGB(255, 170, 40), reward = { goldMinutes = 60 } },
		{ id = "Relic", name = "Epic+ relic", weight = 10, color = Color3.fromRGB(200, 90, 240), relic = "Epic", reward = {} },
		{ id = "HeroChest", name = "Hero Chest", weight = 7, color = Color3.fromRGB(230, 90, 90), reward = { heroChests = 1 } },
		{ id = "Jackpot", name = "JACKPOT", weight = 1, color = Color3.fromRGB(255, 230, 120), relic = "Legendary", reward = { scrolls = 5, heroChests = 1 } },
	} :: { Types.FortunePrize },
	JACKPOT = "Jackpot",
	RELIC_FALLBACK_DUST = 150,

	REQUESTS_PER_SECOND = 1,
	REQUESTS_BURST = 3,
}

return table.freeze(FortuneConfig)
