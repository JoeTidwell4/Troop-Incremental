--!strict
-- Pure game math. The server uses these to decide outcomes; the client uses the same
-- functions only to DISPLAY costs and previews. The server never trusts client math.

local Shared = script.Parent
local BigNum = require(Shared.BigNum)
local Types = require(Shared.Types)
local TroopConfig = require(Shared.Config.TroopConfig)
local StageConfig = require(Shared.Config.StageConfig)
local CombatConfig = require(Shared.Config.CombatConfig)

type BigNum = BigNum.BigNum
type TroopCounts = Types.TroopCounts

local Formulas = {}

local function getTroop(troopId: string): Types.TroopDef
	local def = TroopConfig.TROOPS[troopId]
	if def == nil then
		error(`Unknown troop id: {troopId}`, 3)
	end
	return def
end

-- How many damage milestones a troop count has reached.
function Formulas.milestonesReached(count: number): number
	local reached = 0
	for _, threshold in TroopConfig.MILESTONES do
		if count >= threshold then
			reached += 1
		end
	end
	local last = TroopConfig.MILESTONES[#TroopConfig.MILESTONES]
	if count >= last + TroopConfig.MILESTONE_REPEAT_EVERY then
		reached += (count - last) // TroopConfig.MILESTONE_REPEAT_EVERY
	end
	return reached
end

-- The next count that triggers a milestone, e.g. 25 when you own 12.
function Formulas.nextMilestone(count: number): number
	for _, threshold in TroopConfig.MILESTONES do
		if count < threshold then
			return threshold
		end
	end
	local last = TroopConfig.MILESTONES[#TroopConfig.MILESTONES]
	local every = TroopConfig.MILESTONE_REPEAT_EVERY
	return last + ((count - last) // every + 1) * every
end

function Formulas.milestoneMultiplier(count: number): BigNum
	return BigNum.powNumber(TroopConfig.MILESTONE_MULTIPLIER, Formulas.milestonesReached(count))
end

-- Total DPS of all troops of one type.
function Formulas.troopDps(troopId: string, count: number): BigNum
	if count <= 0 then
		return BigNum.ZERO
	end
	local def = getTroop(troopId)
	return BigNum.mul(BigNum.fromNumber(count * def.baseDps), Formulas.milestoneMultiplier(count))
end

function Formulas.armyDps(troops: TroopCounts): BigNum
	local total = BigNum.ZERO
	for _, troopId in TroopConfig.ORDER do
		total = BigNum.add(total, Formulas.troopDps(troopId, troops[troopId] or 0))
	end
	return total
end

-- Gold cost to buy `amount` more troops when you already own `owned`.
-- Geometric series: baseCost * growth^owned * (growth^amount - 1) / (growth - 1)
-- Rounded to whole gold so floating point error can't make an exact price
-- (e.g. 1499.9999 vs 1500) unaffordable.
function Formulas.troopCost(troopId: string, owned: number, amount: number): BigNum
	if amount <= 0 then
		return BigNum.ZERO
	end
	local def = getTroop(troopId)
	local growth = def.costGrowth
	local firstCost = BigNum.mulNumber(BigNum.powNumber(growth, owned), def.baseCost)
	local seriesFactor = BigNum.sub(BigNum.powNumber(growth, amount), BigNum.ONE)
	return BigNum.round(BigNum.div(BigNum.mul(firstCost, seriesFactor), BigNum.fromNumber(growth - 1)))
end

-- How many troops `gold` can buy right now (up to `cap`), and what that costs.
function Formulas.maxAffordable(troopId: string, owned: number, gold: BigNum, cap: number): (number, BigNum)
	if cap <= 0 then
		return 0, BigNum.ZERO
	end
	local def = getTroop(troopId)
	local growth = def.costGrowth
	local firstCost = BigNum.mulNumber(BigNum.powNumber(growth, owned), def.baseCost)
	if BigNum.lt(gold, firstCost) then
		return 0, BigNum.ZERO
	end

	-- Invert the geometric series: n = floor(log_growth(gold * (growth - 1) / firstCost + 1))
	local ratio = BigNum.div(BigNum.mulNumber(gold, growth - 1), firstCost)
	local estimate = BigNum.log10(BigNum.add(ratio, BigNum.ONE)) / math.log10(growth)
	local count = math.clamp(math.floor(estimate), 0, cap)

	-- Floating point can overshoot by one; step down until it's actually affordable.
	local cost = Formulas.troopCost(troopId, owned, count)
	while count > 0 and BigNum.gt(cost, gold) do
		count -= 1
		cost = Formulas.troopCost(troopId, owned, count)
	end
	return count, cost
end

function Formulas.enemyHp(stage: number): BigNum
	return BigNum.mulNumber(BigNum.powNumber(StageConfig.ENEMY_HP_GROWTH, stage - 1), StageConfig.ENEMY_HP_BASE)
end

function Formulas.goldPerKill(stage: number): BigNum
	return BigNum.mulNumber(BigNum.powNumber(StageConfig.GOLD_GROWTH, stage - 1), StageConfig.GOLD_BASE)
end

function Formulas.tapDamage(armyDps: BigNum): BigNum
	return BigNum.add(
		BigNum.fromNumber(CombatConfig.TAP_FLAT_DAMAGE),
		BigNum.mulNumber(armyDps, CombatConfig.TAP_ARMY_DPS_FRACTION)
	)
end

return table.freeze(Formulas)
