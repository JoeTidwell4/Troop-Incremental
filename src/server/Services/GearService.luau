--!strict
-- Gear level upgrades. The client says which troop + slot and x1 or Max; the server works
-- out the price, checks the gold, and applies it with no yields in between.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = Shared:WaitForChild("Config")
local GearConfig = require(Config:WaitForChild("GearConfig"))
local TroopConfig = require(Config:WaitForChild("TroopConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local Validate = require(Server.Util.Validate)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local CombatService = require(Services.CombatService)
local ActivityService = require(Services.ActivityService)

type BuyResult = Types.BuyResult
type GearBuyMode = Types.GearBuyMode
type UpgradeRequest = { troopId: string, slot: Types.GearSlot, mode: GearBuyMode }

local MODES: { string } = { "One", "Max" }
local REJECTED: BuyResult = { ok = false, bought = 0, reason = "Rejected" }

local GearService = {}

local function fail(reason: string): BuyResult
	return { ok = false, bought = 0, reason = reason }
end

local function upgrade(player: Player, request: UpgradeRequest): BuyResult
	local data = DataService.get(player)
	if data == nil then
		return fail("NotLoaded")
	end
	local troopGear = data.gear[request.troopId]
	if troopGear == nil then
		return fail("Rejected")
	end
	if not Formulas.troopUnlocked(request.troopId, data.bestStage) then
		return fail("Locked")
	end
	local state: Types.GearSlotState = if request.slot == "weapon" then troopGear.weapon else troopGear.armor

	local cap = GearConfig.MAX_LEVEL - state.level
	if cap <= 0 then
		return fail("MaxReached")
	end
	if request.mode == "One" then
		cap = 1
	else
		cap = math.min(cap, GearConfig.MAX_LEVELS_PER_REQUEST)
	end

	local levels, cost = Formulas.gearMaxAffordable(request.troopId, state.level, data.gold, cap)
	if levels <= 0 or BigNum.lt(data.gold, cost) then
		return fail("CantAfford")
	end

	data.gold = BigNum.sub(data.gold, cost)
	state.level += levels
	CombatService.refreshArmy(player)
	ActivityService.record(player, "GearUpgrade", levels)
	DataService.markChanged(player)
	return { ok = true, bought = levels }
end

function GearService.start()
	local limiter = RateLimiter.new(GearConfig.REQUESTS_BURST, GearConfig.REQUESTS_PER_SECOND)

	RemoteService.onInvoke(
		Remotes.Functions.UpgradeGear,
		limiter,
		function(troopId: unknown, slot: unknown, mode: unknown): UpgradeRequest?
			local validId = Validate.keyOf(troopId, TroopConfig.TROOPS)
			local validSlot = Validate.oneOf(slot, GearConfig.SLOTS :: { string })
			local validMode = Validate.oneOf(mode, MODES)
			if validId == nil or validSlot == nil or validMode == nil then
				return nil
			end
			return {
				troopId = validId,
				slot = validSlot :: Types.GearSlot,
				mode = validMode :: GearBuyMode,
			}
		end,
		upgrade,
		REJECTED
	)
end

return GearService
