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
	ORDER = { "Swordsman", "Archer", "Knight", "Mage", "Cavalry", "Siege" } :: { TroopId },

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
		-- Later troops unlock by all-time best stage and have a job against certain enemies.
		Mage = {
			id = "Mage",
			displayName = "Mage",
			role = "x2 damage to bosses. Very fragile.",
			baseCost = 20000,
			costGrowth = 1.10,
			-- Balance pass (tools/balance_v2.py): was 90 dps / 60 hp, weaker than Knights
			-- against bosses at the stages it unlocks for.
			baseDps = 300,
			baseHp = 200,
			color = Color3.fromRGB(150, 90, 220),
			unlockStage = 30,
			bossMultiplier = 2,
		},
		Cavalry = {
			id = "Cavalry",
			displayName = "Cavalry",
			role = "x1.5 damage to normal enemies. Sturdy.",
			baseCost = 1500000,
			costGrowth = 1.11,
			baseDps = 4000,
			baseHp = 30000,
			color = Color3.fromRGB(190, 140, 70),
			unlockStage = 60,
			normalMultiplier = 1.5,
		},
		Siege = {
			id = "Siege",
			displayName = "Siege Engine",
			role = "x2 damage to bosses. Fragile.",
			baseCost = 100000000,
			costGrowth = 1.12,
			-- Balance pass (tools/balance_v2.py): was 500,000 dps / 50 hp / x3 vs bosses,
			-- which grew to ~270x Cavalry's damage and left armies with no HP. Now it ends
			-- up around 3-5x Cavalry vs bosses and has some HP.
			baseDps = 11000,
			baseHp = 4000,
			color = Color3.fromRGB(120, 100, 85),
			unlockStage = 100,
			bossMultiplier = 2,
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
