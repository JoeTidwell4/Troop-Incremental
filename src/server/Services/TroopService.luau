--!strict
-- Handles troop purchases. The client only says WHAT it wants to buy; the server
-- works out the price, checks the player can afford it, and spends the gold.
-- There are no yields between the check and the spend, so two quick requests can't
-- both spend the same gold.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = Shared:WaitForChild("Config")
local TroopConfig = require(Config:WaitForChild("TroopConfig"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local Validate = require(Server.Util.Validate)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local CombatService = require(Services.CombatService)

type BuyMode = Types.BuyMode
type BuyResult = Types.BuyResult
type BuyRequest = { troopId: string, mode: BuyMode }

local BUY_MODES: { string } = { "One", "Ten", "Max" }
local REJECTED: BuyResult = { ok = false, bought = 0, reason = "Rejected" }

local TroopService = {}

local function fail(reason: string): BuyResult
	return { ok = false, bought = 0, reason = reason }
end

local function buy(player: Player, request: BuyRequest): BuyResult
	local data = DataService.get(player)
	if data == nil then
		return fail("NotLoaded")
	end

	local troopId = request.troopId
	local owned = data.troops[troopId] or 0
	local cap = math.min(TroopConfig.MAX_BUY_PER_REQUEST, TroopConfig.MAX_PER_TYPE - owned)
	if cap <= 0 then
		return fail("MaxReached")
	end

	local amount: number
	local cost: BigNum.BigNum
	if request.mode == "Max" then
		amount, cost = Formulas.maxAffordable(troopId, owned, data.gold, cap)
	else
		amount = if request.mode == "Ten" then 10 else 1
		if amount > cap then
			return fail("MaxReached")
		end
		cost = Formulas.troopCost(troopId, owned, amount)
	end

	if amount <= 0 or BigNum.lt(data.gold, cost) then
		return fail("CantAfford")
	end

	data.gold = BigNum.sub(data.gold, cost)
	data.troops[troopId] = owned + amount
	CombatService.refreshArmy(player)
	DataService.markChanged(player)
	return { ok = true, bought = amount }
end

function TroopService.start()
	local limiter = RateLimiter.new(EconomyConfig.BUY_REQUESTS_BURST, EconomyConfig.BUY_REQUESTS_PER_SECOND)

	RemoteService.onInvoke(Remotes.Functions.BuyTroop, limiter, function(troopId: unknown, mode: unknown): BuyRequest?
		local validId = Validate.keyOf(troopId, TroopConfig.TROOPS)
		local validMode = Validate.oneOf(mode, BUY_MODES)
		if validId == nil or validMode == nil then
			return nil
		end
		return { troopId = validId, mode = validMode :: BuyMode }
	end, buy, REJECTED)
end

return TroopService
