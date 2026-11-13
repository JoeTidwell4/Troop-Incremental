--!strict
-- What a brand-new player's save looks like. When you add a field here, existing
-- players get it automatically on their next join (ProfileStore Reconcile).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local EconomyConfig = require(Shared:WaitForChild("Config"):WaitForChild("EconomyConfig"))

local function newGear(): Types.TroopGear
	return {
		weapon = { level = 0, rarity = 1 },
		armor = { level = 0, rarity = 1 },
	}
end

local template: Types.PlayerData = {
	gold = BigNum.fromNumber(EconomyConfig.STARTING_GOLD),
	stage = 1,
	highestStage = 1,
	killsInStage = 0,
	autoAdvance = true,
	highestBossDefeated = 0,
	troops = {
		Swordsman = 0,
		Archer = 0,
		Knight = 0,
	},
	gear = {
		Swordsman = newGear(),
		Archer = newGear(),
		Knight = newGear(),
	},
	packs = {
		free = 0,
		sinceEpic = 0,
		opened = 0,
		rewardedBossStage = 0,
	},
	stats = {
		totalKills = 0,
		totalTaps = 0,
		lifetimeGold = BigNum.ZERO,
		bossesDefeated = 0,
	},
}

return template
