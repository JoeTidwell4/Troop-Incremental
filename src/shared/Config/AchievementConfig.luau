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
--   "generals"    own >= target different Generals
--   "generalStars" any General at >= target stars
--   "generalRarity" own a General of rarity `key`
--   "generalSet"  a House set of >= target fielded Generals active
--   "relicsEquipped" >= target relics equipped; "relicRarity" own a relic of rarity `key`;
--   "relicSet" >= target equipped pieces of one relic set

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
		{ id = "Generals3", name = "War Council", description = "Recruit 3 different Generals", honor = 3, honorShare = 0.05, kind = "generals", target = 3 },
		{ id = "Generals8", name = "Hall of Heroes", description = "Recruit 8 different Generals", honor = 8, honorShare = 0.2, kind = "generals", target = 8 },
		{ id = "Generals12", name = "Every Banner", description = "Recruit all 12 Generals", honor = 20, honorShare = 0.5, kind = "generals", target = 12 },
		{ id = "Relics10", name = "Relic Hunter", description = "Find 10 relics", honor = 3, honorShare = 0.05, kind = "lifetime", key = "RelicDrop", target = 10 },
		{ id = "Relics6", name = "Fully Kitted", description = "Equip a relic in all 6 slots", honor = 5, honorShare = 0.1, kind = "relicsEquipped", target = 6 },
		{ id = "RelicSet6", name = "Perfect Set", description = "Equip 6 relics of one set", honor = 12, honorShare = 0.3, kind = "relicSet", target = 6 },
		{ id = "RelicMythic", name = "Ancient Power", description = "Own a Mythic relic", honor = 15, honorShare = 0.4, kind = "relicRarity", key = "Mythic", target = 1 },
		{ id = "Expedition10", name = "Wanderlust", description = "Complete 10 Expeditions", honor = 3, honorShare = 0.05, kind = "lifetime", key = "ExpeditionDone", target = 10 },
		{ id = "Expedition100", name = "Far and Wide", description = "Complete 100 Expeditions", honor = 8, honorShare = 0.2, kind = "lifetime", key = "ExpeditionDone", target = 100 },
		{ id = "Expedition500", name = "Cartographer", description = "Complete 500 Expeditions", honor = 18, honorShare = 0.45, kind = "lifetime", key = "ExpeditionDone", target = 500 },
		{ id = "Tower10", name = "First Steps Up", description = "Clear floor 10 of the Tower", honor = 4, honorShare = 0.08, kind = "tower", target = 10 },
		{ id = "Tower25", name = "Above the Clouds", description = "Clear floor 25 of the Tower", honor = 8, honorShare = 0.15, kind = "tower", target = 25 },
		{ id = "Tower50", name = "Halfway to Nowhere", description = "Clear floor 50 of the Tower", honor = 12, honorShare = 0.3, kind = "tower", target = 50 },
		{ id = "Tower100", name = "Top of the World", description = "Clear floor 100 of the Tower", honor = 25, honorShare = 0.6, kind = "tower", target = 100 },
		{ id = "Challenge1", name = "Challenger", description = "Clear a challenge tier", honor = 3, honorShare = 0.05, kind = "lifetime", key = "ChallengeTier", target = 1 },
		{ id = "Challenge10", name = "Glutton for Punishment", description = "Clear 10 challenge tiers", honor = 6, honorShare = 0.15, kind = "lifetime", key = "ChallengeTier", target = 10 },
		{ id = "Challenge30", name = "Trial by Fire", description = "Clear 30 challenge tiers", honor = 12, honorShare = 0.3, kind = "lifetime", key = "ChallengeTier", target = 30 },
		{ id = "Challenge60", name = "Unbreakable", description = "Clear 60 challenge tiers", honor = 20, honorShare = 0.5, kind = "lifetime", key = "ChallengeTier", target = 60 },
		{ id = "FullHouse", name = "Full House", description = "Field a full 3-General House set", honor = 6, honorShare = 0.15, kind = "generalSet", target = 3 },
		{ id = "GeneralStars5", name = "Living Legend", description = "Get a General to 5 stars", honor = 15, honorShare = 0.4, kind = "generalStars", target = 5 },
		{ id = "MythicGeneral", name = "Myth Made Real", description = "Recruit a Mythic General", honor = 15, honorShare = 0.4, kind = "generalRarity", key = "Mythic", target = 1 },
		{ id = "Golden10", name = "Gold Rush", description = "Defeat 10 golden enemies", honor = 3, honorShare = 0.05, kind = "lifetime", key = "GoldenKill", target = 10 },
		{ id = "Golden100", name = "Midas Touch", description = "Defeat 100 golden enemies", honor = 8, honorShare = 0.2, kind = "lifetime", key = "GoldenKill", target = 100 },
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
