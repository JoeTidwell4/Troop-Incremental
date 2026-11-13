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
local DataService = require(Services.DataService)
local ModifierService = require(Services.ModifierService)

type BigNum = BigNum.BigNum

type Army = {
	baseDps: BigNum,
	baseHp: BigNum,
	pendingDamage: BigNum, -- clicks + ability bursts waiting for the next tick
}

local armies: { [Player]: Army } = {}

local CombatService = {}

-- Recalculate base army stats. Call after anything that changes troops or gear.
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
	army.baseDps = Formulas.armyDps(data.troops, data.gear)
	army.baseHp = Formulas.armyHp(data.troops, data.gear)
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
	return Formulas.tapDamage(CombatService.getDps(player))
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
	CombatService.queueDamage(player, BigNum.mulNumber(CombatService.getTapDamage(player), taps))
	data.stats.totalTaps += taps
end

-- Returns all damage the army deals over `dt` seconds, plus queued damage (which is cleared).
function CombatService.takeDamage(player: Player, dt: number): BigNum
	local army = armies[player]
	if army == nil then
		return BigNum.ZERO
	end
	local damage = BigNum.add(BigNum.mulNumber(CombatService.getDps(player), dt), army.pendingDamage)
	army.pendingDamage = BigNum.ZERO
	return damage
end

function CombatService.start()
	DataService.ProfileReleasing:Connect(function(player: Player)
		armies[player] = nil
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		armies[player] = nil
	end)
end

return CombatService
