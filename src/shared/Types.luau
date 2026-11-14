--!strict
-- Shared type definitions. No logic lives here.

local BigNum = require(script.Parent.BigNum)

export type BigNum = BigNum.BigNum

export type TroopId = "Swordsman" | "Archer" | "Knight" | "Mage" | "Cavalry" | "Siege"
export type AbilityId = "Rally" | "Barrage" | "Plunder" | "Frenzy" | "ShieldWall" | "Bounty" | "Execute" | "WarDrums" | "Fortify"
export type EncounterKind = "Normal" | "Boss" | "Raid"
export type GearSlot = "weapon" | "armor"

-- Troop counts keyed by TroopId. Typed as string keys so new troop types can be added
-- to the config without changing saved data.
export type TroopCounts = { [string]: number }

export type TroopDef = {
	id: TroopId,
	displayName: string,
	role: string,
	baseCost: number, -- gold cost of the very first one
	costGrowth: number, -- each one you own multiplies the next cost by this
	baseDps: number, -- damage per second per troop, before multipliers
	baseHp: number, -- HP per troop (only matters in boss fights), before multipliers
	color: Color3, -- visual only
	unlockStage: number?, -- all-time best stage needed before it can be trained
	bossMultiplier: number?, -- extra damage against bosses (and the raid boss)
	normalMultiplier: number?, -- extra damage against normal enemies
}

-- An area's trait: one troop type deals less damage there.
export type AreaTrait = {
	name: string, -- e.g. "Armored"
	troopId: string,
	damageMultiplier: number, -- e.g. 0.7 = -30%
}

export type AbilityDef = {
	id: AbilityId,
	displayName: string,
	description: string,
	cooldown: number, -- seconds
	unlockStage: number, -- highest stage needed to use it
	duration: number?, -- seconds the effect lasts (timed abilities)
	damageMultiplier: number?,
	goldMultiplier: number?,
	burstDpsSeconds: number?, -- instant damage = army DPS * this
	tapMultiplier: number?, -- click damage multiplied while active
	bossDamageTaken: number?, -- boss damage to your army multiplied while active (0.5 = half)
	executeThreshold: number?, -- burst x executeMultiplier if the enemy is below this HP fraction
	executeMultiplier: number?,
	healFraction: number?, -- boss fights only: heals this much of the army's max HP
	bountyKills: number?, -- the next N kills drop bountyGoldMultiplier x gold
	bountyGoldMultiplier: number?,
	weakPointGapScale: number?, -- weak points come this much more often while active (0.4 = 2.5x)
	bossOnly: boolean?, -- can only be used during a boss fight (it would be wasted otherwise)
}

-- Something the commander can wear (CommanderConfig.ITEMS).
export type CommanderItemDef = {
	id: string,
	slot: string, -- "Helmet" | "Cape" | "Weapon" | "Back"
	displayName: string,
	rarity: number, -- 1-5, same colors as gear rarity
	multiplier: number?, -- bonus to the slot's stat while equipped (nil = looks only)
	style: string, -- which look Visuals/CommanderGear builds
	color: Color3,
	unlock: { kind: string, value: number?, pass: string?, chest: string? },
}

-- Result of opening a Wardrobe Chest.
export type ChestResult = {
	ok: boolean,
	reason: string?,
	itemId: string?,
	duplicate: boolean?, -- already owned: refund instead
	refund: BigNum?,
}

-- The commander's wardrobe as the client sees it (snapshot field `commander`).
export type CommanderView = {
	owned: { [string]: boolean },
	equipped: { [string]: string }, -- slot -> item id ("" = nothing)
	pity: { [string]: number }, -- chest id -> chests opened since the last Legendary
}

-- One upgrade track of an ability (AbilityConfig.UPGRADES), bought with Honor.
export type AbilityUpgradeDef = {
	id: string,
	abilityId: string,
	displayName: string,
	stat: string, -- any numeric AbilityStats field, e.g. "duration", "cooldown", "tapMultiplier"
	perLevel: number, -- added to the stat per level (negative = lower, e.g. cooldown)
	maxLevel: number,
	baseCost: number, -- Honor
	costGrowth: number,
}

-- An ability's numbers after upgrades (Formulas.abilityStats).
export type AbilityStats = {
	cooldown: number,
	duration: number?,
	damageMultiplier: number?,
	goldMultiplier: number?,
	burstDpsSeconds: number?,
	tapMultiplier: number?,
	bossDamageTaken: number?,
	executeThreshold: number?,
	executeMultiplier: number?,
	healFraction: number?,
	bountyKills: number?,
	bountyGoldMultiplier: number?,
	weakPointGapScale: number?,
}

export type RarityDef = {
	name: string,
	multiplier: number,
	color: Color3,
}

-- One gear slot's state. rarity is an index into GearConfig.RARITIES (1 = Common).
export type GearSlotState = {
	level: number,
	rarity: number,
}

export type TroopGear = {
	weapon: GearSlotState,
	armor: GearSlotState,
}

-- Gear for every troop type, keyed by TroopId.
export type GearSet = { [string]: TroopGear }

export type PackTierDef = {
	id: string,
	displayName: string,
	priceInKills: number, -- price = this many kills' worth of gold at your best stage this run
	odds: { number }, -- percent per rarity, adds up to 100
	unlockStage: number, -- all-time best stage needed to buy it
}

export type PackState = {
	free: number, -- unopened free packs
	hero: number, -- unopened Hero Chests (guaranteed Epic or better)
	forge: number, -- unused Epic Forge tokens (Robux product: pick a troop + slot, it becomes Epic)
	sinceEpic: number, -- packs opened in a row without hitting the pity rarity
	opened: number, -- lifetime total
	rewardedBossStage: number, -- highest boss stage that already granted its free pack
}

export type HonorUpgradeDef = {
	id: string,
	displayName: string,
	description: string,
	baseCost: number, -- Honor
	costGrowth: number,
	maxLevel: number?,
	damageMultiplier: number?,
	goldMultiplier: number?,
	armyHpMultiplier: number?,
	tapMultiplier: number?,
	tapPerLevel: number?, -- additive: +this click damage per level (x(1 + tapPerLevel * level))
	startGoldMultiplier: number?,
	offlineHoursPerLevel: number?,
	offlineEfficiencyPerLevel: number?,
}

export type FactionDef = {
	id: string,
	displayName: string,
	troopId: TroopId, -- troop type this faction boosts
	color: Color3,
	motto: string,
}

-- This player's war record for one week (saved).
export type WarRecord = {
	weekId: number,
	faction: string, -- faction the points were earned for
	points: number,
	dayId: number,
	dayPoints: number,
	active: boolean, -- reached ACTIVE_THRESHOLD this week
}

export type FactionStanding = {
	points: number,
	active: number, -- active members
	average: number, -- points / active members (the score)
}

export type WarResult = {
	weekId: number,
	winner: string, -- faction id, or "" if nobody scored
	standings: { [string]: FactionStanding },
}

-- Shared war info sent to every client (WarSync remote).
export type WarState = {
	weekId: number,
	secondsLeft: number,
	studioTestMode: boolean,
	available: boolean, -- false if the cross-server store couldn't be reached
	standings: { [string]: FactionStanding },
	top: { [string]: { { name: string, points: number } } },
	lastResult: WarResult?,
}

export type ClanRole = "Leader" | "Officer" | "Member"

-- This player's raid participation for one raid week (saved).
export type RaidRecord = {
	weekId: number,
	clanId: string, -- clan the attacks were for
	attacks: number, -- this week
	units: number, -- this week
	dayId: number,
	attacksToday: number,
	claimedWeek: number, -- last raid week whose rewards were granted
}

-- A clan's raid progress for one week (stored in the "ClanRaid" DataStore).
export type RaidProgress = {
	units: number,
	contributors: { [string]: { name: string, units: number, attacks: number } },
}

-- Sent to clan members (RaidSync remote).
export type RaidView = {
	weekId: number,
	bossId: string, -- this week's raid boss (RaidConfig.BOSSES)
	secondsLeft: number,
	units: number,
	tier: number,
	top: { { name: string, units: number, attacks: number } },
	studioTestMode: boolean,
}

export type ClanPerkDef = {
	id: string,
	displayName: string,
	description: string,
	baseCost: number, -- Supplies
	costGrowth: number,
	maxLevel: number,
	damageMultiplier: number?,
	goldMultiplier: number?,
	armyHpMultiplier: number?,
	raidMultiplier: number?,
}

export type ClanMember = {
	role: ClanRole,
	name: string,
	joinedAt: number,
	donated: number, -- lifetime Supplies donated to this clan
}

-- Stored in the "Clans" DataStore. The clan record is the source of truth for membership.
export type ClanRecord = {
	id: string,
	name: string,
	tag: string,
	faction: string, -- "" unless CLAN_REQUIRES_SAME_FACTION
	open: boolean,
	createdAt: number,
	members: { [string]: ClanMember }, -- keyed by tostring(userId)
	memberCount: number,
	bank: number, -- Supplies
	perks: { [string]: number }, -- perk id -> level
	version: number, -- +1 on every change
	-- Customization + requests (Phase 11d; missing on older records):
	color: number?, -- index into ClanConfig.COLORS
	emblem: number?, -- index into ClanConfig.EMBLEMS
	motto: string?,
	requests: { [string]: { name: string, at: number, bestStage: number } }?, -- userId -> pending join request
	questWeek: number?, -- Clan War week the quests below belong to
	quests: { { key: string, target: number, progress: number } }?, -- this week's clan quests
	memberWeekXp: { [string]: number }?, -- userId -> XP this Clan War week (weekId)
	lastMemberWeekXp: { [string]: number }?, -- same for lastWeekId (MVP)
	-- Clan XP (Phase 10c; missing on older records = 0 / -1):
	xp: number?, -- lifetime, sets the clan level
	weekId: number?, -- Clan War week that weekXp belongs to
	weekXp: number?,
	lastWeekId: number?, -- the week before weekId, kept for rewards and late XP
	lastWeekXp: number?,
}

-- One clan in the browse list.
export type ClanSummary = {
	id: string,
	name: string,
	tag: string,
	memberCount: number,
	faction: string,
	open: boolean,
}

-- What a member's client is told about their clan (ClanSync remote).
export type ClanView = {
	inClan: boolean,
	clan: ClanRecord?,
	myRole: ClanRole?,
	donatedToday: number,
	myWeekXp: number?, -- XP you gave this clan this Clan War week
	myDayXp: number?, -- XP you gave today (daily cap ClanConfig.XP_DAILY_CAP)
	requestClanId: string?, -- not in a clan: the clan you asked to join
	questClaims: { [string]: boolean }?, -- clan quests you've claimed this week (index as string)
}

-- One clan chat message (already filtered on the sender's server).
export type ClanChatMessage = {
	id: string,
	clanId: string,
	userId: number,
	name: string,
	text: string,
	at: number,
}

-- One row of the weekly Clan War board.
export type ClanWarEntry = {
	rank: number,
	clanId: string,
	name: string,
	tag: string,
	xp: number,
}

-- ClanWarSync remote: this week's standings.
export type ClanWarView = {
	weekId: number,
	secondsLeft: number,
	top: { ClanWarEntry },
	myRank: number?, -- your clan's place if it's on the board
	-- Head-to-head this week (nil until last week's results are in):
	matchup: { bye: boolean, opponentName: string?, opponentTag: string?, opponentXp: number? }?,
}

-- Per-player Clan War record in the save.
export type ClanWarRecord = {
	weekId: number,
	clanId: string, -- the clan your XP this week went to
	xp: number,
	dayId: number,
	dayXp: number,
	lastWeekId: number, -- previous week you played (for rewards)
	lastClanId: string,
	lastXp: number,
	claimedWeek: number, -- last week whose rewards were handled
}

export type ClanResult = {
	ok: boolean,
	reason: string?,
	clans: { ClanSummary }?,
}

export type AreaTheme = {
	name: string,
	bossName: string,
	scenery: string, -- prop set around the battlefield (Client/Visuals/Environment)
	enemyKind: string, -- main creature (also summoned minions)
	enemyKinds: { string }, -- creatures that take turns in normal stages (Client/Visuals/EnemyModels)
	bossKind: string?, -- unique boss model (nil = a bigger, crowned enemyKind)
	groundColor: Color3,
	groundMaterial: Enum.Material,
	arenaColor: Color3,
	arenaMaterial: Enum.Material,
	mountainColor: Color3,
	enemyColor: Color3,
	bossColor: Color3,
	clockTime: number,
	tint: Color3,
	hazeColor: Color3,
	hazeDensity: number,
	particles: string,
	trait: AreaTrait?,
	bossMoves: { string }, -- "Enrage", "Shield", "Summon"
}

-- What gets saved for each player (ProfileStore Profile.Data).
export type PlayerData = {
	gold: BigNum,
	stage: number,
	highestStage: number, -- highest stage reached THIS run (resets on Ascend)
	bestStage: number, -- highest stage ever reached (never resets; unlocks abilities)
	killsInStage: number,
	autoAdvance: boolean,
	highestBossDefeated: number, -- stage of the highest boss beaten this run (0 = none)
	honor: BigNum,
	honorUpgrades: { [string]: number }, -- Honor upgrade id -> level
	abilityUpgrades: { [string]: number }, -- AbilityConfig.UPGRADES id -> level (bought with Honor)
	lastSeen: number, -- os.time() the server last saw this player (0 = never)
	faction: string, -- faction id, "" = not chosen yet
	factionChangedAt: number, -- os.time() of the last pick/switch (0 = never)
	war: WarRecord, -- this week
	lastWar: WarRecord, -- the previous week this player took part in
	clanId: string, -- "" = not in a clan (a cached copy; the clan record is the truth)
	clanDonation: { dayId: number, amount: number }, -- Supplies donated today
	raid: RaidRecord, -- this player's clan raid week
	purchases: { string }, -- recent Robux purchase ids already granted (newest last)
	daily: { lastClaimDay: number, streak: number }, -- login calendar
	quests: { day: number, list: { QuestState }, rerollsUsed: number, bonusClaimed: boolean },
	achievements: { [string]: string }, -- id -> "unlocked" | "claimed"
	lifetime: { [string]: number }, -- lifetime activity counters (see ActivityService)
	passToggles: { [string]: boolean }, -- toggleable passes switched OFF (missing = on)
	clanWar: ClanWarRecord,
	clanRequest: { clanId: string, at: number }, -- pending join request ("" = none)
	clanTokens: number, -- Clan Tokens for the clan shop (kept on Ascend)
	abilityLoadout: { string }, -- equipped abilities, one per slot (Formulas.loadoutSlots)
	commanderXp: number, -- Commander Level XP (never resets)
	generals: GeneralsData, -- Generals roster (kept forever)
	relics: RelicsData, -- relic inventory (kept on Ascend, turned to Dust on Legacy)
	tutorial: { seen: { [string]: boolean }, initialized: boolean }, -- lessons already shown
	challenge: ChallengeState, -- challenge runs (tiers kept forever)
	expeditions: ExpeditionsData, -- Expeditions (board, teams away)
	tower: { best: number, tributeDay: number }, -- Endless Tower: best floor (kept forever), last Tribute day
	skills: { ranks: { [string]: number }, respecDay: number }, -- skill tree (SkillConfig)
	legacy: LegacyState, -- the second prestige (kept forever)
	clanQuestClaims: { weekId: number, claimed: { [string]: boolean } }, -- quest index -> claimed this week
	settings: { [string]: string }, -- graphics / sound (see SettingsConfig)
	analytics: { onboardingStep: number }, -- last onboarding funnel step sent (AnalyticsService)
	bossWeaken: { stage: number, fails: number }, -- failed attempts in a row on that boss stage
	commander: { owned: { [string]: boolean }, equipped: { [string]: string }, pity: { [string]: number } }, -- commander gear (kept on Ascend)
	troops: TroopCounts,
	gear: GearSet,
	packs: PackState,
	stats: {
		totalKills: number,
		totalTaps: number,
		lifetimeGold: BigNum,
		bossesDefeated: number,
		ascensions: number,
		honorEarned: BigNum,
	},
}

-- Server timestamps (workspace:GetServerTimeNow()) for one ability. 0 = never used.
export type AbilityTimers = {
	readyAt: number,
	activeUntil: number,
}

-- What the server sends a client so it can draw the screen. Display only.
export type Snapshot = {
	gold: BigNum,
	stage: number,
	highestStage: number,
	bestStage: number,
	killsInStage: number,
	enemiesPerStage: number,
	autoAdvance: boolean,

	encounter: EncounterKind,
	enemyHp: BigNum,
	enemyMaxHp: BigNum,
	goldPerKill: BigNum, -- already includes gold multipliers
	bossEndsAt: number, -- server time; 0 when not fighting a boss
	bossDps: BigNum, -- zero when not fighting a boss (already doubled while enraged)
	bossEnraged: boolean,
	bossIntroUntil: number, -- server time; the fight (and timer) starts after the entrance
	bossWeakened: number, -- 0..0.5, how much HP this boss lost from your failed attempts
	bossShieldUntil: number, -- server time; troops can't hurt the boss until then
	minionHp: BigNum, -- summoned minions' remaining HP (zero = none)
	minionMaxHp: BigNum,

	armyDps: BigNum, -- already includes damage multipliers
	tapDamage: BigNum,
	armyHp: BigNum,
	armyMaxHp: BigNum,
	damageMultiplier: number,
	goldMultiplier: number,

	troops: TroopCounts,
	gear: GearSet,
	packs: PackState,
	packPrice: BigNum,
	abilities: { [string]: AbilityTimers },
	totalKills: number,

	honor: BigNum,
	honorUpgrades: { [string]: number },
	abilityUpgrades: { [string]: number },
	ascendHonor: BigNum, -- Honor you'd get for Ascending right now (zero if not allowed)
	ascensions: number,
	abilityLoadout: { string }, -- equipped abilities by slot (keys 1/2/3)
	bountyLeft: number, -- kills left on an active Bounty
	commanderXp: number,
	generals: GeneralsData,
	relicDust: number, -- (the relic inventory itself comes on RelicSync, only when it changes)
	tutorialSeen: { [string]: boolean },
	challengeActive: string, -- challenge id you're in ("" = none)
	challengeTiers: { [string]: number }, -- challenge id -> tiers cleared
	expeditions: ExpeditionsData,
	expeditionSlots: number, -- missions that can be away at once
	towerFloor: number, -- the Tower floor being fought right now (0 = not in the Tower)
	towerBest: number, -- best Tower floor cleared
	towerTributeReady: boolean, -- today's Tower Tribute can be claimed
	skillRanks: { [string]: number },
	respecReady: boolean, -- the free daily respec is available
	enemyGolden: boolean, -- the current enemy is a golden one
	legacyCount: number,
	crowns: number, -- unspent
	crownUpgrades: { [string]: number },
	legacyBest: number, -- best stage this Legacy
	legacyCrowns: number, -- Crowns a Legacy right now would give (0 if not allowed yet)

	faction: string,
	factionSwitchIn: number, -- seconds until you may switch (0 = now)
	warPoints: number,
	warDayPoints: number,
	warActive: boolean,
	warBonusActive: boolean, -- won last week's war: winner gold bonus applies

	raidAttacksLeft: number, -- today
	raidUnitsWeek: number, -- your contribution this raid week
	raidUnitsLive: number, -- units so far in the raid attack you're doing right now
	raidBossId: string, -- the boss of the raid attack in progress ("" when not raiding)

	passToggles: { [string]: boolean },
	settings: { [string]: string }, -- every SettingsConfig key, filled with defaults
	clanTokens: number,
	commander: CommanderView,
}

-- One-off messages from the server, shown as banners.
export type Notice = {
	kind: "BossDefeated" | "BossFailed" | "OfflineEarnings" | "RaidResult" | "RaidRewards" | "Purchase" | "ClanWarRewards" | "CommanderItem" | "ClanJoined" | "Golden" | "LevelUp" | "Relic" | "ChallengeTier" | "ChallengeEnded" | "TowerFloor" | "TowerFailed" | "TowerTribute",
	stage: number,
	reason: ("OutOfTime" | "ArmyDefeated")?,
	firstClear: boolean?, -- true the first time this boss is beaten (grants a free pack)
	-- OfflineEarnings only:
	seconds: number?, -- time counted (after the cap)
	awaySeconds: number?, -- real time away
	gold: BigNum?,
	-- RaidResult / RaidRewards only:
	units: number?,
	tier: number?,
	honor: number?,
	packs: number?,
	-- Purchase only:
	itemName: string?,
	-- CommanderItem: itemName = the new item's name.
	-- ClanWarRewards only (also uses honor / packs):
	rank: number?, -- nil = participation reward
	mvp: boolean?, -- you were your clan's top contributor that week (extra Honor)
	tokens: number?, -- Clan Tokens earned
	headToHead: string?, -- "win" | "bye" | "loss" for that week's head-to-head
	heroChests: number?,
	-- LevelUp only: the new Commander Level (stage = 0).
	level: number?,
	-- Relic only: what dropped, and whether it went straight to Dust (inventory full).
	relic: RelicItem?,
	dust: number?,
	-- ChallengeTier: challengeId, tier (cleared), honor, scrolls, dust (Relic Dust),
	-- heroChests. ChallengeEnded: challengeId, reason "Left" | "Complete" | "Defeated",
	-- gold = held gold rewards paid out.
	challengeId: string?,
	challengeReason: string?,
	-- TowerFloor: stage = the floor cleared, honor, dust, prize (TowerConfig.CHEST_PRIZES id
	-- when the floor had a chest), bonus = true when a permanent bonus step was reached.
	-- TowerFailed: stage = the floor, reason. TowerTribute: stage = best floor, gold, dust.
	prize: string?,
	bonus: boolean?,
	scrolls: number?,
}

export type BuyMode = "One" | "Ten" | "Max"
export type GearBuyMode = "One" | "Max"

export type BuyResult = {
	ok: boolean,
	bought: number,
	reason: string?,
}

-- Server -> client: a weak point appeared ("Spawn") or the fight ended ("Clear").
-- x in [-1, 1], y in [0, 1]: where on the enemy to draw it.
export type WeakPointEvent = {
	kind: "Spawn" | "Clear",
	id: number,
	expiresAt: number, -- server time (workspace:GetServerTimeNow())
	x: number,
	y: number,
}

export type WeakPointResult = {
	ok: boolean,
	reason: string?,
	damage: BigNum?,
	streak: number?, -- hits in a row, including this one
}

export type PackResult = {
	ok: boolean,
	reason: string?,
	troopId: string?,
	slot: GearSlot?,
	rarity: number?, -- what was rolled
	upgraded: boolean?, -- true if the slot's rarity went up
	refund: BigNum?, -- gold refunded for a duplicate
}

export type FactionResult = {
	ok: boolean,
	reason: string?,
}

-- A General (GeneralConfig.GENERALS).
export type GeneralDef = {
	id: string,
	name: string,
	title: string,
	rarity: string, -- "Rare" | "Epic" | "Legendary" | "Mythic"
	passive: { stat: string, value: number }, -- "damage" | "armyHp" | "gold" | "tap"
	trait: { kind: string, troopId: string?, value: number, text: string },
}

-- A tutorial lesson (TutorialConfig).
export type TutorialStep = { text: string, spotlight: string?, open: string? }
export type TutorialLesson = {
	id: string,
	topic: string,
	title: string,
	when: string,
	stage: number,
	steps: { TutorialStep },
}

-- Challenge runs (ChallengeConfig).
export type ChallengeRules = {
	onlyTroop: string?,
	noClicks: boolean?,
	oneLife: boolean?,
	bossTimeScale: number?,
	goldScale: number?,
	noGear: boolean?,
	allBossMoves: boolean?,
	bossHpScale: number?,
	noExtras: boolean?,
}
export type ChallengeDef = {
	id: string,
	name: string,
	rule: string, -- shown to the player
	color: Color3,
	unlockAscends: number,
	rules: ChallengeRules,
	reward: { stat: string, perTier: number, text: string }, -- permanent, per tier cleared
}
export type ChallengeTierReward = { honorShare: number, honor: number, scrolls: number?, relicDust: number?, heroChests: number? }
-- Permanent bonuses from cleared tiers, added up (Formulas.challengeBonuses).
export type ChallengeBonuses = {
	damage: number, -- multipliers
	armyHp: number,
	gold: number,
	tap: number,
	bossDamageDealt: number,
	offline: number,
	xp: number,
	bossTime: number, -- seconds
}
-- The main run, parked while a challenge is on.
export type ChallengeStash = {
	gold: BigNum,
	stage: number,
	highestStage: number,
	killsInStage: number,
	autoAdvance: boolean,
	highestBossDefeated: number,
	rewardedBossStage: number,
	weakenStage: number,
	weakenFails: number,
	troops: TroopCounts,
	gear: GearSet,
}
export type ChallengeState = {
	active: string, -- challenge id, "" = not in one
	tiers: { [string]: number }, -- challenge id -> tiers cleared
	goldMinutes: number, -- gold rewards / purchases held until the main run is back
	stash: ChallengeStash?, -- only while active
}
export type ChallengeResult = { ok: boolean, reason: string? }

-- Expeditions (ExpeditionConfig).
export type ExpeditionDuration = {
	id: string,
	name: string,
	seconds: number,
	power: number, -- recommended team power
	rewards: { [string]: any }, -- reward type -> amount (Relic: minimum rarity name)
}
export type ExpeditionMission = {
	id: number,
	duration: string, -- ExpeditionConfig.DURATIONS id
	reward: string, -- ExpeditionConfig.REWARDS id
	house: string, -- GeneralConfig.HOUSE_ORDER id: its Generals count x HOUSE_BONUS
}
export type ExpeditionRun = {
	mission: ExpeditionMission,
	generals: { string }, -- empty = the Scout Party
	power: number, -- team power when sent
	endsAt: number, -- os.time()
}
export type ExpeditionsData = {
	day: number, -- board day (DailyConfig)
	rerollDay: number, -- last day a reroll was used
	rerolls: number, -- rerolls used that day
	nextId: number,
	board: { ExpeditionMission },
	active: { ExpeditionRun },
}
-- What a returning team brought (ExpeditionRequest "Collect" and the notice).
export type ExpeditionLoot = {
	gold: BigNum?,
	honor: number?,
	dust: number?,
	scrolls: number?,
	heroChests: number?,
	relic: boolean?,
	bonus: string, -- ExpeditionConfig.BONUS id
}
export type ExpeditionResult = { ok: boolean, reason: string?, loot: ExpeditionLoot? }

-- The Endless Tower (TowerConfig).
export type TowerEffects = {
	troopMultiplier: number,
	queuedMultiplier: number,
	troopDamage: { [string]: number },
	regen: number,
	bossDamage: number,
	timeScale: number,
	noClicks: boolean,
	noAbilities: boolean,
	weakPointGap: number,
}
export type TowerLawDef = {
	id: string,
	name: string,
	text: string,
	effects: {
		troopMultiplier: number?,
		queuedMultiplier: number?,
		troopDamage: { [string]: number }?,
		regen: number?,
		bossDamage: number?,
		timeScale: number?,
		noClicks: boolean?,
		noAbilities: boolean?,
		weakPointGap: number?,
	},
}
export type TowerPrizeDef = { id: string, weight: number, text: string, scrolls: number?, heroChests: number? }
-- One floor, worked out from its number (Formulas.towerFloor).
export type TowerFloor = {
	floor: number,
	stage: number, -- about as tough as this stage's boss
	guardian: boolean,
	chest: boolean,
	laws: { string }, -- TowerConfig.LAWS ids
	effects: TowerEffects, -- the laws added up
	model: string, -- EnemyModels kind
}
export type TowerResult = { ok: boolean, reason: string? }

-- Relics (RelicConfig).
export type RelicSetDef = {
	id: string,
	name: string,
	color: Color3,
	bonuses: { [number]: { text: string, effects: { [string]: number } } }, -- at 2 / 4 / 6 pieces
}
export type RelicLine = { stat: string, roll: number } -- roll = the rarity range factor rolled
export type RelicItem = {
	id: string,
	slot: string,
	set: string,
	rarity: string,
	level: number,
	lines: { RelicLine },
	locked: boolean, -- locked relics can't be salvaged
}
export type RelicsData = {
	items: { [string]: RelicItem },
	equipped: { [string]: string }, -- slot -> relic id
	dust: number,
	nextId: number,
	pity: { sinceLegendary: number, sinceMythic: number },
}
-- What the equipped relics add up to (Formulas.relicBonuses).
export type RelicBonuses = {
	damage: number, -- multipliers (1 = none)
	armyHp: number,
	gold: number,
	tap: number,
	bossDamageDealt: number, -- multiplier vs bosses and raids
	bossDamage: number, -- multiplier on boss damage to you
	critChance: number, -- added
	critMultiplier: number,
	bossTime: number,
	goldenChance: number,
	sets: { { setId: string, count: number } },
}
-- Crit / boss timer / golden enemy bonuses from skills + Generals + relics together.
export type ExtraEffects = { critChance: number, critMultiplier: number, bossTime: number, goldenChance: number }

-- A House: fielding 2-3 of its members gives a set bonus (GeneralConfig.HOUSES).
export type GeneralHouseDef = {
	id: string,
	name: string,
	color: Color3,
	members: { string },
	bonuses: { [number]: { text: string, effects: { [string]: number } } },
}

-- One General you own.
export type GeneralState = { stars: number, level: number, copies: number }

export type GeneralsData = {
	owned: { [string]: GeneralState },
	fielded: { string }, -- up to GeneralConfig.FIELD_SLOTS ids ("" = empty slot)
	scrolls: number, -- Recruit Scrolls
	shards: number, -- from extra copies; SHARDS_PER_SCROLL = 1 scroll
	pity: { sinceLegendary: number, sinceMythic: number },
	welcomed: boolean, -- got the FIRST_SCROLLS gift
}

-- Everything fielded Generals add up to (Formulas.generalBonuses).
export type GeneralBonuses = {
	damage: number, -- multipliers (1 = none)
	armyHp: number,
	gold: number,
	tap: number,
	bossDamage: number, -- multiplier on boss damage to your army
	troopDamage: { [string]: number }, -- per troop type multipliers
	troopHp: { [string]: number },
	critChance: number, -- added
	critMultiplier: number, -- added to the crit multiplier
	bossTime: number, -- added seconds
	goldenChance: number, -- added to the golden chance multiplier (0.4 = x1.4)
	sets: { { houseId: string, count: number, power: number } }, -- active set bonuses
}

export type RecruitResult = {
	ok: boolean,
	reason: string?,
	results: { { id: string, isNew: boolean, stars: number, shards: number } }?,
}

-- One node of the skill tree (SkillConfig.NODES).
export type SkillNodeDef = {
	id: string,
	branch: string, -- "Warlord" | "Quartermaster" | "Tactician"
	tier: number, -- needs SkillConfig.TIER_POINTS[tier] points spent in the branch
	order: number, -- position within the tier
	fork: string?, -- nodes sharing a fork id are pick-one
	displayName: string,
	description: string,
	maxRank: number,
	cost: number, -- skill points per rank
	effects: { [string]: number }, -- per rank (see SkillConfig header)
}

-- Every skill effect added up (Formulas.skillEffects). Missing = 0.
export type SkillEffects = {
	damage: number,
	armyHp: number,
	gold: number,
	tap: number,
	bossDamageDealt: number,
	bossDamageTaken: number,
	bossTime: number,
	bossGold: number,
	critChance: number,
	critMultiplier: number,
	goldenChance: number,
	goldenGold: number,
	offlineHours: number,
	offlineEfficiency: number,
	ascendHonor: number,
	abilityCooldown: number,
	abilityDuration: number,
	weakPointDamage: number,
	extraSlots: number,
	lastStand: number,
}

export type CrownUpgradeDef = {
	id: string,
	displayName: string,
	description: string,
	baseCost: number, -- Crowns
	costGrowth: number,
	maxLevel: number?,
	stat: string, -- "damage" | "armyHp" | "gold" | "ascendHonor"
	multiplier: number, -- per level
}

-- What a player keeps across Legacies (and what this Legacy has done so far).
export type LegacyState = {
	count: number, -- Legacies done
	crowns: number, -- unspent
	crownsEarned: number, -- all-time
	upgrades: { [string]: number }, -- Crown upgrade levels
	best: number, -- best stage reached during this Legacy (needs LegacyConfig.MIN_STAGE)
	honorAtStart: BigNum, -- stats.honorEarned when this Legacy began
}

export type LegacyResult = {
	ok: boolean,
	reason: string?,
	crowns: number?, -- Crowns gained
}

export type AscendResult = {
	ok: boolean,
	reason: string?,
	honor: BigNum?, -- Honor gained
}

export type LeaderboardEntry = { name: string, value: number }

-- Global top lists (LeaderboardSync remote).
export type Leaderboards = {
	bestStage: { LeaderboardEntry },
	honor: { LeaderboardEntry },
	tower: { LeaderboardEntry },
}

export type SoundDef = { id: string, volume: number }

-- A reward bundle (login calendar, quest bonus). Any mix of these.
export type RewardDef = {
	goldMinutes: number?,
	packs: number?,
	heroChests: number?,
	honor: number?, -- flat Honor (the minimum when honorShare is set)
	honorShare: number?, -- share of an Ascend's Honor at your best stage (Formulas.scaledHonor)
	scrolls: number?, -- Recruit Scrolls for Generals
}

export type QuestDef = {
	key: string,
	activity: string, -- ActivityService activity that counts toward it
	text: string, -- "{n}" is replaced by the target
	targets: { number }, -- one per difficulty
	minutes: { number }, -- gold reward (minutes of income) per difficulty
	requires: string?,
}

-- One of today's quests (saved).
export type QuestState = {
	key: string,
	difficulty: number,
	target: number,
	progress: number,
	claimed: boolean,
}

export type AchievementDef = {
	id: string,
	name: string,
	description: string,
	honor: number, -- minimum Honor (what you get before stage 50)
	honorShare: number, -- share of an Ascend's Honor at your best stage
	kind: string,
	key: string?,
	target: number,
}

-- Sent to the client (ProgressSync remote).
export type ProgressView = {
	studioTestMode: boolean,
	secondsToNextDay: number,
	login: { canClaim: boolean, nextIndex: number, streak: number },
	quests: { QuestState },
	rerollsLeft: number,
	bonusClaimed: boolean,
	achievements: { [string]: { current: number, status: "locked" | "unlocked" | "claimed" } },
}

export type PassDef = {
	key: string,
	id: number, -- Roblox game pass id (0 = not set up yet, hidden)
	displayName: string,
	description: string,
	goldMultiplier: number?,
	toggleable: boolean?, -- owner can switch the effect on/off in the store
	autoClicksPerSecond: number?,
}

export type ProductDef = {
	key: string,
	id: number, -- Roblox developer product id (0 = not set up yet, hidden)
	displayName: string,
	description: string,
	goldMinutes: number?, -- gives this many minutes of your army's gold
	forgeTokens: number?, -- gives this many Epic Forge tokens
}

-- ModuleScripts must return a value; this module only exists for its types.
return {}
