--!strict
-- The army's numbers: how much damage it deals and how much HP it has.
--
-- There are no physical troops: damage is army DPS * time plus any queued damage
-- from clicks and abilities. StageService pulls that damage every tick and applies it.
-- Base stats are cached and recalculated only when troops change; multipliers
-- (abilities now, more later) are applied on read through ModifierService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local CombatConfig = require(Shared:WaitForChild("Config"):WaitForChild("CombatConfig"))
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local ModifierService = require(Services.ModifierService)

local random = Random.new()

type BigNum = BigNum.BigNum

type Army = {
	baseDps: BigNum,
	baseHp: BigNum,
	pendingDamage: BigNum, -- clicks + ability bursts waiting for the next tick
}

local armies: { [Player]: Army } = {}
-- What the army is fighting right now (set by StageService): the stage (for area traits)
-- and whether it's a boss (for troops that are better against bosses or normal enemies).
local contexts: { [Player]: { stage: number, vsBoss: boolean } } = {}

local CombatService = {}

-- Recalculate base army stats. Call after anything that changes troops, gear, or faction.
-- Also creates the player's army entry the first time.
function CombatService.refreshArmy(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local army = armies[player]
	if army == nil then
		army = { baseDps = BigNum.ZERO, baseHp = BigNum.ZERO, pendingDamage = BigNum.ZERO }
		armies[player] = army
	end
	local context = contexts[player] or { stage = data.stage, vsBoss = false }
	-- Damage: faction x area trait x each troop's job. HP: faction only.
	local damageBonus = Formulas.fightDamageMultipliers(data.faction, context.stage, context.vsBoss)
	army.baseDps = Formulas.armyDps(data.troops, data.gear, damageBonus)
	army.baseHp = Formulas.armyHp(data.troops, data.gear, Formulas.factionTroopMultipliers(data.faction))
end

-- Called by StageService whenever the fight changes; recalculates the army's damage.
function CombatService.setFightContext(player: Player, stage: number, vsBoss: boolean)
	local current = contexts[player]
	if current ~= nil and current.stage == stage and current.vsBoss == vsBoss then
		return
	end
	contexts[player] = { stage = stage, vsBoss = vsBoss }
	CombatService.refreshArmy(player)
end

-- Army DPS with all current multipliers applied.
function CombatService.getDps(player: Player): BigNum
	local army = armies[player]
	if army == nil then
		return BigNum.ZERO
	end
	return BigNum.mulNumber(army.baseDps, ModifierService.get(player).damage)
end

function CombatService.getTapDamage(player: Player): BigNum
	return BigNum.mulNumber(Formulas.tapDamage(CombatService.getDps(player)), ModifierService.get(player).tap)
end

-- Army max HP with all current multipliers applied.
function CombatService.getMaxHp(player: Player): BigNum
	local army = armies[player]
	if army == nil then
		return BigNum.ZERO
	end
	return BigNum.mulNumber(army.baseHp, ModifierService.get(player).armyHp)
end

-- Queue extra damage (e.g. Barrage) to land on the next tick.
function CombatService.queueDamage(player: Player, damage: BigNum)
	local army = armies[player]
	if army ~= nil then
		army.pendingDamage = BigNum.add(army.pendingDamage, damage)
	end
end

-- Queue damage from taps that TapService already rate-limited.
function CombatService.applyTaps(player: Player, taps: number)
	local data = DataService.get(player)
	if data == nil or taps <= 0 then
		return
	end
	-- Each click can crit. The crits' extra damage is sent to the client for a big number.
	local crits = 0
	for _ = 1, math.floor(taps) do
		if random:NextNumber() < CombatConfig.CRIT_CHANCE then
			crits += 1
		end
	end
	local perTap = CombatService.getTapDamage(player)
	CombatService.queueDamage(player, BigNum.mulNumber(perTap, taps + crits * (CombatConfig.CRIT_MULTIPLIER - 1)))
	if crits > 0 then
		RemoteService.fireClient(Remotes.Events.Crit, player, BigNum.mulNumber(perTap, CombatConfig.CRIT_MULTIPLIER))
	end
	data.stats.totalTaps += taps
end

-- Returns all damage the army deals over `dt` seconds, plus queued damage (which is cleared).
-- `troopsBlocked`: a boss shield is up, so only clicks and abilities (queued damage) count.
-- `troopMultiplier` / `queuedMultiplier` scale the two parts (raid boss rules).
function CombatService.takeDamage(player: Player, dt: number, troopsBlocked: boolean?, troopMultiplier: number?, queuedMultiplier: number?): BigNum
	local army = armies[player]
	if army == nil then
		return BigNum.ZERO
	end
	local troopDamage = if troopsBlocked then BigNum.ZERO else BigNum.mulNumber(CombatService.getDps(player), dt * (troopMultiplier or 1))
	local damage = BigNum.add(troopDamage, BigNum.mulNumber(army.pendingDamage, queuedMultiplier or 1))
	army.pendingDamage = BigNum.ZERO
	return damage
end

function CombatService.start()
	DataService.ProfileReleasing:Connect(function(player: Player)
		armies[player] = nil
		contexts[player] = nil
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		armies[player] = nil
		contexts[player] = nil
	end)
end

return CombatService
