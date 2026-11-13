--!strict
-- Shared type definitions. No logic lives here.

local BigNum = require(script.Parent.BigNum)

export type BigNum = BigNum.BigNum

export type TroopId = "Swordsman" | "Archer" | "Knight"
export type AbilityId = "Rally" | "Barrage" | "Plunder"
export type EncounterKind = "Normal" | "Boss"
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
}

-- One-off messages from the server, shown as banners.
export type Notice = {
	kind: "BossDefeated" | "BossFailed" | "OfflineEarnings",
	stage: number,
	reason: ("OutOfTime" | "ArmyDefeated")?,
	firstClear: boolean?, -- true the first time this boss is beaten (grants a free pack)
	-- OfflineEarnings only:
	seconds: number?, -- time counted (after the cap)
	awaySeconds: number?, -- real time away
	gold: BigNum?,
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

export type AscendResult = {
	ok: boolean,
	reason: string?,
	honor: BigNum?, -- Honor gained
}

-- ModuleScripts must return a value; this module only exists for its types.
return {}
