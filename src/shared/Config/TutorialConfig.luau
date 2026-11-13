--!strict
-- Tutorial lessons (TutorialUI shows them, GuideUI in Settings replays them).
--
-- STANDING RULE (owner): every new feature a player has to learn gets its lesson here IN
-- THE SAME CHANGE, and changing how a system works means updating its lesson.
--
-- A lesson pops up once, the first time its trigger happens (saved on the account), as
-- 1-4 small cards. It never pauses the game. Each card can glow a button (`spotlight`, a
-- Spotlight key) and open a window (`open`, a Spotlight opener key). Players can replay
-- any lesson they've unlocked from the GUIDE.
--
-- when:
--   "stage"            all-time best stage >= `stage`
--   "boss"             a boss fight starts            "farming"     the stage repeats (auto-advance off)
--   "bossShield"       a boss raises its shield       "bossEnrage"  a boss enrages
--   "bossMinions"      a boss summons minions         "freePack"    you have a free gear pack
--   "skillPoint"       you have an unspent skill point
--   "ascendReady"      you can Ascend                 "legacyReady" a Legacy would give Crowns
--   "inClan"           you're in a clan               "golden"      a golden enemy appears
--   "relic"            your first relic drops
--   "ascended"         you have Ascended at least once   "inChallenge"  you're in a challenge run
--   "offline"          you come back to offline earnings
-- `stage` on event lessons = the earliest stage it can matter. When the tutorial system
-- first runs on an old save, lessons below the player's best stage count as already seen
-- (TutorialService), so veterans aren't flooded; they're all in the GUIDE.
-- Text: "{tap}" becomes "Tap" on phones and "Click" on PC.

local Types = require(script.Parent.Parent.Types)
local AbilityConfig = require(script.Parent.AbilityConfig)
local TroopConfig = require(script.Parent.TroopConfig)
local PackConfig = require(script.Parent.PackConfig)
local GeneralConfig = require(script.Parent.GeneralConfig)
local RelicConfig = require(script.Parent.RelicConfig)
local LegacyConfig = require(script.Parent.LegacyConfig)
local ClanConfig = require(script.Parent.ClanConfig)

type Lesson = Types.TutorialLesson

local TOPICS = { "Basics", "Bosses", "Army", "Troops", "Gear and packs", "Generals", "Relics", "Progress", "Clans and factions", "Prestige", "Adventure" }

local LESSONS: { Lesson } = {
	---------------------------------------------------------------- Basics
	{
		id = "Welcome", topic = "Basics", title = "Welcome, Commander!", when = "stage", stage = 1,
		steps = {
			{ text = "Your troops fight on their own. {tap} the enemy to help: every hit counts, and sometimes you land a critical hit!" },
			{ text = "Enemies drop gold. Spend it on troops in the shop below. More troops = more damage = more gold.", spotlight = "Buy:Swordsman", open = "Tab:Troops" },
		},
	},
	{
		id = "Stages", topic = "Basics", title = "Stages", when = "stage", stage = 3,
		steps = {
			{ text = "Beat 10 enemies to clear a stage. Each stage is tougher, but pays more gold. Every 10th stage is a boss." },
			{ text = "Troops get stronger at 25, 50, 100, 200... owned (x2 damage each time). Keep buying!", spotlight = "Tab:Troops" },
		},
	},
	{
		id = "Golden", topic = "Basics", title = "Golden enemy!", when = "golden", stage = 1,
		steps = { { text = "Golden enemies are rare, tougher and drop about 20x the gold, sometimes a free gear pack too. Get them!" } },
	},
	{
		id = "Offline", topic = "Basics", title = "Offline earnings", when = "offline", stage = 1,
		steps = { { text = "While you're away, your army keeps fighting and earns gold (a bit slower than live). Honor upgrades and skills raise the cap." } },
	},
	{
		id = "Quests", topic = "Progress", title = "Quests and achievements", when = "stage", stage = 6,
		steps = {
			{ text = "QUESTS has a daily login reward (come back every day!), 3 daily quests and achievements that pay Honor.", spotlight = "Menu:Quests" },
			{ text = "A red dot means something is ready to claim. Finishing all 3 daily quests gives a bonus." },
		},
	},

	---------------------------------------------------------------- Bosses
	{
		id = "FirstBoss", topic = "Bosses", title = "Boss fight!", when = "boss", stage = 9,
		steps = {
			{ text = "Bosses have a timer and hit back: the red bar is the boss, the green bar is your army's HP." },
			{ text = "{tap} the red ! targets on the boss (weak points) for big bursts of damage. Hitting several in a row adds more." },
			{ text = "Lose (time runs out or your army falls) and you go back one stage to farm. Every failed try weakens the boss a little." },
		},
	},
	{
		id = "Farming", topic = "Bosses", title = "Farming mode", when = "farming", stage = 9,
		steps = { { text = "The stage now repeats so you can farm gold. Buy troops and gear, then press FIGHT BOSS when you're ready.", spotlight = "FightBoss" } },
	},
	{
		id = "BossShield", topic = "Bosses", title = "Boss shield", when = "bossShield", stage = 19,
		steps = { { text = "Shielded! Your troops can't hurt the boss for a few seconds, but your clicks, abilities and weak points still do." } },
	},
	{
		id = "BossEnrage", topic = "Bosses", title = "Enraged boss", when = "bossEnrage", stage = 29,
		steps = { { text = "Low on HP, the boss is ENRAGED and hits twice as hard. Finish it fast, or bring more HP (Knights, armor, Shield Wall)." } },
	},
	{
		id = "BossMinions", topic = "Bosses", title = "Minions", when = "bossMinions", stage = 39,
		steps = { { text = "The boss summoned minions. They soak up your damage until they're gone, so burst them down." } },
	},

	---------------------------------------------------------------- Army (abilities, skills)
	{
		id = "Abilities", topic = "Army", title = "Abilities", when = "stage", stage = 5,
		steps = {
			{ text = "Rally doubles your troops' damage for a few seconds. Use it on bosses! Press 1, or {tap} the button.", spotlight = "Ability:Rally" },
			{ text = "More abilities unlock as you go. You can equip 3 at a time in the ARMY window.", spotlight = "Menu:Army" },
		},
	},
	{
		id = "Skills", topic = "Army", title = "Commander Level and skills", when = "skillPoint", stage = 1,
		steps = {
			{ text = "You leveled up! Beating bosses (new ones give the most), Ascending and quests give Commander XP. The level never resets.", spotlight = "Menu:Army" },
			{ text = "Each level gives a skill point. Spend it in ARMY > Skills. The 3 branches: army, gold, clicks and abilities.", open = "Army:Skills", spotlight = "Army:Skills" },
			{ text = "Deeper skills open as you spend points in a branch. Some are pick-one. You get a free respec every day." },
		},
	},

	---------------------------------------------------------------- Gear and packs
	{
		id = "Gear", topic = "Gear and packs", title = "Gear", when = "stage", stage = 10,
		steps = {
			{ text = "Each troop type has a weapon (damage) and armor (HP). Level them up in the Gear tab.", spotlight = "Tab:Gear", open = "Tab:Gear" },
			{ text = "Gear rarity (Common to Legendary) multiplies it a lot. You get rarity from gear packs." },
		},
	},
	{
		id = "Packs", topic = "Gear and packs", title = "Gear packs", when = "freePack", stage = 1,
		steps = {
			{ text = "Free gear pack! Every boss you beat for the first time in a run gives one. Open it in the Packs tab.", spotlight = "Tab:Packs", open = "Tab:Packs" },
			{ text = "A pack upgrades one troop's weapon or armor to a random rarity (odds shown). Already better? You get gold back." },
		},
	},
	{
		id = "Areas", topic = "Troops", title = "Areas and traits", when = "stage", stage = 11,
		steps = { { text = "Each boss beaten takes you to a new area. Most areas weaken one troop type by 30% (shown at the top). Mix your army!" } },
	},

	---------------------------------------------------------------- Clans and factions
	{
		id = "Factions", topic = "Clans and factions", title = "Factions", when = "stage", stage = 11,
		steps = {
			{ text = "Pick one of 3 factions: each boosts one troop type's damage and HP by 50%. You can switch later (with a cooldown).", spotlight = "Menu:War" },
			{ text = "Every week the factions fight a war. Fight on your best stages for points; the winners get a gold bonus all next week." },
		},
	},
	{
		id = "Clans", topic = "Clans and factions", title = "Clans", when = "stage", stage = 15,
		steps = {
			{ text = "Join a clan (or make one) in CLAN. Clans share a bank, perks for everyone, a weekly raid boss and a weekly Clan War.", spotlight = "Menu:Clan" },
		},
	},
	{
		id = "ClanLife", topic = "Clans and factions", title = "Your clan", when = "inClan", stage = 1,
		steps = {
			{ text = "Donate gold to the clan bank; officers buy perks that boost the whole clan.", spotlight = "Menu:Clan" },
			{ text = "Raid: 3 attacks a day on the clan boss. Clan War: everything you do earns clan XP. Both pay rewards weekly." },
			{ text = "Clan quests and the clan shop (Clan Tokens) have exclusive gear. Say hi in clan chat!" },
		},
	},
	{
		id = "Leaderboards", topic = "Progress", title = "Leaderboards", when = "stage", stage = 20,
		steps = { { text = "TOP shows the best commanders in the game: highest stage and most Honor.", spotlight = "Menu:Top" } },
	},

	---------------------------------------------------------------- Progress
	{
		id = "Wardrobe", topic = "Progress", title = "Wardrobe", when = "stage", stage = 20,
		steps = {
			{ text = "Your commander can wear a helmet, cape, weapon and back item, each with a bonus. Earn them by playing.", spotlight = "Menu:Wardrobe" },
			{ text = "Wardrobe Chests (gold) roll for exclusive pieces, with Legendary pity. Find them in WARDROBE > Chests." },
		},
	},

	---------------------------------------------------------------- Generals
	{
		id = "Generals", topic = "Generals", title = "Generals", when = "stage", stage = GeneralConfig.UNLOCK_STAGE,
		steps = {
			{ text = "Generals have joined your cause! Recruit them with Recruit Scrolls (from Ascending, achievements, daily rewards...).", open = "Army:Generals", spotlight = "Army:Generals" },
			{ text = "Field 3 at a time. Each has a passive bonus and a trait, often boosting one troop type." },
			{ text = "Duplicates add stars (stronger, higher max level). Level them up with gold." },
			{ text = "Field 2-3 Generals of the same House for a set bonus. The Mythic Marshal counts for every House!" },
		},
	},

	---------------------------------------------------------------- Relics
	{
		id = "Relics", topic = "Relics", title = "Relics", when = "relic", stage = RelicConfig.UNLOCK_STAGE,
		steps = {
			{ text = "A relic! Bosses sometimes drop them. Equip one per slot (6 slots) in ARMY > Relics.", open = "Army:Relics", spotlight = "Army:Relics" },
			{ text = "Each relic has random stats. Equip 2, 4 or 6 of the same set for extra bonuses." },
			{ text = "Salvage relics you don't need into Dust, then use Dust to level up or reroll the ones you love. Lock favorites so they're never salvaged." },
		},
	},

	---------------------------------------------------------------- Adventure
	{
		id = "Challenges", topic = "Adventure", title = "Challenges", when = "ascended", stage = 50,
		steps = {
			{ text = "New: Challenges! A challenge is a fresh run from stage 1 with one nasty rule, like Swordsmen only or no clicking.", spotlight = "Menu:Adventure" },
			{ text = "Your main run is parked while you're in one and comes back exactly as it was when you leave. Trying one never costs you progress.", open = "Adventure:Challenges", spotlight = "Adventure:Challenges" },
			{ text = "Beat the boss of each goal stage to clear a tier. Every tier is a small bonus you keep forever, plus a one-off prize. More challenges unlock as you Ascend." },
		},
	},
	{
		id = "InChallenge", topic = "Adventure", title = "You're in a challenge", when = "inChallenge", stage = 50,
		steps = {
			{ text = "This shows your challenge and the next goal. {tap} it to see your progress, or to leave and get your main run back.", spotlight = "ChallengeBanner" },
			{ text = "No Ascending, raid attacks or free boss packs in here. Free packs, Hero Chests and gold rewards are saved for your main run." },
			{ text = "Your main run earns nothing while it's parked (offline too), so don't camp in a challenge. Tiers you clear are kept even if you leave early." },
		},
	},
	---------------------------------------------------------------- Prestige
	{
		id = "Ascend", topic = "Prestige", title = "Ascend", when = "ascendReady", stage = 50,
		steps = {
			{ text = "You can Ascend! It restarts your run (gold, troops, gear, stage) and gives Honor based on how far you got.", spotlight = "Ascend" },
			{ text = "Honor buys permanent upgrades in the Honor tab: more damage, gold, HP, a head start, better abilities.", open = "Tab:Honor", spotlight = "Tab:Honor" },
			{ text = "Each run goes faster and further. Push a little past where you get stuck, then Ascend." },
		},
	},
	{
		id = "Legacy", topic = "Prestige", title = "Legacy", when = "legacyReady", stage = LegacyConfig.MIN_STAGE,
		steps = {
			{ text = "Legacy is the big reset: everything Ascend resets, plus your Honor and Honor upgrades. In return you get Crowns.", open = "Tab:Honor", spotlight = "Legacy" },
			{ text = "Crowns buy permanent upgrades that are never lost. Your Generals, skills, wardrobe, clan and achievements stay too." },
			{ text = "The more Honor you earned this time, the more Crowns. Your first Legacy gets you past your old best fast." },
		},
	},
}

-- Unlocks with a short lesson each, made from the configs, so new abilities, troops and
-- pack tiers get one automatically.
for _, abilityId in AbilityConfig.ORDER do
	local def = AbilityConfig.ABILITIES[abilityId]
	if abilityId ~= "Rally" then -- Rally is in "Abilities"
		table.insert(LESSONS, {
			id = `Ability_{abilityId}`, topic = "Army", title = `New ability: {def.displayName}`, when = "stage", stage = def.unlockStage,
			steps = { { text = `{def.description}. Equip it in ARMY > Abilities (you have {AbilityConfig.LOADOUT_SLOTS} slots).`, open = "Army:Abilities", spotlight = "Army:Abilities" } },
		})
	end
end
for _, troopId in TroopConfig.ORDER do
	local def = TroopConfig.TROOPS[troopId]
	if def.unlockStage ~= nil and def.unlockStage > 0 then
		table.insert(LESSONS, {
			id = `Troop_{troopId}`, topic = "Troops", title = `New troop: {def.displayName}`, when = "stage", stage = def.unlockStage,
			steps = { { text = `{def.displayName}: {def.role} Train them in the Troops tab.`, open = "Tab:Troops", spotlight = `Buy:{troopId}` } },
		})
	end
end
for tierId, tier in PackConfig.TIERS do
	if tier.unlockStage > 0 then
		table.insert(LESSONS, {
			id = `Pack_{tierId}`, topic = "Gear and packs", title = `New pack: {tier.displayName}`, when = "stage", stage = tier.unlockStage,
			steps = { { text = `{tier.displayName}s cost more but skip the low rarities. Odds are shown on the button.`, open = "Tab:Packs", spotlight = "Tab:Packs" } },
		})
	end
end
table.insert(LESSONS, {
	id = "ClanCreate", topic = "Clans and factions", title = "Start your own clan", when = "stage", stage = ClanConfig.CREATE_MIN_BEST_STAGE,
	steps = { { text = "You can now create your own clan: pick a name and tag in CLAN, then customize its color, emblem and motto.", spotlight = "Menu:Clan" } },
})

local BY_ID: { [string]: Lesson } = {}
for _, lesson in LESSONS do
	assert(BY_ID[lesson.id] == nil, `duplicate tutorial lesson {lesson.id}`)
	BY_ID[lesson.id] = lesson
end

return table.freeze({
	TOPICS = TOPICS,
	LESSONS = LESSONS,
	BY_ID = BY_ID,
	-- Seconds to wait after a trigger before showing the lesson (lets popups settle).
	SHOW_DELAY = 1.2,
})
