--!strict
-- The Mystery Merchant (MerchantConfig): visit schedule (real time, os.time), the offers
-- he brings, and buying them. Each offer is exactly what its label says; only WHICH
-- offers come is random. Gold prices are kills' worth at the ALL-TIME best stage, because
-- everything he sells is kept on Ascend.

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
local MerchantConfig = require(Config:WaitForChild("MerchantConfig"))
local GeneralConfig = require(Config:WaitForChild("GeneralConfig"))
local RelicConfig = require(Config:WaitForChild("RelicConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)
local ActivityService = require(Services.ActivityService)
local GeneralService = require(Services.GeneralService)
local RelicService = require(Services.RelicService)
local CommanderService = require(Services.CommanderService)

type PlayerData = Types.PlayerData
type Offer = Types.MerchantOffer
type Result = { ok: boolean, reason: string? }

local random = Random.new()

local MerchantService = {}

local function unlocked(data: PlayerData): boolean
	return data.bestStage >= MerchantConfig.UNLOCK_STAGE
end

local function goldPrice(data: PlayerData, kills: number): BigNum.BigNum
	return BigNum.round(BigNum.mulNumber(Formulas.goldPerKill(data.bestStage), kills))
end

local function weightedKey(weights: { [string]: number }): string
	local total = 0
	for _, w in weights do
		total += w
	end
	local value = random:NextNumber() * total
	local last = ""
	for key, w in weights do
		last = key
		value -= w
		if value < 0 then
			return key
		end
	end
	return last
end

local function makeOffer(data: PlayerData, kind: string): Offer?
	if kind == "General" then
		local rarity = weightedKey(MerchantConfig.GENERAL_RARITY)
		local pool: { string } = {}
		for _, generalId in GeneralConfig.ORDER do
			if GeneralConfig.GENERALS[generalId].rarity == rarity then
				table.insert(pool, generalId)
			end
		end
		local price = MerchantConfig.GENERAL_HONOR[rarity]
		return {
			kind = kind,
			item = pool[random:NextInteger(1, #pool)],
			rarity = rarity,
			amount = 1,
			currency = "Honor",
			price = BigNum.round(Formulas.scaledHonor(data.bestStage, price.share, price.min)),
		}
	elseif kind == "Relic" then
		local weights: { [string]: number } = {}
		local dust: { [string]: number } = {}
		for _, entry in MerchantConfig.RELIC do
			weights[entry.rarity] = entry.weight
			dust[entry.rarity] = entry.dust
		end
		local rarity = weightedKey(weights)
		local slot = RelicConfig.SLOTS[random:NextInteger(1, #RelicConfig.SLOTS)]
		local set = RelicConfig.SET_ORDER[random:NextInteger(1, #RelicConfig.SET_ORDER)]
		return { kind = kind, item = `{slot}:{set}`, rarity = rarity, amount = 1, currency = "Dust", price = BigNum.fromNumber(dust[rarity]) }
	elseif kind == "Scrolls" then
		return { kind = kind, item = "", rarity = "", amount = MerchantConfig.SCROLLS.amount, currency = "Gold", price = goldPrice(data, MerchantConfig.SCROLLS.kills) }
	elseif kind == "HeroChest" then
		return { kind = kind, item = "", rarity = "", amount = 1, currency = "Gold", price = goldPrice(data, MerchantConfig.HERO_CHEST.kills) }
	elseif kind == "DustBundle" then
		return { kind = kind, item = "", rarity = "", amount = MerchantConfig.DUST_BUNDLE.amount, currency = "Gold", price = goldPrice(data, MerchantConfig.DUST_BUNDLE.kills) }
	elseif kind == "Cosmetic" then
		local missing: { string } = {}
		for _, itemId in MerchantConfig.COSMETICS do
			if not data.commander.owned[itemId] then
				table.insert(missing, itemId)
			end
		end
		if #missing == 0 then
			return nil -- he has nothing new for you
		end
		return { kind = kind, item = missing[random:NextInteger(1, #missing)], rarity = "", amount = 1, currency = "Gold", price = goldPrice(data, MerchantConfig.COSMETIC_KILLS) }
	end
	return nil
end

local function arrive(player: Player, data: PlayerData, now: number)
	local merchant = data.merchant
	local pool = table.clone(MerchantConfig.KINDS)
	local offers: { Offer } = {}
	while #offers < MerchantConfig.OFFER_COUNT and #pool > 0 do
		local total = 0
		for _, kind in pool do
			total += kind.weight
		end
		local value = random:NextNumber() * total
		local pick = #pool
		for i, kind in pool do
			value -= kind.weight
			if value < 0 then
				pick = i
				break
			end
		end
		local kind = table.remove(pool, pick)
		local offer = if kind ~= nil then makeOffer(data, kind.id) else nil
		if offer ~= nil then
			table.insert(offers, offer)
		end
	end
	merchant.offers = offers
	merchant.bought = {}
	merchant.leaveAt = now + MerchantConfig.STAY
	if SyncService.isReady(player) then
		RemoteService.fireClient(Remotes.Events.Notice, player, { kind = "MerchantArrived", stage = 0 })
	end
end

local function leave(data: PlayerData, now: number)
	local merchant = data.merchant
	merchant.leaveAt = 0
	merchant.offers = {}
	merchant.bought = {}
	merchant.nextAt = now + random:NextInteger(MerchantConfig.GAP_MIN, MerchantConfig.GAP_MAX)
end

-- Moves the schedule along. `loading`: the player just joined (a visit that ended while
-- they were away is replaced by a fresh one right now). Returns true if anything changed.
local function update(player: Player, data: PlayerData, loading: boolean): boolean
	if not unlocked(data) then
		return false
	end
	local merchant = data.merchant
	local now = os.time()
	if merchant.nextAt == 0 and merchant.leaveAt == 0 then
		merchant.nextAt = now + MerchantConfig.FIRST_VISIT
		return true
	end
	if merchant.leaveAt > 0 then
		if now < merchant.leaveAt then
			return false
		end
		if loading then
			arrive(player, data, now) -- he came while you were away: he's here now
		else
			leave(data, now)
		end
		return true
	end
	if now >= merchant.nextAt then
		arrive(player, data, now)
		return true
	end
	return false
end

local function canPay(data: PlayerData, offer: Offer): boolean
	if offer.currency == "Gold" then
		return BigNum.gte(data.gold, offer.price)
	elseif offer.currency == "Honor" then
		return BigNum.gte(data.honor, offer.price)
	end
	return data.relics.dust >= BigNum.toNumber(offer.price)
end

local function pay(data: PlayerData, offer: Offer)
	if offer.currency == "Gold" then
		data.gold = BigNum.sub(data.gold, offer.price)
	elseif offer.currency == "Honor" then
		data.honor = BigNum.sub(data.honor, offer.price)
	else
		data.relics.dust -= math.floor(BigNum.toNumber(offer.price))
	end
end

local function buy(player: Player, data: PlayerData, index: number): Result
	local merchant = data.merchant
	if merchant.leaveAt == 0 or os.time() >= merchant.leaveAt then
		return { ok = false, reason = "Gone" }
	end
	local offer = merchant.offers[index]
	if offer == nil then
		return { ok = false, reason = "Rejected" }
	end
	if merchant.bought[tostring(index)] then
		return { ok = false, reason = "SoldOut" }
	end
	if offer.kind == "Cosmetic" and data.commander.owned[offer.item] then
		return { ok = false, reason = "Owned" }
	end
	if not canPay(data, offer) then
		return { ok = false, reason = "CantAfford" }
	end
	pay(data, offer)
	merchant.bought[tostring(index)] = true
	if offer.kind == "General" then
		GeneralService.addCopyOf(player, data, offer.item)
	elseif offer.kind == "Relic" then
		local slot, set = string.match(offer.item, "^(%w+):(%w+)$")
		RelicService.drop(player, data, nil, { slot = slot or RelicConfig.SLOTS[1], set = set or RelicConfig.SET_ORDER[1], rarity = offer.rarity })
	elseif offer.kind == "Scrolls" then
		data.generals.scrolls += offer.amount
	elseif offer.kind == "HeroChest" then
		data.packs.hero += offer.amount
	elseif offer.kind == "DustBundle" then
		data.relics.dust += offer.amount
	elseif offer.kind == "Cosmetic" then
		CommanderService.grant(player, offer.item)
	end
	ActivityService.record(player, "MerchantBuy", 1)
	DataService.markChanged(player)
	return { ok = true }
end

---------------------------------------------------------------- Studio test panel

function MerchantService.debugArrive(player: Player)
	local data = DataService.get(player)
	if data ~= nil then
		arrive(player, data, os.time())
		DataService.markChanged(player)
	end
end

function MerchantService.debugLeave(player: Player)
	local data = DataService.get(player)
	if data ~= nil then
		leave(data, os.time())
		DataService.markChanged(player)
	end
end

function MerchantService.start()
	DataService.ProfileLoaded:Connect(function(player: Player, data: PlayerData)
		update(player, data, true)
	end)
	SyncService.ClientReady:Connect(function(player: Player)
		local data = DataService.get(player)
		if data ~= nil and data.merchant.leaveAt > os.time() then
			RemoteService.fireClient(Remotes.Events.Notice, player, { kind = "MerchantArrived", stage = 0 })
		end
	end)
	task.spawn(function()
		while true do
			task.wait(5)
			for _, player in Players:GetPlayers() do
				local data = DataService.get(player)
				if data ~= nil and update(player, data, false) then
					DataService.markChanged(player)
				end
			end
		end
	end)

	SyncService.addSnapshotFields(function(_player: Player, data: PlayerData): { [string]: any }
		return { merchant = data.merchant }
	end)

	RemoteService.onInvoke(
		Remotes.Functions.MerchantRequest,
		RateLimiter.new(MerchantConfig.REQUESTS_BURST, MerchantConfig.REQUESTS_PER_SECOND),
		function(action: unknown, index: unknown): number?
			if action ~= "Buy" or typeof(index) ~= "number" or index ~= math.floor(index :: number) then
				return nil
			end
			if (index :: number) < 1 or (index :: number) > MerchantConfig.OFFER_COUNT then
				return nil
			end
			return index :: number
		end,
		function(player: Player, index: number): Result
			local data = DataService.get(player)
			if data == nil then
				return { ok = false, reason = "NotLoaded" }
			end
			return buy(player, data, index)
		end,
		{ ok = false, reason = "Rejected" } :: Result
	)
end

return MerchantService
