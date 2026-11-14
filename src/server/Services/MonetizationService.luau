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

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local MessagingService = game:GetService("MessagingService")
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
local PromoConfig = require(Config:WaitForChild("PromoConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local StoreNames = require(Server.Util.StoreNames)
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

-- Free passes the owner gives from the ADMIN panel (AdminService): DataStore "PassGrants",
-- key "u<userId>" = { passKeys }, plus key "index" = the list shown in the panel. A
-- MessagingService nudge makes other servers re-check a player who's online right now.
local grantStore = DataStoreService:GetDataStore(StoreNames.of("PassGrants"))
local GRANT_TOPIC = StoreNames.of("PassGrant")
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
	-- Comped passes (MonetizationConfig.FREE_PASSES and the ADMIN panel's grants): owned
	-- without buying.
	local comps = table.clone(MonetizationConfig.FREE_PASSES[player.UserId] or {})
	local ok, stored = pcall(function(): any
		return grantStore:GetAsync(`u{player.UserId}`)
	end)
	if ok and typeof(stored) == "table" then
		for _, passKey in stored do
			table.insert(comps, passKey)
		end
	end
	for _, passKey in comps do
		if typeof(passKey) == "string" and MonetizationConfig.PASSES[passKey] ~= nil then
			setOwned(player, passKey)
		end
	end
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
	if product.goldMinutes ~= nil and data.challenge.active ~= "" then
		-- Bought inside a challenge run: held, and paid out on the main run when the
		-- challenge ends (ChallengeService), so it's never lost with the challenge's gold.
		data.challenge.goldMinutes += product.goldMinutes
	elseif product.goldMinutes ~= nil then
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

-- Forget what this player owns and check again (after a free pass is given or taken).
local function recheck(player: Player)
	owned[player] = {}
	for passKey in MonetizationConfig.PASSES do
		player:SetAttribute("Pass_" .. passKey, nil)
	end
	checkPasses(player)
	DataService.markChanged(player)
end

-- ADMIN panel: give `userId` exactly these free passes ({} = take them all away). Yields.
function MonetizationService.setGrant(userId: number, name: string, passes: { string }): (boolean, string?)
	local key = `u{userId}`
	local ok, err = pcall(function()
		if #passes == 0 then
			grantStore:RemoveAsync(key)
		else
			grantStore:SetAsync(key, passes)
		end
		grantStore:UpdateAsync("index", function(old: any): any
			local list: { Types.PassGrant } = {}
			if typeof(old) == "table" then
				for _, entry in old do
					if typeof(entry) == "table" and entry.userId ~= userId and #list < PromoConfig.MAX_GRANTS - 1 then
						table.insert(list, entry)
					end
				end
			end
			if #passes > 0 then
				table.insert(list, 1, { userId = userId, name = name, passes = passes })
			end
			return list
		end)
	end)
	if not ok then
		return false, tostring(err)
	end
	local online = Players:GetPlayerByUserId(userId)
	if online ~= nil then
		task.spawn(recheck, online)
	end
	pcall(function()
		MessagingService:PublishAsync(GRANT_TOPIC, userId)
	end)
	return true, nil
end

-- ADMIN panel: everyone who has free passes. Yields.
function MonetizationService.listGrants(): { Types.PassGrant }
	local ok, list = pcall(function(): any
		return grantStore:GetAsync("index")
	end)
	return if ok and typeof(list) == "table" then list else {}
end

function MonetizationService.start()
	task.spawn(function()
		pcall(function()
			MessagingService:SubscribeAsync(GRANT_TOPIC, function(message: any)
				local userId = tonumber(message.Data)
				local player = if userId ~= nil then Players:GetPlayerByUserId(userId) else nil
				if player ~= nil then
					recheck(player)
				end
			end)
		end)
	end)
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
