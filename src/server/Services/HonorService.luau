--!strict
-- Honor shop: permanent upgrades bought with Honor. Their combat bonuses go into
-- ModifierService; starting gold and offline bonuses are read by AscendService and
-- OfflineService through the helpers below.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local HonorConfig = require(Shared:WaitForChild("Config"):WaitForChild("HonorConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local Validate = require(Server.Util.Validate)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local CombatService = require(Services.CombatService)
local ModifierService = require(Services.ModifierService)
local Analytics = require(Services.AnalyticsService)

type BuyResult = Types.BuyResult

local REJECTED: BuyResult = { ok = false, bought = 0, reason = "Rejected" }

local HonorService = {}

local function levelOf(data: Types.PlayerData, upgradeId: string): number
	return data.honorUpgrades[upgradeId] or 0
end

-- Extra offline hours and efficiency from Honor upgrades.
function HonorService.getOfflineBonus(player: Player): (number, number)
	local data = DataService.get(player)
	if data == nil then
		return 0, 0
	end
	local hours, efficiency = 0, 0
	for upgradeId, def in HonorConfig.UPGRADES do
		local level = levelOf(data, upgradeId)
		hours += (def.offlineHoursPerLevel or 0) * level
		efficiency += (def.offlineEfficiencyPerLevel or 0) * level
	end
	return hours, efficiency
end

local function buyUpgrade(player: Player, upgradeId: string): BuyResult
	local data = DataService.get(player)
	local def = HonorConfig.UPGRADES[upgradeId]
	if data == nil or def == nil then
		return { ok = false, bought = 0, reason = "NotLoaded" }
	end
	local level = levelOf(data, upgradeId)
	if def.maxLevel ~= nil and level >= def.maxLevel then
		return { ok = false, bought = 0, reason = "MaxReached" }
	end
	local cost = Formulas.honorUpgradeCost(upgradeId, level)
	if BigNum.lt(data.honor, cost) then
		return { ok = false, bought = 0, reason = "CantAffordHonor" }
	end

	data.honor = BigNum.sub(data.honor, cost)
	data.honorUpgrades[upgradeId] = level + 1
	Analytics.honor(player, "Sink", cost, data.honor, "HonorShop", upgradeId)
	CombatService.refreshArmy(player)
	DataService.markChanged(player)
	return { ok = true, bought = 1 }
end

function HonorService.start()
	ModifierService.register(function(player: Player): ModifierService.PartialModifiers?
		local data = DataService.get(player)
		if data == nil then
			return nil
		end
		local result = { damage = 1, gold = 1, armyHp = 1, tap = 1 }
		for upgradeId, def in HonorConfig.UPGRADES do
			local level = levelOf(data, upgradeId)
			if level > 0 then
				result.damage *= (def.damageMultiplier or 1) ^ level
				result.gold *= (def.goldMultiplier or 1) ^ level
				result.armyHp *= (def.armyHpMultiplier or 1) ^ level
				result.tap *= (def.tapMultiplier or 1) ^ level
			end
		end
		return result
	end)

	local limiter = RateLimiter.new(HonorConfig.REQUESTS_BURST, HonorConfig.REQUESTS_PER_SECOND)
	RemoteService.onInvoke(Remotes.Functions.BuyHonorUpgrade, limiter, function(upgradeId: unknown): string?
		return Validate.keyOf(upgradeId, HonorConfig.UPGRADES)
	end, buyUpgrade, REJECTED)
end

return HonorService
