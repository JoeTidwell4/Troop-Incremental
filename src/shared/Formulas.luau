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
function Formulas.fightDamageMultipliers(factionId: string, stage: number, vsBoss: boolean, generals: Types.GeneralsData?): TroopMultipliers
	local result = Formulas.factionTroopMultipliers(factionId)
	if generals ~= nil then
		applyTroopBonuses(result, Formulas.generalBonuses(generals).troopDamage)
	end
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
		bossTime = 0,
		goldenChance = 0,
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
	result.damage = 1 + passive.damage
	result.armyHp = 1 + passive.armyHp
	result.gold = 1 + passive.gold
	result.tap = 1 + passive.tap
	return result
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
