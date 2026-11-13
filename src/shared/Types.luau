--!strict
-- Shared type definitions. No logic lives here.

local BigNum = require(script.Parent.BigNum)

export type BigNum = BigNum.BigNum

export type TroopId = "Swordsman" | "Archer" | "Knight"
export type AbilityId = "Rally" | "Barrage" | "Plunder"
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
	key: Enum.KeyCode, -- keyboard shortcut (visual/client only)
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

export type PackState = {
	free: number, -- unopened free packs
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
}

export type ClanResult = {
	ok: boolean,
	reason: string?,
	clans: { ClanSummary }?,
}

export type AreaTheme = {
	name: string,
	bossName: string,
	groundColor: Color3,
	groundMaterial: Enum.Material,
	enemyColor: Color3,
	bossColor: Color3,
	enemyShape: Enum.PartType,
	clockTime: number,
	tint: Color3,
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
	lastSeen: number, -- os.time() the server last saw this player (0 = never)
	faction: string, -- faction id, "" = not chosen yet
	factionChangedAt: number, -- os.time() of the last pick/switch (0 = never)
	war: WarRecord, -- this week
	lastWar: WarRecord, -- the previous week this player took part in
	clanId: string, -- "" = not in a clan (a cached copy; the clan record is the truth)
	clanDonation: { dayId: number, amount: number }, -- Supplies donated today
	raid: RaidRecord, -- this player's clan raid week
	purchases: { string }, -- recent Robux purchase ids already granted (newest last)
	autoAbilities: boolean, -- Auto Abilities pass: on/off
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
	bossDps: BigNum, -- zero when not fighting a boss

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
	ascendHonor: BigNum, -- Honor you'd get for Ascending right now (zero if not allowed)
	ascensions: number,

	faction: string,
	factionSwitchIn: number, -- seconds until you may switch (0 = now)
	warPoints: number,
	warDayPoints: number,
	warActive: boolean,
	warBonusActive: boolean, -- won last week's war: winner gold bonus applies

	raidAttacksLeft: number, -- today
	raidUnitsWeek: number, -- your contribution this raid week
	raidUnitsLive: number, -- units so far in the raid attack you're doing right now

	autoAbilities: boolean,
}

-- One-off messages from the server, shown as banners.
export type Notice = {
	kind: "BossDefeated" | "BossFailed" | "OfflineEarnings" | "RaidResult" | "RaidRewards" | "Purchase",
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
}

export type BuyMode = "One" | "Ten" | "Max"
export type GearBuyMode = "One" | "Max"

export type BuyResult = {
	ok: boolean,
	bought: number,
	reason: string?,
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
}

export type SoundDef = { id: string, volume: number }

export type PassDef = {
	key: string,
	id: number, -- Roblox game pass id (0 = not set up yet, hidden)
	displayName: string,
	description: string,
	goldMultiplier: number?,
}

export type ProductDef = {
	key: string,
	id: number, -- Roblox developer product id (0 = not set up yet, hidden)
	displayName: string,
	description: string,
	goldMinutes: number?, -- gives this many minutes of your army's gold
}

-- ModuleScripts must return a value; this module only exists for its types.
return {}
