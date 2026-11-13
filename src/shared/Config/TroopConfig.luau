--!strict
-- Troop types and how they scale. Safe to tweak any number here.
--
-- Cost of the Nth troop of a type = baseCost * costGrowth ^ (owned)
-- DPS of a type = count * baseDps * milestone multiplier
-- HP of a type  = count * baseHp * milestone multiplier (HP only matters against bosses)

local Types = require(script.Parent.Parent.Types)

type TroopId = Types.TroopId
type TroopDef = Types.TroopDef

local TroopConfig = {
	-- Display order in the shop and on the battlefield.
	ORDER = { "Swordsman", "Archer", "Knight" } :: { TroopId },

	TROOPS = {
		Swordsman = {
			id = "Swordsman",
			displayName = "Swordsman",
			role = "Cheap, steady. Scales with numbers.",
			baseCost = 10,
			costGrowth = 1.07,
			baseDps = 1,
			baseHp = 12,
			color = Color3.fromRGB(200, 70, 60),
		},
		Archer = {
			id = "Archer",
			displayName = "Archer",
			role = "High damage, fragile vs bosses.",
			baseCost = 100,
			costGrowth = 1.08,
			baseDps = 10,
			baseHp = 25,
			color = Color3.fromRGB(80, 170, 90),
		},
		Knight = {
			id = "Knight",
			displayName = "Knight",
			role = "Tank. Huge HP for boss fights.",
			baseCost = 1500,
			costGrowth = 1.09,
			baseDps = 110,
			baseHp = 2600,
			color = Color3.fromRGB(80, 120, 210),
		},
	} :: { [string]: TroopDef },

	-- Owning this many of one type multiplies that type's damage AND HP by MILESTONE_MULTIPLIER.
	-- After the last listed milestone, another one happens every MILESTONE_REPEAT_EVERY troops.
	MILESTONES = { 25, 50, 100, 200, 300, 400, 500 } :: { number },
	MILESTONE_REPEAT_EVERY = 100,
	MILESTONE_MULTIPLIER = 2,

	-- Safety limits.
	MAX_PER_TYPE = 100000,
	MAX_BUY_PER_REQUEST = 1000,
}

return table.freeze(TroopConfig)
