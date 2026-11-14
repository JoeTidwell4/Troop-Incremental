--!strict
-- Promo codes (PromoConfig): the owner makes them in the ADMIN panel (AdminService),
-- players redeem them in SETTINGS, once each. DataStore "PromoCodes": key "c_<CODE>" =
-- Types.PromoCode (uses counted with UpdateAsync, so a use limit holds across servers),
-- key "index" = the list of codes for the panel. Rewards go through DailyService.grant
-- (gold is held inside a challenge run like any other gold reward).

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local PromoConfig = require(Shared:WaitForChild("Config"):WaitForChild("PromoConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local StoreNames = require(Server.Util.StoreNames)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local DailyService = require(Services.DailyService)
local ActivityService = require(Services.ActivityService)

type PromoCode = Types.PromoCode
type RedeemResult = Types.RedeemResult

local store = DataStoreService:GetDataStore(StoreNames.of("PromoCodes"))
local busy: { [Player]: boolean } = {}

local PromoService = {}

-- "launch " -> "LAUNCH"; nil if it can't be a code.
function PromoService.normalize(raw: string): string?
	local code = string.upper((string.gsub(raw, "%s", "")))
	if #code < PromoConfig.CODE_MIN or #code > PromoConfig.CODE_MAX or not string.match(code, PromoConfig.CODE_PATTERN) then
		return nil
	end
	return code
end

-- Only known reward fields, whole numbers, within the caps; nil if nothing is left.
function PromoService.cleanRewards(raw: any): { [string]: number }?
	if typeof(raw) ~= "table" then
		return nil
	end
	local rewards: { [string]: number } = {}
	local any = false
	for _, field in PromoConfig.REWARD_ORDER do
		local value = raw[field]
		if typeof(value) == "number" and value == value and value >= 1 then
			rewards[field] = math.min(math.floor(value), PromoConfig.REWARDS[field].max)
			any = true
		end
	end
	return if any then rewards else nil
end

-- ADMIN: create or replace a code. Yields.
function PromoService.create(code: string, rewards: { [string]: number }, days: number, maxUses: number): (boolean, string?)
	local entry: PromoCode = {
		code = code,
		rewards = rewards,
		expiresAt = os.time() + math.floor(days * 86400),
		maxUses = maxUses,
		uses = 0,
	}
	local ok, err = pcall(function()
		store:UpdateAsync(`c_{code}`, function(old: any): any
			if typeof(old) == "table" and typeof(old.uses) == "number" then
				entry.uses = old.uses -- editing a code keeps its use count
			end
			return entry
		end)
		store:UpdateAsync("index", function(old: any): any
			local list: { string } = {}
			if typeof(old) == "table" then
				for _, other in old do
					if typeof(other) == "string" and other ~= code and #list < PromoConfig.MAX_CODES - 1 then
						table.insert(list, other)
					end
				end
			end
			table.insert(list, 1, code)
			return list
		end)
	end)
	return ok, if ok then nil else tostring(err)
end

-- ADMIN: delete a code (players who redeemed it keep their rewards). Yields.
function PromoService.delete(code: string): (boolean, string?)
	local ok, err = pcall(function()
		store:RemoveAsync(`c_{code}`)
		store:UpdateAsync("index", function(old: any): any
			local list: { string } = {}
			if typeof(old) == "table" then
				for _, other in old do
					if typeof(other) == "string" and other ~= code then
						table.insert(list, other)
					end
				end
			end
			return list
		end)
	end)
	return ok, if ok then nil else tostring(err)
end

-- ADMIN: every code with its use count. Yields.
function PromoService.list(): { PromoCode }
	local codes: { PromoCode } = {}
	local ok, index = pcall(function(): any
		return store:GetAsync("index")
	end)
	if not ok or typeof(index) ~= "table" then
		return codes
	end
	for _, code in index do
		local got, entry = pcall(function(): any
			return store:GetAsync(`c_{code}`)
		end)
		if got and typeof(entry) == "table" then
			table.insert(codes, entry)
		end
	end
	return codes
end

local function redeem(player: Player, raw: string): RedeemResult
	local code = PromoService.normalize(raw)
	if code == nil then
		return { ok = false, reason = "Invalid" }
	end
	local data = DataService.get(player)
	if data == nil then
		return { ok = false, reason = "NotLoaded" }
	end
	if data.codes.redeemed[code] then
		return { ok = false, reason = "Already" }
	end
	if busy[player] then
		return { ok = false, reason = "Busy" }
	end
	busy[player] = true
	local reason: string? = nil
	local rewards: { [string]: number }? = nil
	local ok = pcall(function()
		store:UpdateAsync(`c_{code}`, function(entry: any): any
			reason, rewards = nil, nil
			if typeof(entry) ~= "table" then
				reason = "Invalid"
				return nil -- cancels the write
			elseif os.time() > (entry.expiresAt or 0) then
				reason = "Expired"
				return nil
			elseif (entry.maxUses or 0) > 0 and (entry.uses or 0) >= entry.maxUses then
				reason = "UsedUp"
				return nil
			end
			entry.uses = (entry.uses or 0) + 1
			rewards = PromoService.cleanRewards(entry.rewards)
			return entry
		end)
	end)
	busy[player] = nil
	if not ok then
		return { ok = false, reason = "TryLater" }
	end
	if reason ~= nil or rewards == nil then
		return { ok = false, reason = reason or "Invalid" }
	end
	-- The save may have unloaded while the store answered.
	local fresh = DataService.get(player)
	if fresh == nil or fresh.codes.redeemed[code] then
		return { ok = false, reason = "Already" }
	end
	local given = rewards :: { [string]: number }
	fresh.codes.redeemed[code] = true
	DailyService.grant(player, fresh, {
		packs = given.packs,
		heroChests = given.heroChests,
		scrolls = given.scrolls,
		spins = given.spins,
		goldMinutes = given.goldMinutes,
	}, "Code")
	if given.dust ~= nil then
		fresh.relics.dust += given.dust
	end
	ActivityService.record(player, "CodeRedeemed", 1)
	DataService.markChanged(player)
	return { ok = true, rewards = given }
end

function PromoService.start()
	RemoteService.onInvoke(
		Remotes.Functions.RedeemCode,
		RateLimiter.new(PromoConfig.REDEEM_BURST, PromoConfig.REDEEM_PER_SECOND),
		function(code: unknown): string?
			if typeof(code) == "string" and #(code :: string) <= 40 then
				return code :: string
			end
			return nil
		end,
		redeem,
		{ ok = false, reason = "Slow" } :: RedeemResult
	)
end

return PromoService
