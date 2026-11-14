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
local CommanderConfig = require(Shared.Config.CommanderConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local FactionConfig = require(Shared.Config.FactionConfig)
local ClanConfig = require(Shared.Config.ClanConfig)
local RaidConfig = require(Shared.Config.RaidConfig)
local LegacyConfig = require(Shared.Config.LegacyConfig)
local SkillConfig = require(Shared.Config.SkillConfig)
local GeneralConfig = require(Shared.Config.GeneralConfig)
local RelicConfig = require(Shared.Config.RelicConfig)
local ChallengeConfig = require(Shared.Config.ChallengeConfig)
local TowerConfig = require(Shared.Config.TowerConfig)
local ExpeditionConfig = require(Shared.Config.ExpeditionConfig)
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

-- Gold price of a Wardrobe Chest: priced at your all-time BEST stage (wardrobe gear is kept
-- on Ascend, so this run's stage would make chests far too cheap after Ascending).
function Formulas.wardrobeChestPrice(bestStage: number): BigNum
	return BigNum.round(BigNum.mulNumber(Formulas.goldPerKill(bestStage), CommanderConfig.CHEST_PRICE_IN_KILLS))
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

-- Multiplies per-troop General bonuses into a troop multiplier table (in place).
local function applyTroopBonuses(target: { [string]: number }, bonuses: { [string]: number })
	for troopId, multiplier in bonuses do
		target[troopId] = (target[troopId] or 1) * multiplier
	end
end

-- Per-troop DAMAGE multipliers for a fight: faction bonus x the area's trait x each
-- troop's job (bosses vs normal enemies). HP only uses the faction bonus.
-- `towerFloor` (> 0 in a Tower fight): no area trait there, the floor's laws instead.
function Formulas.fightDamageMultipliers(factionId: string, stage: number, vsBoss: boolean, generals: Types.GeneralsData?, towerFloor: number?): TroopMultipliers
	local result = Formulas.factionTroopMultipliers(factionId)
	if generals ~= nil then
		applyTroopBonuses(result, Formulas.generalBonuses(generals).troopDamage)
	end
	local inTower = towerFloor ~= nil and towerFloor > 0
	if inTower then
		applyTroopBonuses(result, Formulas.towerFloor(towerFloor :: number).effects.troopDamage)
	end
	local trait = if inTower then nil else Areas.forStage(stage).theme.trait
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

-- Per-troop HP multipliers: faction + fielded Generals (e.g. Brannoc: Knights).
function Formulas.troopHpMultipliers(factionId: string, generals: Types.GeneralsData?): TroopMultipliers
	local result = Formulas.factionTroopMultipliers(factionId)
	if generals ~= nil then
		applyTroopBonuses(result, Formulas.generalBonuses(generals).troopHp)
	end
	return result
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
function Formulas.clanWarReward(rank: number?): { honor: number?, honorShare: number?, heroChests: number?, packs: number? }?
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

-- This raid week's boss (RaidConfig.BOSSES rotates one per week).
function Formulas.raidBoss(weekId: number)
	local bosses = RaidConfig.BOSSES
	return bosses[(math.max(0, weekId) % #bosses) + 1]
end

-- A raid boss by id (falls back to the first boss).
function Formulas.raidBossById(bossId: string)
	for _, boss in RaidConfig.BOSSES do
		if boss.id == bossId then
			return boss
		end
	end
	return RaidConfig.BOSSES[1]
end

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
-- (Honor, free packs) for a raid tier. Honor scales with your all-time best stage.
function Formulas.raidRewards(tier: number, bestStage: number): (BigNum, number)
	local honor = if tier > 0
		then Formulas.scaledHonor(bestStage, tier * RaidConfig.HONOR_SHARE_PER_TIER, tier * RaidConfig.HONOR_PER_TIER)
		else BigNum.ZERO
	return honor, tier // RaidConfig.PACK_EVERY_TIERS
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

---------------------------------------------------------------- generals

function Formulas.generalMaxLevel(stars: number): number
	return stars * GeneralConfig.LEVELS_PER_STAR
end

-- How strong a General's passive is (levels and stars) and its trait (stars only).
function Formulas.generalPassivePower(state: Types.GeneralState): number
	return (1 + GeneralConfig.LEVEL_STEP * (state.level - 1)) * (1 + GeneralConfig.STAR_STEP * (state.stars - 1))
end

function Formulas.generalTraitPower(state: Types.GeneralState): number
	return 1 + GeneralConfig.STAR_STEP * (state.stars - 1)
end

-- The trait's value for a General at its current stars (e.g. 0.5 -> 0.625 at 2 stars).
function Formulas.generalTraitValue(def: Types.GeneralDef, state: Types.GeneralState): number
	return def.trait.value * Formulas.generalTraitPower(state)
end

-- Gold to raise a General from `level` to `level + 1`.
function Formulas.generalLevelCost(generalId: string, level: number, bestStage: number): BigNum
	local def = GeneralConfig.GENERALS[generalId]
	local rarity = GeneralConfig.RARITIES[if def ~= nil then def.rarity else "Rare"]
	local kills = GeneralConfig.LEVEL_COST_KILLS * GeneralConfig.LEVEL_COST_GROWTH ^ (level - 1) * rarity.costMultiplier
	return BigNum.round(BigNum.mulNumber(Formulas.goldPerKill(bestStage), kills))
end

-- Everything the FIELDED Generals add up to.
function Formulas.generalBonuses(generals: Types.GeneralsData?): Types.GeneralBonuses
	local result: Types.GeneralBonuses = {
		damage = 1,
		armyHp = 1,
		gold = 1,
		tap = 1,
		bossDamage = 1,
		troopDamage = {},
		troopHp = {},
		critChance = 0,
		critMultiplier = 0,
		bossTime = 0,
		goldenChance = 0,
		sets = {},
	}
	if generals == nil then
		return result
	end
	local passive = { damage = 0, armyHp = 0, gold = 0, tap = 0 } :: { [string]: number }
	for _, generalId in generals.fielded do
		local def = GeneralConfig.GENERALS[generalId]
		local state = generals.owned[generalId]
		if def ~= nil and state ~= nil then
			passive[def.passive.stat] = (passive[def.passive.stat] or 0) + def.passive.value * Formulas.generalPassivePower(state)
			local value = Formulas.generalTraitValue(def, state)
			local trait = def.trait
			if trait.kind == "troopDamage" and trait.troopId ~= nil then
				result.troopDamage[trait.troopId] = (result.troopDamage[trait.troopId] or 1) * (1 + value)
			elseif trait.kind == "troopHp" and trait.troopId ~= nil then
				result.troopHp[trait.troopId] = (result.troopHp[trait.troopId] or 1) * (1 + value)
			elseif trait.kind == "allTroopDamage" then
				for _, troopId in TroopConfig.ORDER do
					result.troopDamage[troopId] = (result.troopDamage[troopId] or 1) * (1 + value)
				end
			elseif trait.kind == "critChance" then
				result.critChance += value
			elseif trait.kind == "bossTime" then
				result.bossTime += value
			elseif trait.kind == "goldenChance" then
				result.goldenChance += value
			elseif trait.kind == "bossDamageTaken" then
				result.bossDamage *= math.max(0.1, 1 + value)
			end
		end
	end
	-- Set bonuses: 2 or 3 fielded members of a House (the wildcard counts for every House).
	for _, set in Formulas.generalSets(generals) do
		local house = GeneralConfig.HOUSES[set.houseId]
		local bonus = house.bonuses[set.count]
		if bonus ~= nil then
			for field, value in bonus.effects do
				local scaled = value * set.power
				if passive[field] ~= nil then
					passive[field] += scaled
				elseif field == "bossDamage" then
					result.bossDamage *= math.max(0.1, 1 + scaled)
				elseif field == "critChance" then
					result.critChance += scaled
				elseif field == "critMultiplier" then
					result.critMultiplier += scaled
				elseif field == "bossTime" then
					result.bossTime += scaled
				elseif field == "goldenChance" then
					result.goldenChance += scaled
				end
			end
			table.insert(result.sets, set)
		end
	end
	result.damage = 1 + passive.damage
	result.armyHp = 1 + passive.armyHp
	result.gold = 1 + passive.gold
	result.tap = 1 + passive.tap
	return result
end

-- The House a General belongs to ("" for the wildcard, who belongs to all of them).
function Formulas.generalHouse(generalId: string): string
	for _, houseId in GeneralConfig.HOUSE_ORDER do
		if table.find(GeneralConfig.HOUSES[houseId].members, generalId) ~= nil then
			return houseId
		end
	end
	return ""
end

-- Active sets among the fielded Generals: { houseId, count (2-3), power }.
-- power = 1 + STAR_STEP x (lowest stars among the counted members - 1).
function Formulas.generalSets(generals: Types.GeneralsData): { { houseId: string, count: number, power: number } }
	local sets = {}
	local wildcard = GeneralConfig.WILDCARD
	local wildcardState = if table.find(generals.fielded, wildcard) ~= nil then generals.owned[wildcard] else nil
	for _, houseId in GeneralConfig.HOUSE_ORDER do
		local house = GeneralConfig.HOUSES[houseId]
		local count = 0
		local lowest = math.huge
		for _, generalId in generals.fielded do
			local state = generals.owned[generalId]
			if state ~= nil and table.find(house.members, generalId) ~= nil then
				count += 1
				lowest = math.min(lowest, state.stars)
			end
		end
		if count >= 1 and wildcardState ~= nil then
			count += 1
			lowest = math.min(lowest, wildcardState.stars)
		end
		if count >= 2 then
			table.insert(sets, {
				houseId = houseId,
				count = math.min(count, 3),
				power = 1 + GeneralConfig.STAR_STEP * (lowest - 1),
			})
		end
	end
	return sets
end

---------------------------------------------------------------- relics

-- One stat line's amount at a relic level (e.g. 0.05 x 1.2 x 1.3 = +7.8% damage).
function Formulas.relicLineValue(line: Types.RelicLine, level: number): number
	local stat = RelicConfig.STATS[line.stat]
	if stat == nil then
		return 0
	end
	return stat.value * line.roll * (1 + RelicConfig.LEVEL_STEP * level)
end

local function rarityOrder(rarity: string): number
	local def = RelicConfig.RARITIES[rarity]
	return if def ~= nil then def.order else 1
end

function Formulas.relicUpgradeCost(item: Types.RelicItem): number
	return math.floor(RelicConfig.UPGRADE_BASE * RelicConfig.UPGRADE_GROWTH ^ item.level * rarityOrder(item.rarity) + 0.5)
end

function Formulas.relicRerollCost(item: Types.RelicItem): number
	return RelicConfig.REROLL_BASE * rarityOrder(item.rarity)
end

function Formulas.relicSalvageDust(item: Types.RelicItem): number
	local def = RelicConfig.RARITIES[item.rarity]
	return (if def ~= nil then def.dust else 0) + item.level * RelicConfig.DUST_PER_LEVEL
end

-- Everything the EQUIPPED relics add up to, including set bonuses (2 / 4 / 6 pieces).
function Formulas.relicBonuses(relics: Types.RelicsData?): Types.RelicBonuses
	local sum: { [string]: number } = { damage = 0, armyHp = 0, gold = 0, tap = 0, bossDamageDealt = 0, critChance = 0, critMultiplier = 0, bossTime = 0, goldenChance = 0 }
	local bossDamage = 1
	local sets: { { setId: string, count: number } } = {}
	if relics ~= nil then
		local perSet: { [string]: number } = {}
		for _, slot in RelicConfig.SLOTS do
			local item = relics.items[relics.equipped[slot] or ""]
			if item ~= nil and item.slot == slot then
				for _, line in item.lines do
					sum[line.stat] = (sum[line.stat] or 0) + Formulas.relicLineValue(line, item.level)
				end
				perSet[item.set] = (perSet[item.set] or 0) + 1
			end
		end
		for _, setId in RelicConfig.SET_ORDER do
			local count = perSet[setId] or 0
			local def = RelicConfig.SETS[setId]
			if count >= 2 then
				table.insert(sets, { setId = setId, count = count })
			end
			for pieces, bonus in def.bonuses do
				if count >= pieces then
					for field, value in bonus.effects do
						if field == "bossDamage" then
							bossDamage *= math.max(0.1, 1 + value)
						else
							sum[field] = (sum[field] or 0) + value
						end
					end
				end
			end
		end
	end
	return {
		damage = 1 + sum.damage,
		armyHp = 1 + sum.armyHp,
		gold = 1 + sum.gold,
		tap = 1 + sum.tap,
		bossDamageDealt = 1 + sum.bossDamageDealt,
		bossDamage = bossDamage,
		critChance = sum.critChance,
		critMultiplier = sum.critMultiplier,
		bossTime = sum.bossTime,
		goldenChance = sum.goldenChance,
		sets = sets,
	}
end

-- Crit chance / crit power / boss timer / golden enemy chance from skills + fielded
-- Generals + equipped relics, added up. One place, so every system is counted the same.
function Formulas.extras(skillRanks: { [string]: number }?, generals: Types.GeneralsData?, relics: Types.RelicsData?): Types.ExtraEffects
	local skills = Formulas.skillEffects(skillRanks)
	local gen = Formulas.generalBonuses(generals)
	local rel = Formulas.relicBonuses(relics)
	return {
		critChance = skills.critChance + gen.critChance + rel.critChance,
		critMultiplier = skills.critMultiplier + gen.critMultiplier + rel.critMultiplier,
		bossTime = skills.bossTime + gen.bossTime + rel.bossTime,
		goldenChance = skills.goldenChance + gen.goldenChance + rel.goldenChance,
	}
end

---------------------------------------------------------------- challenge runs

local NO_RULES: Types.ChallengeRules = table.freeze({})

-- The rules of the challenge a player is in ({} when not in one).
function Formulas.challengeRules(activeId: string?): Types.ChallengeRules
	local def = if activeId ~= nil then ChallengeConfig.CHALLENGES[activeId] else nil
	return if def ~= nil then def.rules else NO_RULES
end

-- The (skill ranks, Generals, relics) the fight math should count: all three are off in
-- a `noExtras` challenge (nil = none; every function here treats nil as empty).
function Formulas.fightBuild(
	activeId: string?,
	skillRanks: { [string]: number }?,
	generals: Types.GeneralsData?,
	relics: Types.RelicsData?
): ({ [string]: number }?, Types.GeneralsData?, Types.RelicsData?)
	if Formulas.challengeRules(activeId).noExtras then
		return nil, nil, nil
	end
	return skillRanks, generals, relics
end

-- The stage whose boss must be beaten for tier `tier` (nil past the last tier).
function Formulas.challengeGoal(tier: number): number?
	return ChallengeConfig.TIER_GOALS[tier]
end

-- Permanent bonuses from every tier cleared so far.
function Formulas.challengeBonuses(tiers: { [string]: number }?): Types.ChallengeBonuses
	local add: { [string]: number } = {}
	if tiers ~= nil then
		for challengeId, cleared in tiers do
			local def = ChallengeConfig.CHALLENGES[challengeId]
			if def ~= nil and cleared > 0 then
				add[def.reward.stat] = (add[def.reward.stat] or 0) + def.reward.perTier * cleared
			end
		end
	end
	return {
		damage = 1 + (add.damage or 0),
		armyHp = 1 + (add.armyHp or 0),
		gold = 1 + (add.gold or 0),
		tap = 1 + (add.tap or 0),
		bossDamageDealt = 1 + (add.bossDamageDealt or 0),
		offline = 1 + (add.offline or 0),
		xp = 1 + (add.xp or 0),
		bossTime = add.bossTime or 0,
	}
end

-- Reward text for a challenge at `tiers` cleared, e.g. "+12% army damage".
function Formulas.challengeRewardText(def: Types.ChallengeDef, tiers: number): string
	local value = def.reward.perTier * tiers
	if def.reward.stat ~= "bossTime" then
		value *= 100
	end
	local text = string.gsub(def.reward.text, "{v}", string.format("%g", math.floor(value * 10 + 0.5) / 10))
	return text
end

---------------------------------------------------------------- expeditions

-- Missions that can be away at once.
function Formulas.expeditionSlots(bestStage: number): number
	return ExpeditionConfig.SLOTS + (if bestStage >= ExpeditionConfig.THIRD_SLOT_STAGE then 1 else 0)
end

-- Team power of `generalIds` on a mission for `house` (empty list = the Scout Party).
function Formulas.expeditionPower(generals: Types.GeneralsData, generalIds: { string }, house: string): number
	if #generalIds == 0 then
		return ExpeditionConfig.SCOUT_POWER
	end
	local power = 0
	for _, generalId in generalIds do
		local state = generals.owned[generalId]
		if state ~= nil then
			local one = state.stars * (1 + ExpeditionConfig.LEVEL_STEP * (state.level - 1))
			local memberHouse = Formulas.generalHouse(generalId)
			if memberHouse == house or generalId == GeneralConfig.WILDCARD then
				one *= ExpeditionConfig.HOUSE_BONUS
			end
			power += one
		end
	end
	return power
end

-- How much of the base reward comes back for `power` on a mission of `durationId`.
function Formulas.expeditionScale(durationId: string, power: number): number
	local duration = ExpeditionConfig.DURATIONS[durationId]
	return math.clamp(power / duration.power, ExpeditionConfig.MIN_SCALE, ExpeditionConfig.MAX_SCALE)
end

-- The base amount of a mission's reward x `scale` (whole numbers; Honor and Relic as-is).
function Formulas.expeditionAmount(mission: Types.ExpeditionMission, scale: number): number
	local base = ExpeditionConfig.DURATIONS[mission.duration].rewards[mission.reward]
	if typeof(base) ~= "number" then
		return 1
	end
	if mission.reward == "Honor" then
		return base * scale
	end
	return math.max(1, math.floor(base * scale + 0.5))
end

---------------------------------------------------------------- endless tower

-- A small integer hash, the same on the server and the client (whole numbers below 2^53).
local function towerHash(floor: number, salt: number): number
	local h = (floor * 7919 + salt * 104729 + 12345) % 4294967296
	h = bit32.bxor(h, bit32.rshift(h, 7))
	h = (h * 40503) % 4294967296
	h = bit32.bxor(h, bit32.rshift(h, 11))
	h = (h * 9973) % 4294967296
	return bit32.bxor(h, bit32.rshift(h, 13))
end

local towerCache: { [number]: Types.TowerFloor } = {}

-- Everything about a Tower floor that follows from its number: laws, Guardian, chest.
function Formulas.towerFloor(floor: number): Types.TowerFloor
	local cached = towerCache[floor]
	if cached ~= nil then
		return cached
	end
	local guardian = floor % TowerConfig.GUARDIAN_EVERY == 0
	local lawCount = if floor <= TowerConfig.FREE_FLOORS
		then 0
		elseif not guardian and floor % TowerConfig.DOUBLE_LAW_EVERY == 0 then 2
		else 1
	local laws: { string } = {}
	local order = TowerConfig.LAW_ORDER
	if lawCount >= 1 then
		table.insert(laws, order[towerHash(floor, 1) % #order + 1])
	end
	if lawCount >= 2 then
		-- A different one: step 1..(#order - 1) places on from the first.
		local first = table.find(order, laws[1]) :: number
		local step = towerHash(floor, 2) % (#order - 1) + 1
		table.insert(laws, order[(first - 1 + step) % #order + 1])
	end
	local effects: Types.TowerEffects = {
		troopMultiplier = 1,
		queuedMultiplier = 1,
		troopDamage = {},
		regen = 0,
		bossDamage = 1,
		timeScale = 1,
		noClicks = false,
		noAbilities = false,
		weakPointGap = 1,
	}
	for _, lawId in laws do
		local law = TowerConfig.LAWS[lawId].effects
		effects.troopMultiplier *= law.troopMultiplier or 1
		effects.queuedMultiplier *= law.queuedMultiplier or 1
		effects.regen += law.regen or 0
		effects.bossDamage *= law.bossDamage or 1
		effects.timeScale *= law.timeScale or 1
		effects.noClicks = effects.noClicks or law.noClicks == true
		effects.noAbilities = effects.noAbilities or law.noAbilities == true
		effects.weakPointGap *= law.weakPointGap or 1
		if law.troopDamage ~= nil then
			for troopId, multiplier in law.troopDamage do
				effects.troopDamage[troopId] = (effects.troopDamage[troopId] or 1) * multiplier
			end
		end
	end
	local result: Types.TowerFloor = {
		floor = floor,
		stage = TowerConfig.BASE_STAGE + TowerConfig.STAGES_PER_FLOOR * floor,
		guardian = guardian,
		chest = floor % TowerConfig.CHEST_EVERY == 0,
		laws = laws,
		effects = effects,
		model = TowerConfig.MODELS[(floor - 1) % #TowerConfig.MODELS + 1],
	}
	towerCache[floor] = result
	return result
end

-- HP and damage per second (before the army-HP clamp) of a floor's boss.
function Formulas.towerHp(floor: number): BigNum
	local info = Formulas.towerFloor(floor)
	return BigNum.round(BigNum.mulNumber(Formulas.bossHp(info.stage), if info.guardian then TowerConfig.GUARDIAN_HP else 1))
end

function Formulas.towerDps(floor: number): BigNum
	return Formulas.bossDps(Formulas.towerFloor(floor).stage)
end

-- Permanent damage and gold multiplier from your best floor.
function Formulas.towerBonus(bestFloor: number): number
	return 1 + TowerConfig.BONUS_PER_STEP * (bestFloor // TowerConfig.BONUS_EVERY)
end

-- Relic Dust for clearing `floor` the first time.
function Formulas.towerFloorDust(floor: number): number
	return math.floor(TowerConfig.FLOOR_DUST_BASE + TowerConfig.FLOOR_DUST_PER_FLOOR * floor)
end

function Formulas.towerChestDust(floor: number): number
	return TowerConfig.CHEST_DUST_BASE + TowerConfig.CHEST_DUST_PER_FLOOR * floor
end

-- The daily Tribute at `bestFloor`: (minutes of army gold, Relic Dust).
function Formulas.towerTribute(bestFloor: number): (number, number)
	local minutes = math.min(
		TowerConfig.TRIBUTE_GOLD_MINUTES_BASE + TowerConfig.TRIBUTE_GOLD_MINUTES_PER_FLOOR * bestFloor,
		TowerConfig.TRIBUTE_GOLD_MINUTES_MAX
	)
	return minutes, TowerConfig.TRIBUTE_DUST_BASE + TowerConfig.TRIBUTE_DUST_PER_FLOOR * bestFloor
end

---------------------------------------------------------------- commander level + skills

-- (level, XP into this level, XP needed for the next; 0 at max level).
function Formulas.commanderLevel(xp: number): (number, number, number)
	local level = 1
	local left = math.max(0, xp)
	while level < SkillConfig.MAX_LEVEL do
		local need = math.floor(SkillConfig.LEVEL_XP_BASE * SkillConfig.LEVEL_XP_GROWTH ^ (level - 1))
		if left < need then
			return level, left, need
		end
		left -= need
		level += 1
	end
	return level, 0, 0
end

-- Skill points earned at a level, and spent by these ranks (optionally in one branch).
function Formulas.skillPoints(level: number): number
	return (level - 1) * SkillConfig.SKILL_POINTS_PER_LEVEL
end

function Formulas.skillSpent(ranks: { [string]: number }, branch: string?): number
	local spent = 0
	for nodeId, rank in ranks do
		local def = SkillConfig.NODES[nodeId]
		if def ~= nil and (branch == nil or def.branch == branch) then
			spent += math.min(rank, def.maxRank) * def.cost
		end
	end
	return spent
end

-- Whether one more rank of `nodeId` can be learned: (ok, reason). Shared by server + UI.
function Formulas.canLearnSkill(ranks: { [string]: number }, level: number, nodeId: string): (boolean, string?)
	local def = SkillConfig.NODES[nodeId]
	if def == nil then
		return false, "Rejected"
	end
	if (ranks[nodeId] or 0) >= def.maxRank then
		return false, "MaxReached"
	end
	if Formulas.skillSpent(ranks, def.branch) < (SkillConfig.TIER_POINTS[def.tier] or 0) then
		return false, "TierLocked"
	end
	if def.fork ~= nil then
		for otherId, rank in ranks do
			local other = SkillConfig.NODES[otherId]
			if other ~= nil and otherId ~= nodeId and other.fork == def.fork and rank > 0 then
				return false, "ForkTaken"
			end
		end
	end
	if Formulas.skillPoints(level) - Formulas.skillSpent(ranks) < def.cost then
		return false, "NoPoints"
	end
	return true, nil
end

-- All skill effects added up over the learned ranks.
function Formulas.skillEffects(ranks: { [string]: number }?): Types.SkillEffects
	local total: { [string]: number } = {}
	for _, field in { "damage", "armyHp", "gold", "tap", "bossDamageDealt", "bossDamageTaken", "bossTime", "bossGold", "critChance", "critMultiplier", "goldenChance", "goldenGold", "offlineHours", "offlineEfficiency", "ascendHonor", "abilityCooldown", "abilityDuration", "weakPointDamage", "extraSlots", "lastStand" } do
		total[field] = 0
	end
	if ranks ~= nil then
		for nodeId, rank in ranks do
			local def = SkillConfig.NODES[nodeId]
			if def ~= nil and rank > 0 then
				local counted = math.min(rank, def.maxRank)
				for field, value in def.effects do
					total[field] = (total[field] or 0) + value * counted
				end
			end
		end
	end
	return (total :: any) :: Types.SkillEffects
end

-- How many abilities you can equip (AbilityConfig.LOADOUT_SLOTS + Grand Tactician).
function Formulas.loadoutSlots(ranks: { [string]: number }?): number
	return AbilityConfig.LOADOUT_SLOTS + math.floor(Formulas.skillEffects(ranks).extraSlots)
end

-- Commander XP for beating a boss.
function Formulas.bossXp(bossStage: number, firstClear: boolean): number
	local xp = SkillConfig.XP.BOSS_BASE + bossStage // SkillConfig.XP.BOSS_STAGE_DIVISOR
	return if firstClear then xp * SkillConfig.XP.FIRST_CLEAR_MULTIPLIER else xp
end

---------------------------------------------------------------- legacy

-- Total multiplier from one Crown upgrade stat ("damage", "armyHp", "gold", "ascendHonor").
function Formulas.crownMultiplier(upgrades: { [string]: number }?, stat: string): number
	local result = 1
	if upgrades == nil then
		return result
	end
	for upgradeId, level in upgrades do
		local def = LegacyConfig.UPGRADES[upgradeId]
		if def ~= nil and def.stat == stat and level > 0 then
			result *= def.multiplier ^ math.min(level, def.maxLevel or level)
		end
	end
	return result
end

-- Crown price of the next level of a Crown upgrade (whole Crowns).
function Formulas.crownUpgradeCost(upgradeId: string, level: number): number
	local def = LegacyConfig.UPGRADES[upgradeId]
	if def == nil then
		return math.huge
	end
	return math.floor(def.baseCost * def.costGrowth ^ level + 0.5)
end

-- The Legacy rank (commander aura) for a number of Legacies done; nil before the first.
function Formulas.legacyRank(count: number): { count: number, name: string, color: Color3 }?
	local rank = nil
	for _, def in LegacyConfig.RANKS do
		if count >= def.count then
			rank = def
		end
	end
	return rank
end

-- Crowns for the Honor earned during a Legacy.
function Formulas.legacyCrowns(honorThisLegacy: BigNum): number
	if BigNum.isZero(honorThisLegacy) then
		return 0
	end
	-- log space so huge Honor numbers can't overflow
	local log = (BigNum.log10(honorThisLegacy) - math.log10(LegacyConfig.CROWN_HONOR_UNIT)) * LegacyConfig.CROWN_EXPONENT
	local crowns = LegacyConfig.CROWN_SCALE * 10 ^ log
	return if crowns ~= crowns or crowns == math.huge then 0 else math.floor(crowns)
end

-- Honor for Ascending now, including Crown upgrades (Eternal Glory) and skills (Honor Guard).
function Formulas.ascendHonor(highestStage: number, crownUpgrades: { [string]: number }?, skillRanks: { [string]: number }?): BigNum
	local base = Formulas.honorForStage(highestStage)
	local multiplier = Formulas.crownMultiplier(crownUpgrades, "ascendHonor") * (1 + Formulas.skillEffects(skillRanks).ascendHonor)
	return BigNum.floor(BigNum.mulNumber(base, multiplier))
end

-- An Honor reward that stays worth something at every stage: `share` of what an Ascend
-- at your all-time best stage gives (e.g. 0.25 = a quarter of a run's Honor), never less
-- than `minimum` (the old flat amount, which is what you get before stage 50).
function Formulas.scaledHonor(bestStage: number, share: number, minimum: number): BigNum
	local run = Formulas.honorForStage(math.max(bestStage, AscendConfig.MIN_STAGE))
	return BigNum.max(BigNum.floor(BigNum.mulNumber(run, share)), BigNum.fromNumber(minimum))
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
function Formulas.abilityStats(abilityId: string, upgrades: { [string]: number }?, skillRanks: { [string]: number }?): Types.AbilityStats
	local def = AbilityConfig.ABILITIES[abilityId]
	local stats: { [string]: number? } = {}
	for _, field in AbilityConfig.STAT_FIELDS do
		stats[field] = (def :: any)[field]
	end
	if upgrades ~= nil then
		for upgradeId, upgrade in AbilityConfig.UPGRADES do
			local level = math.clamp(upgrades[upgradeId] or 0, 0, upgrade.maxLevel)
			local base = stats[upgrade.stat]
			if upgrade.abilityId == abilityId and level > 0 and base ~= nil then
				stats[upgrade.stat] = base + upgrade.perLevel * level
			end
		end
	end
	-- Skills: Rapid Recovery (shorter cooldowns), Focus (longer durations).
	if skillRanks ~= nil then
		local effects = Formulas.skillEffects(skillRanks)
		stats.cooldown = (stats.cooldown :: number) * math.max(0.2, 1 + effects.abilityCooldown)
		if stats.duration ~= nil then
			stats.duration = stats.duration * (1 + effects.abilityDuration)
		end
	end
	return (stats :: any) :: Types.AbilityStats
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
