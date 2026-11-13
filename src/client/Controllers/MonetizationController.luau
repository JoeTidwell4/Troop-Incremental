--!strict
-- Client side of the Robux store: opens Roblox's purchase prompts and reads which passes
-- you own (the server sets "Pass_<key>" attributes on your Player). The client never
-- grants anything itself.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local MonetizationConfig = require(Shared:WaitForChild("Config"):WaitForChild("MonetizationConfig"))

local autoRemote: RemoteEvent? = nil
local priceCache: { [string]: number } = {}

local MonetizationController = {}

function MonetizationController.owns(passKey: string): boolean
	return Players.LocalPlayer:GetAttribute("Pass_" .. passKey) == true
end

function MonetizationController.promptPass(passKey: string)
	local def = MonetizationConfig.PASSES[passKey]
	if def ~= nil and def.id > 0 and not MonetizationController.owns(passKey) then
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, def.id)
	end
end

function MonetizationController.promptProduct(productKey: string)
	local def = MonetizationConfig.PRODUCTS[productKey]
	if def ~= nil and def.id > 0 then
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, def.id)
	end
end

-- Robux price from Roblox (yields the first time, then cached). Nil if it can't be read.
function MonetizationController.getPrice(kind: "Pass" | "Product", id: number): number?
	local cacheKey = `{kind}{id}`
	local cached = priceCache[cacheKey]
	if cached ~= nil then
		return cached
	end
	local infoType = if kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
	local ok, info = pcall(function(): any
		return MarketplaceService:GetProductInfo(id, infoType)
	end)
	if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
		priceCache[cacheKey] = info.PriceInRobux
		return info.PriceInRobux
	end
	return nil
end

function MonetizationController.setAutoAbilities(enabled: boolean)
	if autoRemote ~= nil then
		autoRemote:FireServer(enabled)
	end
end

function MonetizationController.start()
	autoRemote = Remotes.waitForEvent(Remotes.Events.SetAutoAbilities)
end

return MonetizationController
