--!strict
-- Clan bank and perks.
--
-- Donations: gold is converted to Supplies at one Supply per kill's worth of gold at your
-- best stage this run, with a daily cap per member. The gold leaves your save right away
-- (session-locked, so it can't be double-spent); the Supplies are buffered on this server
-- and added to the clan record in one atomic UpdateAsync every FLUSH_INTERVAL. If a flush
-- fails, the batch goes back in the buffer and is retried. Buffered Supplies are shown in
-- the bank right away so donors see their donation.
--
-- Perks: bought by the Leader or Officers. The "enough Supplies?" and role checks run
-- inside UpdateAsync, so two officers buying at the same moment can't overspend the bank.
-- Perk bonuses go into ModifierService for every online member.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local ClanConfig = require(Shared:WaitForChild("Config"):WaitForChild("ClanConfig"))
local DataService = require(Services.DataService)
local ModifierService = require(Services.ModifierService)
local ClanService = require(Services.ClanService)
local ClanStore = require(Services.ClanStore)
local ActivityService = require(Services.ActivityService)

type ClanRecord = Types.ClanRecord
type ClanResult = Types.ClanResult
type PlayerData = Types.PlayerData

type Batch = { bank: number, donors: { [string]: number } }

local pending: { [string]: Batch } = {}

local function addBatch(target: Batch, batch: Batch)
	target.bank += batch.bank
	for userKey, amount in batch.donors do
		target.donors[userKey] = (target.donors[userKey] or 0) + amount
	end
end

-- Puts a batch back into the buffer after a failed write.
local function requeue(clanId: string, batch: Batch)
	local current = pending[clanId]
	if current == nil then
		pending[clanId] = batch
	else
		addBatch(current, batch)
	end
end

local function applyBatch(r: ClanRecord, batch: Batch?)
	if batch == nil then
		return
	end
	r.bank += batch.bank
	for userKey, amount in batch.donors do
		local member = r.members[userKey]
		if member ~= nil then
			member.donated += amount
		end
	end
end

local ClanBankService = {}

local function fail(reason: string): ClanResult
	return { ok = false, reason = reason }
end

local function perkLevel(record: ClanRecord, perkId: string): number
	return record.perks[perkId] or 0
end

-- Raid damage multiplier from the Warbanners-style perks (used by RaidService).
function ClanBankService.getRaidMultiplier(player: Player): number
	local record = ClanService.getClan(player)
	if record == nil then
		return 1
	end
	local multiplier = 1
	for perkId, def in ClanConfig.PERKS do
		local level = perkLevel(record, perkId)
		if def.raidMultiplier ~= nil and level > 0 then
			multiplier *= def.raidMultiplier ^ level
		end
	end
	return multiplier
end

local function donate(player: Player, data: PlayerData, amount: number): ClanResult
	local record = ClanService.getClan(player)
	if record == nil then
		return fail("NotInClan")
	end
	local today = Formulas.clanDay(os.time())
	if data.clanDonation.dayId ~= today then
		data.clanDonation.dayId = today
		data.clanDonation.amount = 0
	end
	local allowed = math.min(amount, ClanConfig.DONATION_DAILY_CAP - data.clanDonation.amount)
	if allowed <= 0 then
		return fail("DailyCapReached")
	end
	local price = Formulas.goldPerSupply(data.highestStage)
	-- Donate as much of the request as you can afford.
	local affordable = math.floor(BigNum.toNumber(BigNum.div(data.gold, price)))
	allowed = math.min(allowed, affordable)
	if allowed <= 0 then
		return fail("CantAfford")
	end

	data.gold = BigNum.sub(data.gold, BigNum.mulNumber(price, allowed))
	data.clanDonation.amount += allowed
	DataService.markChanged(player)

	local batch = pending[record.id]
	if batch == nil then
		batch = { bank = 0, donors = {} }
		pending[record.id] = batch
	end
	local userKey = tostring(player.UserId)
	batch.bank += allowed
	batch.donors[userKey] = (batch.donors[userKey] or 0) + allowed
	ClanService.pushClan(record.id)
	ActivityService.record(player, "Donate", allowed)
	return { ok = true }
end

local function buyPerk(player: Player, data: PlayerData, perkId: string): ClanResult
	if data.clanId == "" then
		return fail("NotInClan")
	end
	local def = ClanConfig.PERKS[perkId]
	local userKey = tostring(player.UserId)
	local clanId = data.clanId
	-- Include donations buffered on this server, so what the bank shows is what you can spend.
	local batch = pending[clanId]
	pending[clanId] = nil
	local record, reason = ClanStore.update(clanId, function(r: ClanRecord): (ClanRecord?, string?)
		applyBatch(r, batch)
		local me = r.members[userKey]
		if me == nil then
			return nil, "NotInClan"
		end
		if ClanService.roleRank(me.role) < ClanService.roleRank("Officer") then
			return nil, "NotAllowed"
		end
		local level = r.perks[perkId] or 0
		if level >= def.maxLevel then
			return nil, "MaxReached"
		end
		local cost = Formulas.clanPerkCost(perkId, level)
		if r.bank < cost then
			return nil, "NotEnoughSupplies"
		end
		r.bank -= cost
		r.perks[perkId] = level + 1
		return r, nil
	end)
	if record == nil then
		if batch ~= nil and reason ~= "ClanNotFound" then
			requeue(clanId, batch)
		end
		return fail(reason or "StoreError")
	end
	ClanService.afterChange(record)
	return { ok = true }
end

-- Sends buffered donations. Each clan's batch is taken out of the buffer first, so new
-- donations during the (yielding) write go into a fresh batch and aren't lost.
local function flush()
	local batches = pending
	pending = {}
	for clanId, batch in batches do
		local record, reason = ClanStore.update(clanId, function(r: ClanRecord): (ClanRecord?, string?)
			applyBatch(r, batch)
			return r, nil
		end)
		if record ~= nil then
			ClanService.afterChange(record)
		elseif reason ~= "ClanNotFound" then
			requeue(clanId, batch) -- retry next time
		end
	end
end

function ClanBankService.start()
	ClanService.bankBonus = function(clanId: string): number
		local batch = pending[clanId]
		return if batch ~= nil then batch.bank else 0
	end

	ClanService.registerAction("Donate", function(arg: unknown): (boolean, any)
		local valid = typeof(arg) == "number"
			and arg == arg
			and (arg :: number) % 1 == 0
			and (arg :: number) >= 1
			and (arg :: number) <= ClanConfig.DONATION_DAILY_CAP
		return valid, arg
	end, donate)

	ClanService.registerAction("BuyPerk", function(arg: unknown): (boolean, any)
		return typeof(arg) == "string" and ClanConfig.PERKS[arg :: string] ~= nil, arg
	end, buyPerk)

	ModifierService.register(function(player: Player): ModifierService.PartialModifiers?
		local record = ClanService.getClan(player)
		if record == nil then
			return nil
		end
		local result = { damage = 1, gold = 1, armyHp = 1 }
		for perkId, def in ClanConfig.PERKS do
			local level = perkLevel(record, perkId)
			if level > 0 then
				result.damage *= (def.damageMultiplier or 1) ^ level
				result.gold *= (def.goldMultiplier or 1) ^ level
				result.armyHp *= (def.armyHpMultiplier or 1) ^ level
			end
		end
		return result
	end)

	-- A clan's perks changed: online members' combat numbers change on the next read
	-- (ModifierService is read live), but their HUD needs a fresh snapshot.
	ClanService.ClanChanged:Connect(function(clanId: string)
		for _, player in Players:GetPlayers() do
			local data = DataService.get(player)
			if data ~= nil and data.clanId == clanId then
				DataService.markChanged(player)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(ClanConfig.FLUSH_INTERVAL)
			local ok, err = pcall(flush)
			if not ok then
				warn(`[ClanBankService] flush error: {err}`)
			end
		end
	end)
	game:BindToClose(function()
		pcall(flush)
	end)
end

return ClanBankService
