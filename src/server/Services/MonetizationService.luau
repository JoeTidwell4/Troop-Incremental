--!strict
-- Robux purchases. The client only opens Roblox's purchase prompt; everything a purchase
-- gives is granted here, on the server.
--
-- Game passes (owned forever): checked with UserOwnsGamePassAsync when you join, and
-- updated live by PromptGamePassPurchaseFinished. Owned passes are also set as Player
-- attributes ("Pass_<key>" = true) so the client can show "Owned" and cosmetics.
--
-- Developer products (consumable) go through ProcessReceipt, done the safe way:
--   1. Wait for the buyer's save to be loaded (or ask Roblox to retry later).
--   2. If this purchase id isn't in the save yet: grant it and record the id.
--   3. Save, and only answer PurchaseGranted once the saved copy contains the id.
--      Otherwise answer NotProcessedYet; Roblox retries, and step 2 won't grant twice.
-- This means a purchase is granted exactly once even if the server crashes mid-way.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = Shared:WaitForChild("Config")
local MonetizationConfig = require(Config:WaitForChild("MonetizationConfig"))
local AbilityConfig = require(Config:WaitForChild("AbilityConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local Validate = require(Server.Util.Validate)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local CombatService = require(Services.CombatService)
local ModifierService = require(Services.ModifierService)
local AbilityService = require(Services.AbilityService)
local TapService = require(Services.TapService)

type PlayerData = Types.PlayerData
type ProductDef = Types.ProductDef
type ToggleRequest = { passKey: string, enabled: boolean }

local owned: { [Player]: { [string]: boolean } } = {}
local passByid: { [number]: string } = {}
local productById: { [number]: ProductDef } = {}

local MonetizationService = {}

function MonetizationService.owns(player: Player, passKey: string): boolean
	local set = owned[player]
	return set ~= nil and set[passKey] == true
end

-- Owns a toggleable pass AND has it switched on.
function MonetizationService.isOn(player: Player, passKey: string): boolean
	local data = DataService.get(player)
	return MonetizationService.owns(player, passKey) and data ~= nil and data.passToggles[passKey] ~= false
end

local function setOwned(player: Player, passKey: string)
	local set = owned[player]
	if set == nil then
		set = {}
		owned[player] = set
	end
	set[passKey] = true
	player:SetAttribute("Pass_" .. passKey, true)
	DataService.markChanged(player)
end

local function checkPasses(player: Player)
	for passKey, def in MonetizationConfig.PASSES do
		if def.id > 0 then
			local ok, result = pcall(function(): boolean
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.id)
			end)
			if ok and result then
				setOwned(player, passKey)
			elseif not ok then
				warn(`[MonetizationService] couldn't check pass {passKey}: {result}`)
			end
		end
	end
end

local function notifyPurchase(player: Player, itemName: string)
	RemoteService.fireClient(Remotes.Events.Notice, player, { kind = "Purchase", stage = 0, itemName = itemName })
end

-- Gives what a developer product promises. Must not yield.
local function grantProduct(player: Player, data: PlayerData, product: ProductDef)
	if product.goldMinutes ~= nil then
		-- Your army's normal gold rate at your best cleared stage, at full efficiency.
		local stage = Formulas.offlineStage(data.highestStage)
		local gold = Formulas.offlineGold(
			CombatService.getDps(player),
			ModifierService.get(player).gold,
			stage,
			product.goldMinutes * 60,
			1
		)
		gold = BigNum.max(gold, BigNum.fromNumber(MonetizationConfig.GOLD_PRODUCT_MINIMUM))
		data.gold = BigNum.add(data.gold, gold)
		data.stats.lifetimeGold = BigNum.add(data.stats.lifetimeGold, gold)
	end
	if product.forgeTokens ~= nil then
		data.packs.forge += product.forgeTokens
	end
	DataService.markChanged(player)
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- granted next time they join
	end
	local product = productById[receipt.ProductId]
	if product == nil then
		warn(`[MonetizationService] unknown product id {receipt.ProductId}; check MonetizationConfig`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Wait (briefly) for their save to load.
	local data = DataService.get(player)
	local waited = 0
	while data == nil and waited < 15 and player.Parent ~= nil do
		task.wait(0.5)
		waited += 0.5
		data = DataService.get(player)
	end
	if data == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receipt.PurchaseId)
	if table.find(data.purchases, purchaseId) == nil then
		grantProduct(player, data, product)
		table.insert(data.purchases, purchaseId)
		while #data.purchases > MonetizationConfig.PURCHASE_HISTORY_SIZE do
			table.remove(data.purchases, 1)
		end
		notifyPurchase(player, product.displayName)
	end

	local saved = DataService.saveAndWait(player, function(savedData: any): boolean
		return typeof(savedData) == "table"
			and typeof(savedData.purchases) == "table"
			and table.find(savedData.purchases, purchaseId) ~= nil
	end, MonetizationConfig.RECEIPT_SAVE_TIMEOUT)
	return if saved then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
end

function MonetizationService.start()
	for passKey, def in MonetizationConfig.PASSES do
		if def.id > 0 then
			passByid[def.id] = passKey
		end
	end
	for _, def in MonetizationConfig.PRODUCTS do
		if def.id > 0 then
			productById[def.id] = def
		end
	end

	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		local passKey = passByid[passId]
		if purchased and passKey ~= nil then
			setOwned(player, passKey)
			notifyPurchase(player, MonetizationConfig.PASSES[passKey].displayName)
		end
	end)

	-- Pass bonuses that affect combat go through the shared multiplier hub.
	ModifierService.register(function(player: Player): ModifierService.PartialModifiers?
		local set = owned[player]
		if set == nil then
			return nil
		end
		local gold = 1
		for passKey in set do
			gold *= MonetizationConfig.PASSES[passKey].goldMultiplier or 1
		end
		return { gold = gold }
	end)

	DataService.ProfileLoaded:Connect(function(player: Player, _data: PlayerData)
		checkPasses(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		owned[player] = nil
	end)

	RemoteService.onEvent(
		Remotes.Events.SetPassToggle,
		RateLimiter.new(4, 2),
		function(passKey: unknown, enabled: unknown): ToggleRequest?
			local key = Validate.keyOf(passKey, MonetizationConfig.PASSES)
			local flag = Validate.boolean(enabled)
			if key == nil or flag == nil or not MonetizationConfig.PASSES[key].toggleable then
				return nil
			end
			return { passKey = key, enabled = flag }
		end,
		function(player: Player, request: ToggleRequest)
			local data = DataService.get(player)
			if data ~= nil then
				data.passToggles[request.passKey] = if request.enabled then nil else false
				DataService.markChanged(player)
			end
		end
	)

	-- Auto Abilities pass: fire whatever is ready (same checks as pressing the button).
	task.spawn(function()
		while true do
			task.wait(MonetizationConfig.AUTO_ABILITY_INTERVAL)
			for _, player in Players:GetPlayers() do
				if MonetizationService.isOn(player, "AutoAbilities") then
					for _, abilityId in AbilityService.getLoadout(player) do
						-- Fortify only works in boss fights; tryUse skips it otherwise.
						AbilityService.tryUse(player, abilityId)
					end
				end
			end
		end
	end)

	-- Auto Clicker pass: clicks on the server at a human pace, sharing the normal click cap.
	local clicksPerSecond = MonetizationConfig.PASSES.AutoClicker.autoClicksPerSecond or 0
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				if clicksPerSecond > 0 and MonetizationService.isOn(player, "AutoClicker") then
					TapService.addTaps(player, clicksPerSecond)
				end
			end
		end
	end)
end

return MonetizationService
