--!strict
-- Pure game math. The server uses these to decide outcomes; the client uses the same
-- functions only to DISPLAY costs and previews. The server never trusts client math.

local Shared = script.Parent
local BigNum = require(Shared.BigNum)
local Types = require(Shared.Types)
local TroopConfig = require(Shared.Config.TroopConfig)
local StageConfig = require(Shared.Config.StageConfig)
local CombatConfig = require(Shared.Config.CombatConfig)
local BossConfig = require(Shared.Config.BossConfig)
local GearConfig = require(Shared.Config.GearConfig)
local PackConfig = require(Shared.Config.PackConfig)
local AscendConfig = require(Shared.Config.AscendConfig)
local HonorConfig = require(Shared.Config.HonorConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local FactionConfig = require(Shared.Config.FactionConfig)
local ClanConfig = require(Shared.Config.ClanConfig)
local RaidConfig = require(Shared.Config.RaidConfig)
local Areas = require(Shared.Areas)

type BigNum = BigNum.BigNum
type TroopCounts = Types.TroopCounts
type GearSet = Types.GearSet
type GearSlotState = Types.GearSlotState

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

---------------------------------------------------------------- gear

-- Multiplier from a gear slot's level alone (no rarity).
function Formulas.gearLevelEffect(level: number): number
	return (1 + GearConfig.EFFECT_PER_LEVEL * level) * GearConfig.TIER_MULTIPLIER ^ (level // GearConfig.TIER_EVERY)
end

function Formulas.rarityMultiplier(rarity: number): number
	local def = GearConfig.RARITIES[rarity]
	return if def ~= nil then def.multiplier else 1
end

-- Full multiplier from one gear slot (level and rarity). Missing gear counts as x1.
function Formulas.gearMultiplier(slot: GearSlotState?): number
	if slot == nil then
		return 1
	end
	return Formulas.gearLevelEffect(slot.level) * Formulas.rarityMultiplier(slot.rarity)
end

-- Gold cost to raise a gear slot from `level` to `level + 1`. Rounded to whole gold.
function Formulas.gearUpgradeCost(troopId: string, level: number): BigNum
	local def = getTroop(troopId)
	local cost = BigNum.mulNumber(
		BigNum.powNumber(GearConfig.COST_GROWTH, level),
		def.baseCost * GearConfig.BASE_COST_MULTIPLIER
	)
	return BigNum.round(cost)
end

-- How many levels `gold` can buy (up to `cap`), and the total cost.
function Formulas.gearMaxAffordable(troopId: string, level: number, gold: BigNum, cap: number): (number, BigNum)
	local count = 0
	local total = BigNum.ZERO
	while count < cap do
		local nextTotal = BigNum.add(total, Formulas.gearUpgradeCost(troopId, level + count))
		if BigNum.gt(nextTotal, gold) then
			break
		end
		total = nextTotal
		count += 1
	end
	return count, total
end

-- Gold price of a pack tier ("Basic" | "Elite" | "Royal"; default Basic).
function Formulas.packPrice(highestStage: number, tierId: string?): BigNum
	local tier = PackConfig.TIERS[tierId or "Basic"] or PackConfig.TIERS.Basic
	return BigNum.round(BigNum.mulNumber(Formulas.goldPerKill(highestStage), tier.priceInKills))
end

---------------------------------------------------------------- army

-- Per-troop-type multipliers from your faction (damage and HP), e.g. { Swordsman = 1.5 }.
export type TroopMultipliers = { [string]: number }

function Formulas.troopUnlocked(troopId: string, bestStage: number): boolean
	local def = TroopConfig.TROOPS[troopId]
	return def ~= nil and bestStage >= (def.unlockStage or 0)
end

-- Per-troop DAMAGE multipliers for a fight: faction bonus x the area's trait x each
-- troop's job (bosses vs normal enemies). HP only uses the faction bonus.
function Formulas.fightDamageMultipliers(factionId: string, stage: number, vsBoss: boolean): TroopMultipliers
	local result = Formulas.factionTroopMultipliers(factionId)
	local trait = Areas.forStage(stage).theme.trait
	for _, troopId in TroopConfig.ORDER do
		local def = TroopConfig.TROOPS[troopId]
		local multiplier = result[troopId] or 1
		multiplier *= if vsBoss then def.bossMultiplier or 1 else def.normalMultiplier or 1
		if trait ~= nil and trait.troopId == troopId then
			multiplier *= trait.damageMultiplier
		end
		result[troopId] = multiplier
	end
	return result
end

function Formulas.factionTroopMultipliers(factionId: string): TroopMultipliers
	local def = FactionConfig.FACTIONS[factionId]
	if def == nil then
		return {}
	end
	return { [def.troopId] = FactionConfig.TROOP_BONUS }
end

-- Total DPS of all troops of one type, including that type's weapon and faction bonus.
function Formulas.troopDps(troopId: string, count: number, gear: GearSet?, troopMultipliers: TroopMultipliers?): BigNum
	if count <= 0 then
		return BigNum.ZERO
	end
	local def = getTroop(troopId)
	local troopGear = if gear ~= nil then gear[troopId] else nil
	local weapon = Formulas.gearMultiplier(if troopGear ~= nil then troopGear.weapon else nil)
	local bonus = if troopMultipliers ~= nil then troopMultipliers[troopId] or 1 else 1
	return BigNum.mul(BigNum.fromNumber(count * def.baseDps * weapon * bonus), Formulas.milestoneMultiplier(count))
end

-- Army DPS before any temporary or global multipliers (abilities etc. are applied by the server).
function Formulas.armyDps(troops: TroopCounts, gear: GearSet?, troopMultipliers: TroopMultipliers?): BigNum
	local total = BigNum.ZERO
	for _, troopId in TroopConfig.ORDER do
		total = BigNum.add(total, Formulas.troopDps(troopId, troops[troopId] or 0, gear, troopMultipliers))
	end
	return total
end

-- Total HP of all troops of one type, including that type's armor and faction bonus.
function Formulas.troopHp(troopId: string, count: number, gear: GearSet?, troopMultipliers: TroopMultipliers?): BigNum
	if count <= 0 then
		return BigNum.ZERO
	end
	local def = getTroop(troopId)
	local troopGear = if gear ~= nil then gear[troopId] else nil
	local armor = Formulas.gearMultiplier(if troopGear ~= nil then troopGear.armor else nil)
	local bonus = if troopMultipliers ~= nil then troopMultipliers[troopId] or 1 else 1
	return BigNum.mul(BigNum.fromNumber(count * def.baseHp * armor * bonus), Formulas.milestoneMultiplier(count))
end

-- Army HP before global multipliers. Only used in boss fights.
function Formulas.armyHp(troops: TroopCounts, gear: GearSet?, troopMultipliers: TroopMultipliers?): BigNum
	local total = BigNum.ZERO
	for _, troopId in TroopConfig.ORDER do
		total = BigNum.add(total, Formulas.troopHp(troopId, troops[troopId] or 0, gear, troopMultipliers))
	end
	return total
end

---------------------------------------------------------------- clans

-- Gold cost of one Supply: one kill's worth of gold at your best stage this run.
function Formulas.goldPerSupply(highestStage: number): BigNum
	return BigNum.round(Formulas.goldPerKill(highestStage))
end

function Formulas.clanPerkCost(perkId: string, level: number): number
	local def = ClanConfig.PERKS[perkId]
	if def == nil then
		error(`Unknown clan perk: {perkId}`, 2)
	end
	return math.floor(def.baseCost * def.costGrowth ^ level + 0.5)
end

function Formulas.clanDay(unixTime: number): number
	return unixTime // ClanConfig.DONATION_DAY_SECONDS
end

---------------------------------------------------------------- clan levels + clan war

-- Clan level from lifetime XP. Returns (level, xp into this level, xp needed for the next;
-- 0 at max level).
function Formulas.clanLevel(xp: number): (number, number, number)
	local level = 1
	local remaining = math.max(0, xp)
	while level < ClanConfig.MAX_LEVEL do
		local need = math.floor(ClanConfig.LEVEL_XP_BASE * ClanConfig.LEVEL_XP_GROWTH ^ (level - 1))
		if remaining < need then
			return level, remaining, need
		end
		remaining -= need
		level += 1
	end
	return level, 0, 0
end

-- Gold and damage multipliers every member gets from their clan's level.
function Formulas.clanLevelBonus(level: number): (number, number)
	return 1 + ClanConfig.LEVEL_GOLD_BONUS * level, 1 + ClanConfig.LEVEL_DAMAGE_BONUS * level
end

function Formulas.clanWarWeek(unixTime: number): number
	return (unixTime - ClanConfig.WAR_WEEK_ANCHOR) // ClanConfig.WAR_WEEK_SECONDS
end

function Formulas.clanWarWeekStart(weekId: number): number
	return ClanConfig.WAR_WEEK_ANCHOR + weekId * ClanConfig.WAR_WEEK_SECONDS
end

-- The Clan War reward for a final rank (nil rank or off the board = none here; the
-- participation reward is checked separately).
function Formulas.clanWarReward(rank: number?): { honor: number?, heroChests: number?, packs: number? }?
	if rank == nil then
		return nil
	end
	for _, tier in ClanConfig.WAR_REWARDS do
		if rank <= tier.maxRank then
			return tier
		end
	end
	return nil
end

---------------------------------------------------------------- clan raid

function Formulas.raidWeek(unixTime: number): number
	return (unixTime - RaidConfig.WEEK_ANCHOR) // RaidConfig.WEEK_SECONDS
end

function Formulas.raidWeekStart(weekId: number): number
	return RaidConfig.WEEK_ANCHOR + weekId * RaidConfig.WEEK_SECONDS
end

function Formulas.raidDay(unixTime: number): number
	return (unixTime - RaidConfig.WEEK_ANCHOR) // RaidConfig.DAY_SECONDS
end

-- Raid units for some damage: how many of your own kills it's worth, capped per attack.
function Formulas.raidUnits(damage: BigNum, highestStage: number, multiplier: number): number
	local units = BigNum.toNumber(BigNum.div(damage, Formulas.enemyHp(highestStage))) * multiplier
	return math.clamp(math.floor(units), 0, RaidConfig.UNITS_CAP_PER_ATTACK)
end

-- How many tiers a clan's total units have reached.
function Formulas.raidTier(units: number): number
	local tier = 0
	for _, threshold in RaidConfig.TIERS do
		if units >= threshold then
			tier += 1
		end
	end
	return tier
end

-- Rewards for reaching a tier: (honor, freePacks).
function Formulas.raidRewards(tier: number): (number, number)
	return tier * RaidConfig.HONOR_PER_TIER, tier // RaidConfig.PACK_EVERY_TIERS
end

---------------------------------------------------------------- faction war time

-- War week number for a Unix time (os.time()). Weeks start Monday 00:00 UTC.
function Formulas.warWeek(unixTime: number): number
	return (unixTime - FactionConfig.WEEK_ANCHOR) // FactionConfig.WEEK_SECONDS
end

function Formulas.warWeekStart(weekId: number): number
	return FactionConfig.WEEK_ANCHOR + weekId * FactionConfig.WEEK_SECONDS
end

-- War "day" number (the daily point cap resets each day).
function Formulas.warDay(unixTime: number): number
	local dayLength = FactionConfig.WEEK_SECONDS / FactionConfig.DAYS_PER_WEEK
	return math.floor((unixTime - FactionConfig.WEEK_ANCHOR) / dayLength)
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

function Formulas.isBossStage(stage: number): boolean
	return stage > 0 and stage % BossConfig.BOSS_EVERY == 0
end

function Formulas.bossHp(stage: number): BigNum
	return BigNum.mulNumber(Formulas.enemyHp(stage), BossConfig.BOSS_HP_MULTIPLIER)
end

-- Damage per second the boss deals to your army's HP.
function Formulas.bossDps(stage: number): BigNum
	return BigNum.mulNumber(Formulas.enemyHp(stage), BossConfig.BOSS_DPS_FACTOR)
end

function Formulas.bossGold(stage: number): BigNum
	return BigNum.mulNumber(Formulas.goldPerKill(stage), BossConfig.BOSS_GOLD_MULTIPLIER)
end

---------------------------------------------------------------- ascend + honor

-- Honor for Ascending with this run's highest stage. Zero below AscendConfig.MIN_STAGE.
function Formulas.honorForStage(stage: number): BigNum
	if stage < AscendConfig.MIN_STAGE then
		return BigNum.ZERO
	end
	local raw = BigNum.mulNumber(
		BigNum.powNumber(AscendConfig.HONOR_GROWTH, stage - AscendConfig.MIN_STAGE),
		AscendConfig.HONOR_BASE
	)
	return BigNum.floor(raw)
end

-- The next stage above `stage` that gives more Honor than `stage` does.
function Formulas.nextHonorStage(stage: number): number
	if stage < AscendConfig.MIN_STAGE then
		return AscendConfig.MIN_STAGE
	end
	local current = Formulas.honorForStage(stage)
	for candidate = stage + 1, stage + 200 do
		if BigNum.gt(Formulas.honorForStage(candidate), current) then
			return candidate
		end
	end
	return stage + 1
end

-- An ability's numbers after its Honor upgrades (AbilityConfig.UPGRADES). `upgrades` is
-- the player's abilityUpgrades (id -> level); nil = no upgrades.
function Formulas.abilityStats(abilityId: string, upgrades: { [string]: number }?): Types.AbilityStats
	local def = AbilityConfig.ABILITIES[abilityId]
	local stats: { [string]: number? } = {
		cooldown = def.cooldown,
		duration = def.duration,
		damageMultiplier = def.damageMultiplier,
		goldMultiplier = def.goldMultiplier,
		burstDpsSeconds = def.burstDpsSeconds,
	}
	if upgrades ~= nil then
		for upgradeId, upgrade in AbilityConfig.UPGRADES do
			local level = math.clamp(upgrades[upgradeId] or 0, 0, upgrade.maxLevel)
			local base = stats[upgrade.stat]
			if upgrade.abilityId == abilityId and level > 0 and base ~= nil then
				stats[upgrade.stat] = base + upgrade.perLevel * level
			end
		end
	end
	return {
		cooldown = stats.cooldown :: number,
		duration = stats.duration,
		damageMultiplier = stats.damageMultiplier,
		goldMultiplier = stats.goldMultiplier,
		burstDpsSeconds = stats.burstDpsSeconds,
	}
end

-- Honor cost of the next level of an ability upgrade.
function Formulas.abilityUpgradeCost(upgradeId: string, level: number): BigNum
	local def = AbilityConfig.UPGRADES[upgradeId]
	if def == nil then
		error(`Unknown ability upgrade: {upgradeId}`, 2)
	end
	return BigNum.round(BigNum.mulNumber(BigNum.powNumber(def.costGrowth, level), def.baseCost))
end

function Formulas.honorUpgradeCost(upgradeId: string, level: number): BigNum
	local def = HonorConfig.UPGRADES[upgradeId]
	if def == nil then
		error(`Unknown Honor upgrade: {upgradeId}`, 2)
	end
	return BigNum.round(BigNum.mulNumber(BigNum.powNumber(def.costGrowth, level), def.baseCost))
end

-- Gold a new run starts with, given the Head Start style upgrades owned.
function Formulas.startingGold(upgrades: { [string]: number }): BigNum
	local gold = BigNum.fromNumber(EconomyConfig.STARTING_GOLD)
	for upgradeId, def in HonorConfig.UPGRADES do
		local level = upgrades[upgradeId] or 0
		if def.startGoldMultiplier ~= nil and level > 0 then
			gold = BigNum.mul(gold, BigNum.powNumber(def.startGoldMultiplier, level))
		end
	end
	return gold
end

---------------------------------------------------------------- rewards

-- "N minutes of your army's gold": the normal gold rate at your best cleared stage,
-- at full efficiency, never less than `minimum`. Used by quests, login rewards, products.
function Formulas.incomeGold(dps: BigNum, goldMultiplier: number, highestStage: number, minutes: number, minimum: number): BigNum
	local stage = Formulas.offlineStage(highestStage)
	local gold = Formulas.offlineGold(dps, goldMultiplier, stage, minutes * 60, 1)
	return BigNum.max(gold, BigNum.fromNumber(minimum))
end

---------------------------------------------------------------- offline

-- The stage your army farms while offline: the highest NORMAL stage cleared this run.
function Formulas.offlineStage(highestStage: number): number
	local stage = math.max(1, highestStage - 1)
	if Formulas.isBossStage(stage) then
		stage -= 1
	end
	return math.max(1, stage)
end

-- Gold earned offline. `dps` and `goldMultiplier` should include permanent bonuses.
-- Kills per second are capped at what the live game could resolve, so a huge army on a
-- low stage can't earn more offline than online.
function Formulas.offlineGold(dps: BigNum, goldMultiplier: number, stage: number, seconds: number, efficiency: number): BigNum
	if seconds <= 0 or BigNum.isZero(dps) then
		return BigNum.ZERO
	end
	local maxKillsPerSecond = StageConfig.ENEMIES_PER_STAGE * CombatConfig.TICK_RATE
	local killsPerSecond = math.min(BigNum.toNumber(BigNum.div(dps, Formulas.enemyHp(stage))), maxKillsPerSecond)
	return BigNum.mulNumber(Formulas.goldPerKill(stage), killsPerSecond * seconds * efficiency * goldMultiplier)
end

-- `armyDps` should already include damage multipliers (e.g. Rally), so clicks benefit too.
function Formulas.tapDamage(armyDps: BigNum): BigNum
	return BigNum.add(
		BigNum.fromNumber(CombatConfig.TAP_FLAT_DAMAGE),
		BigNum.mulNumber(armyDps, CombatConfig.TAP_ARMY_DPS_FRACTION)
	)
end

return table.freeze(Formulas)
