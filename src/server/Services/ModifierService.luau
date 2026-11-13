--!strict
-- One place that combines every bonus multiplier a player has.
--
-- Systems that grant bonuses register a "source" function: AbilityService (Rally, Plunder)
-- and HonorService (Honor upgrades). Faction and clan perks plug in here later, so combat
-- code never needs to know where bonuses come from. (Gear is per troop type, so it's
-- applied in Formulas.troopDps/troopHp instead.)
-- All sources are multiplied together.

export type Modifiers = {
	damage: number, -- troop + click damage
	gold: number, -- gold from kills
	armyHp: number, -- army HP in boss fights
	tap: number, -- click damage only (on top of damage)
}

export type PartialModifiers = {
	damage: number?,
	gold: number?,
	armyHp: number?,
	tap: number?,
}

type Source = (player: Player) -> PartialModifiers?

local sources: { Source } = {}

local ModifierService = {}

function ModifierService.register(source: Source)
	table.insert(sources, source)
end

function ModifierService.get(player: Player): Modifiers
	local result: Modifiers = { damage = 1, gold = 1, armyHp = 1, tap = 1 }
	for _, source in sources do
		local partial = source(player)
		if partial ~= nil then
			result.damage *= partial.damage or 1
			result.gold *= partial.gold or 1
			result.armyHp *= partial.armyHp or 1
			result.tap *= partial.tap or 1
		end
	end
	return result
end

return ModifierService
