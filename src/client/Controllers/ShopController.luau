--!strict
-- Client side of everything you buy: troops, gear levels, and packs.
-- Each call asks the server and returns its answer. Calls yield and never throw.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))

type BuyResult = Types.BuyResult
type PackResult = Types.PackResult

local remotes: { [string]: RemoteFunction } = {}

local ShopController = {}

function ShopController.start()
	for _, name in Remotes.Functions do
		remotes[name] = Remotes.waitForFunction(name)
	end
end

local function invoke(name: string, ...: any): any
	local remote = remotes[name]
	if remote == nil then
		return nil
	end
	local args = table.pack(...)
	local ok, result = pcall(function(): any
		return remote:InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not ok or typeof(result) ~= "table" then
		return nil
	end
	return result
end

function ShopController.buyTroop(troopId: string, mode: Types.BuyMode): BuyResult
	local result = invoke(Remotes.Functions.BuyTroop, troopId, mode)
	return if result ~= nil then result :: BuyResult else { ok = false, bought = 0, reason = "NoResponse" }
end

function ShopController.upgradeGear(troopId: string, slot: Types.GearSlot, mode: Types.GearBuyMode): BuyResult
	local result = invoke(Remotes.Functions.UpgradeGear, troopId, slot, mode)
	return if result ~= nil then result :: BuyResult else { ok = false, bought = 0, reason = "NoResponse" }
end

function ShopController.openPack(useFree: boolean): PackResult
	local result = invoke(Remotes.Functions.OpenPack, useFree)
	return if result ~= nil then result :: PackResult else { ok = false, reason = "NoResponse" }
end

return ShopController
