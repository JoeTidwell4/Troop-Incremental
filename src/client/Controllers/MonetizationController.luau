--!strict
-- Client side of the Robux store: opens Roblox's purchase prompts and reads which passes
-- you own (the server sets "Pass_<key>" attributes on your Player). The client never
-- grants anything itself. It also shows the Auto Clicker's clicks (sword swings, hit
-- flashes); the real auto clicks happen on the server.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local StateController = require(script.Parent.StateController)
local InputController = require(script.Parent.InputController)
local MonetizationConfig = require(Shared:WaitForChild("Config"):WaitForChild("MonetizationConfig"))

local toggleRemote: RemoteEvent? = nil
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

-- True if you own this toggleable pass and have it switched on.
function MonetizationController.isOn(passKey: string): boolean
	local snapshot = StateController.get()
	return MonetizationController.owns(passKey) and snapshot ~= nil and snapshot.passToggles[passKey] ~= false
end

function MonetizationController.setToggle(passKey: string, enabled: boolean)
	if toggleRemote ~= nil then
		toggleRemote:FireServer(passKey, enabled)
	end
end

function MonetizationController.start()
	toggleRemote = Remotes.waitForEvent(Remotes.Events.SetPassToggle)

	-- Show the Auto Clicker working: same visuals as a real click, no message to the server.
	local rate = MonetizationConfig.PASSES.AutoClicker.autoClicksPerSecond or 0
	if rate > 0 then
		task.spawn(function()
			while true do
				task.wait(1 / rate)
				local snapshot = StateController.get()
				if snapshot ~= nil and snapshot.encounter ~= nil and MonetizationController.isOn("AutoClicker") then
					InputController.Tapped:Fire()
				end
			end
		end)
	end
end

return MonetizationController
