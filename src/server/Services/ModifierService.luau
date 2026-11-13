--!strict
-- One place that combines every bonus multiplier a player has.
--
-- Systems that grant bonuses register a "source" function. Right now that's just
-- AbilityService (Rally, Plunder). Later phases add Honor upgrades, faction and clan
-- perks, and gear here too, so combat code never needs to know where bonuses come from.
-- All sources are multiplied together.

export type Modifiers = {
	damage: number, -- troop + click damage
	gold: number, -- gold from kills
	armyHp: number, -- army HP in boss fights
}

export type PartialModifiers = {
	damage: number?,
	gold: number?,
	armyHp: number?,
}

type Source = (player: Player) -> PartialModifiers?

local sources: { Source } = {}

local ModifierService = {}

function ModifierService.register(source: Source)
	table.insert(sources, source)
end

function ModifierService.get(player: Player): Modifiers
	local result: Modifiers = { damage = 1, gold = 1, armyHp = 1 }
	for _, source in sources do
		local partial = source(player)
		if partial ~= nil then
			result.damage *= partial.damage or 1
			result.gold *= partial.gold or 1
			result.armyHp *= partial.armyHp or 1
		end
	end
	return result
end

return ModifierService
