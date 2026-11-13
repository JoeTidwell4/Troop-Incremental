--!strict
-- Shared type definitions. No logic lives here.

local BigNum = require(script.Parent.BigNum)

export type BigNum = BigNum.BigNum

export type TroopId = "Swordsman" | "Archer" | "Knight"

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
	color: Color3, -- visual only
}

-- What gets saved for each player (ProfileStore Profile.Data).
export type PlayerData = {
	gold: BigNum,
	stage: number,
	highestStage: number,
	killsInStage: number,
	troops: TroopCounts,
	stats: {
		totalKills: number,
		totalTaps: number,
		lifetimeGold: BigNum,
	},
}

-- What the server sends a client so it can draw the screen. Display only.
export type Snapshot = {
	gold: BigNum,
	stage: number,
	highestStage: number,
	killsInStage: number,
	enemiesPerStage: number,
	enemyHp: BigNum,
	enemyMaxHp: BigNum,
	goldPerKill: BigNum,
	armyDps: BigNum,
	tapDamage: BigNum,
	troops: TroopCounts,
	totalKills: number,
}

export type BuyMode = "One" | "Ten" | "Max"

export type BuyResult = {
	ok: boolean,
	bought: number,
	reason: string?,
}

-- ModuleScripts must return a value; this module only exists for its types.
return {}
