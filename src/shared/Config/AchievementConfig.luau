--!strict
-- Achievements: permanent goals. When one is reached it becomes claimable (and stays
-- claimable even if, say, an Ascend later resets your troops). Rewards are Honor:
-- `honorShare` of what an Ascend at your best stage gives (Formulas.scaledHonor), never
-- less than `honor`. So late achievements stay worth claiming at any stage.
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
		{ id = "Stage25", name = "Into the Wilds", description = "Reach stage 25", honor = 2, honorShare = 0.1, kind = "bestStage", target = 25 },
		{ id = "Stage50", name = "Seasoned Commander", description = "Reach stage 50", honor = 4, honorShare = 0.25, kind = "bestStage", target = 50 },
		{ id = "Stage100", name = "Warlord", description = "Reach stage 100", honor = 8, honorShare = 0.5, kind = "bestStage", target = 100 },
		{ id = "Stage150", name = "Conqueror", description = "Reach stage 150", honor = 12, honorShare = 0.5, kind = "bestStage", target = 150 },
		{ id = "Stage200", name = "Legend of the Realm", description = "Reach stage 200", honor = 15, honorShare = 0.75, kind = "bestStage", target = 200 },
		{ id = "Stage250", name = "Mythic General", description = "Reach stage 250", honor = 20, honorShare = 1, kind = "bestStage", target = 250 },
		{ id = "Stage300", name = "Emperor", description = "Reach stage 300", honor = 25, honorShare = 1, kind = "bestStage", target = 300 },
		{ id = "Stage400", name = "Undying Dynasty", description = "Reach stage 400", honor = 30, honorShare = 1.5, kind = "bestStage", target = 400 },

		{ id = "Kills1K", name = "Bloodied", description = "Defeat 1,000 enemies", honor = 1, honorShare = 0.02, kind = "stat", key = "totalKills", target = 1000 },
		{ id = "Kills10K", name = "Veteran", description = "Defeat 10,000 enemies", honor = 3, honorShare = 0.05, kind = "stat", key = "totalKills", target = 10000 },
		{ id = "Kills100K", name = "Slayer", description = "Defeat 100,000 enemies", honor = 6, honorShare = 0.1, kind = "stat", key = "totalKills", target = 100000 },
		{ id = "Kills1M", name = "Unstoppable", description = "Defeat 1,000,000 enemies", honor = 12, honorShare = 0.2, kind = "stat", key = "totalKills", target = 1000000 },
		{ id = "Kills10M", name = "Endless Tide", description = "Defeat 10,000,000 enemies", honor = 20, honorShare = 0.4, kind = "stat", key = "totalKills", target = 10000000 },

		{ id = "Bosses10", name = "Giant Slayer", description = "Defeat 10 bosses", honor = 2, honorShare = 0.03, kind = "stat", key = "bossesDefeated", target = 10 },
		{ id = "Bosses50", name = "Kingsbane", description = "Defeat 50 bosses", honor = 5, honorShare = 0.08, kind = "stat", key = "bossesDefeated", target = 50 },
		{ id = "Bosses250", name = "Tyrant's End", description = "Defeat 250 bosses", honor = 10, honorShare = 0.2, kind = "stat", key = "bossesDefeated", target = 250 },
		{ id = "Bosses1000", name = "Doom of Titans", description = "Defeat 1,000 bosses", honor = 15, honorShare = 0.4, kind = "stat", key = "bossesDefeated", target = 1000 },

		{ id = "Ascend1", name = "Rebirth", description = "Ascend once", honor = 3, honorShare = 0.1, kind = "stat", key = "ascensions", target = 1 },
		{ id = "Ascend5", name = "Eternal Campaign", description = "Ascend 5 times", honor = 8, honorShare = 0.2, kind = "stat", key = "ascensions", target = 5 },
		{ id = "Ascend25", name = "Ageless", description = "Ascend 25 times", honor = 20, honorShare = 0.4, kind = "stat", key = "ascensions", target = 25 },
		{ id = "Ascend50", name = "Wheel of Ages", description = "Ascend 50 times", honor = 25, honorShare = 0.6, kind = "stat", key = "ascensions", target = 50 },
		{ id = "Ascend100", name = "Timeless", description = "Ascend 100 times", honor = 30, honorShare = 1, kind = "stat", key = "ascensions", target = 100 },

		{ id = "Swords100", name = "Shield Wall", description = "Own 100 Swordsmen", honor = 3, honorShare = 0.05, kind = "troop", key = "Swordsman", target = 100 },
		{ id = "Archers100", name = "Rain of Arrows", description = "Own 100 Archers", honor = 3, honorShare = 0.05, kind = "troop", key = "Archer", target = 100 },
		{ id = "Knights100", name = "Iron Cavalcade", description = "Own 100 Knights", honor = 3, honorShare = 0.05, kind = "troop", key = "Knight", target = 100 },
		{ id = "Mages25", name = "Arcane Circle", description = "Own 25 Mages", honor = 4, honorShare = 0.1, kind = "troop", key = "Mage", target = 25 },
		{ id = "Mages100", name = "Archmage Council", description = "Own 100 Mages", honor = 8, honorShare = 0.25, kind = "troop", key = "Mage", target = 100 },
		{ id = "Cavalry25", name = "Thundering Hooves", description = "Own 25 Cavalry", honor = 6, honorShare = 0.15, kind = "troop", key = "Cavalry", target = 25 },
		{ id = "Cavalry100", name = "Stampede", description = "Own 100 Cavalry", honor = 10, honorShare = 0.3, kind = "troop", key = "Cavalry", target = 100 },
		{ id = "Siege10", name = "Wall Breaker", description = "Own 10 Siege Engines", honor = 10, honorShare = 0.2, kind = "troop", key = "Siege", target = 10 },
		{ id = "Siege100", name = "Grand Battery", description = "Own 100 Siege Engines", honor = 15, honorShare = 0.4, kind = "troop", key = "Siege", target = 100 },

		{ id = "Packs10", name = "Treasure Hunter", description = "Open 10 gear packs", honor = 2, honorShare = 0.03, kind = "lifetime", key = "PackOpen", target = 10 },
		{ id = "Packs100", name = "Hoarder", description = "Open 100 gear packs", honor = 6, honorShare = 0.1, kind = "lifetime", key = "PackOpen", target = 100 },
		{ id = "Packs500", name = "Dragon's Hoard", description = "Open 500 gear packs", honor = 10, honorShare = 0.25, kind = "lifetime", key = "PackOpen", target = 500 },
		{ id = "Legendary", name = "Legendary!", description = "Own a Legendary piece of gear", honor = 5, honorShare = 0.15, kind = "legendary", target = 1 },

		{ id = "Faction", name = "Sworn", description = "Join a faction", honor = 1, honorShare = 0.02, kind = "faction", target = 1 },
		{ id = "WarWin", name = "Victorious", description = "Win a faction war", honor = 5, honorShare = 0.25, kind = "warWin", target = 1 },
		{ id = "Clan", name = "Brothers in Arms", description = "Join a clan", honor = 2, honorShare = 0.05, kind = "clan", target = 1 },
		{ id = "Raids10", name = "Raider", description = "Make 10 raid attacks", honor = 3, honorShare = 0.1, kind = "lifetime", key = "RaidAttack", target = 10 },
		{ id = "Raids50", name = "Siege Lord", description = "Make 50 raid attacks", honor = 6, honorShare = 0.25, kind = "lifetime", key = "RaidAttack", target = 50 },
		{ id = "Donate1K", name = "Generous", description = "Donate 1,000 Supplies", honor = 3, honorShare = 0.1, kind = "lifetime", key = "Donate", target = 1000 },
		{ id = "Donate10K", name = "Patron of the Clan", description = "Donate 10,000 Supplies", honor = 6, honorShare = 0.25, kind = "lifetime", key = "Donate", target = 10000 },
	} :: { Types.AchievementDef },
}

return table.freeze(AchievementConfig)
