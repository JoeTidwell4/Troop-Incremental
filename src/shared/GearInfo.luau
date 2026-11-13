--!strict
-- Display helpers for gear: names like "Rare Steel Bow" and rarity info.

local Shared = script.Parent
local Types = require(Shared.Types)
local GearConfig = require(Shared.Config.GearConfig)
local TroopConfig = require(Shared.Config.TroopConfig)

local GearInfo = {}

function GearInfo.rarity(index: number): Types.RarityDef
	return GearConfig.RARITIES[math.clamp(index, 1, #GearConfig.RARITIES)]
end

function GearInfo.tierName(level: number): string
	local tier = level // GearConfig.TIER_EVERY + 1
	return GearConfig.TIERS[math.min(tier, #GearConfig.TIERS)]
end

-- e.g. "Rare Steel Bow"
function GearInfo.itemName(troopId: string, slot: string, state: Types.GearSlotState): string
	local names = GearConfig.ITEM_NAMES[slot]
	local item = if names ~= nil then names[troopId] or slot else slot
	return `{GearInfo.rarity(state.rarity).name} {GearInfo.tierName(state.level)} {item}`
end

-- e.g. "Archer Weapon"
function GearInfo.slotLabel(troopId: string, slot: string): string
	local troop = TroopConfig.TROOPS[troopId]
	local info = GearConfig.SLOT_INFO[slot]
	local troopName = if troop ~= nil then troop.displayName else troopId
	local slotName = if info ~= nil then info.displayName else slot
	return `{troopName} {slotName}`
end

return table.freeze(GearInfo)
