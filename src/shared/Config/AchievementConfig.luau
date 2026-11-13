--!strict
-- Achievements: permanent goals. When one is reached it becomes claimable (and stays
-- claimable even if, say, an Ascend later resets your troops). Rewards are Honor.
--
-- kind:
--   "bestStage"   all-time best stage >= target
--   "stat"        data.stats[key] >= target (totalKills, bossesDefeated, ascensions)
--   "lifetime"    lifetime activity counter >= target (PackOpen, RaidAttack, Donate, ...)
--   "troop"       own >= target of troop `key` at once
--   "legendary"   any gear slot is Legendary
--   "clan" / "faction"  in a clan / picked a faction
--   "warWin"      currently enjoying a faction war victory bonus

local Types = require(script.Parent.Parent.Types)

local AchievementConfig = {
	LIST = {
		{ id = "Stage25", name = "Into the Wilds", description = "Reach stage 25", honor = 2, kind = "bestStage", target = 25 },
		{ id = "Stage50", name = "Seasoned Commander", description = "Reach stage 50", honor = 4, kind = "bestStage", target = 50 },
		{ id = "Stage100", name = "Warlord", description = "Reach stage 100", honor = 8, kind = "bestStage", target = 100 },
		{ id = "Stage200", name = "Legend of the Realm", description = "Reach stage 200", honor = 15, kind = "bestStage", target = 200 },

		{ id = "Kills1K", name = "Bloodied", description = "Defeat 1,000 enemies", honor = 1, kind = "stat", key = "totalKills", target = 1000 },
		{ id = "Kills10K", name = "Veteran", description = "Defeat 10,000 enemies", honor = 3, kind = "stat", key = "totalKills", target = 10000 },
		{ id = "Kills100K", name = "Slayer", description = "Defeat 100,000 enemies", honor = 6, kind = "stat", key = "totalKills", target = 100000 },
		{ id = "Kills1M", name = "Unstoppable", description = "Defeat 1,000,000 enemies", honor = 12, kind = "stat", key = "totalKills", target = 1000000 },

		{ id = "Bosses10", name = "Giant Slayer", description = "Defeat 10 bosses", honor = 2, kind = "stat", key = "bossesDefeated", target = 10 },
		{ id = "Bosses50", name = "Kingsbane", description = "Defeat 50 bosses", honor = 5, kind = "stat", key = "bossesDefeated", target = 50 },
		{ id = "Bosses250", name = "Tyrant's End", description = "Defeat 250 bosses", honor = 10, kind = "stat", key = "bossesDefeated", target = 250 },

		{ id = "Ascend1", name = "Rebirth", description = "Ascend once", honor = 3, kind = "stat", key = "ascensions", target = 1 },
		{ id = "Ascend5", name = "Eternal Campaign", description = "Ascend 5 times", honor = 8, kind = "stat", key = "ascensions", target = 5 },
		{ id = "Ascend25", name = "Ageless", description = "Ascend 25 times", honor = 20, kind = "stat", key = "ascensions", target = 25 },

		{ id = "Swords100", name = "Shield Wall", description = "Own 100 Swordsmen", honor = 3, kind = "troop", key = "Swordsman", target = 100 },
		{ id = "Archers100", name = "Rain of Arrows", description = "Own 100 Archers", honor = 3, kind = "troop", key = "Archer", target = 100 },
		{ id = "Knights100", name = "Iron Cavalcade", description = "Own 100 Knights", honor = 3, kind = "troop", key = "Knight", target = 100 },
		{ id = "Mages25", name = "Arcane Circle", description = "Own 25 Mages", honor = 4, kind = "troop", key = "Mage", target = 25 },
		{ id = "Cavalry25", name = "Thundering Hooves", description = "Own 25 Cavalry", honor = 6, kind = "troop", key = "Cavalry", target = 25 },
		{ id = "Siege10", name = "Wall Breaker", description = "Own 10 Siege Engines", honor = 10, kind = "troop", key = "Siege", target = 10 },

		{ id = "Packs10", name = "Treasure Hunter", description = "Open 10 gear packs", honor = 2, kind = "lifetime", key = "PackOpen", target = 10 },
		{ id = "Packs100", name = "Hoarder", description = "Open 100 gear packs", honor = 6, kind = "lifetime", key = "PackOpen", target = 100 },
		{ id = "Legendary", name = "Legendary!", description = "Own a Legendary piece of gear", honor = 5, kind = "legendary", target = 1 },

		{ id = "Faction", name = "Sworn", description = "Join a faction", honor = 1, kind = "faction", target = 1 },
		{ id = "WarWin", name = "Victorious", description = "Win a faction war", honor = 5, kind = "warWin", target = 1 },
		{ id = "Clan", name = "Brothers in Arms", description = "Join a clan", honor = 2, kind = "clan", target = 1 },
		{ id = "Raids10", name = "Raider", description = "Make 10 raid attacks", honor = 3, kind = "lifetime", key = "RaidAttack", target = 10 },
		{ id = "Donate1K", name = "Generous", description = "Donate 1,000 Supplies", honor = 3, kind = "lifetime", key = "Donate", target = 1000 },
	} :: { Types.AchievementDef },
}

return table.freeze(AchievementConfig)
