--!strict
-- The Studio-only test panel (UI/DebugPanelUI + server DebugService). None of this
-- exists in the live game: the client only builds the panel in Studio, and the server
-- only answers in Studio. Studio uses its own separate saves (Util/StoreNames), so
-- nothing here can touch real players, clans or leaderboards.
--
-- Each button: label shown, action sent to the server, optional fixed argument.
-- The "Stage" action takes the number typed in the panel's box instead.

export type Button = { label: string, action: string, arg: number? }

local DebugConfig = {
	SECTIONS = {
		{
			title = "Fight",
			buttons = {
				{ label = "Kill enemy / win boss", action = "Kill" },
				{ label = "Lose boss", action = "FailBoss" },
				{ label = "Next boss stage", action = "NextBoss" },
			},
		},
		{
			title = "Currency",
			buttons = {
				{ label = "+10 min gold", action = "GoldMinutes", arg = 10 },
				{ label = "+2 h gold", action = "GoldMinutes", arg = 120 },
				{ label = "Gold x1000", action = "GoldTimes", arg = 1000 },
				{ label = "+100 Honor", action = "Honor", arg = 100 },
				{ label = "+10,000 Honor", action = "Honor", arg = 10000 },
				{ label = "+10M Honor", action = "Honor", arg = 10000000 },
				{ label = "+50 Crowns", action = "Crowns", arg = 50 },
				{ label = "+10 packs", action = "Packs", arg = 10 },
				{ label = "+5 Hero Chests", action = "HeroChests", arg = 5 },
				{ label = "+3 Epic Forge", action = "Forge", arg = 3 },
				{ label = "+200 Clan Tokens", action = "ClanTokens", arg = 200 },
			},
		},
		{
			title = "Daily + clan",
			buttons = {
				{ label = "New day (login + quests)", action = "NewDay" },
				{ label = "Refill raid attacks", action = "RaidAttacks" },
				{ label = "+200 clan XP", action = "ClanXp", arg = 200 },
				{ label = "Finish clan quests", action = "ClanQuests" },
				{ label = "Unlock all wardrobe", action = "Wardrobe" },
			},
		},
		{
			title = "Danger",
			buttons = {
				{ label = "WIPE MY SAVE", action = "Wipe" },
			},
		},
	} :: { { title: string, buttons: { Button } } },

	MAX_STAGE = 10000,
}

return table.freeze(DebugConfig)
