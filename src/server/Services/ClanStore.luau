--!strict
-- All cross-server storage for clans. Rules live in ClanService / ClanBankService /
-- RaidService; this file only reads and writes. Every call is pcall-wrapped.
--
-- Where things live:
--   DataStore "Clans"        "clan_{id}"   -> ClanRecord (source of truth for membership)
--   DataStore "ClanNames"    "name_{lower}" -> clan id (makes names unique)
--   DataStore "ClanRaid"     "raid_{id}_{week}" -> raid progress (Phase 5b)
--   OrderedDataStore "OpenClans" key = clan id, value = member count (only open, non-full clans)
--   MessagingService topic "ClanUpdate" -> clan id ("refresh this clan now")
--   OrderedDataStore "ClanWar_{week}" key = clan id, value = that week's clan XP (only goes up)
--   DataStore "ClanWarResult" "result_{week}" -> final top list, written once (set-if-absent)
--
-- Race conditions: every change to a clan goes through UpdateAsync, which re-runs the
-- change on the freshest stored value if another server wrote in between. Checks like
-- "is the clan full?" or "does the bank have enough?" happen INSIDE that function, so two
-- servers can't both pass a check that only one should.

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))

type ClanRecord = Types.ClanRecord

local clanStore = DataStoreService:GetDataStore("Clans")
local nameStore = DataStoreService:GetDataStore("ClanNames")
local raidStore = DataStoreService:GetDataStore("ClanRaid")
local openList = DataStoreService:GetOrderedDataStore("OpenClans")
local warResultStore = DataStoreService:GetDataStore("ClanWarResult")

local TOPIC = "ClanUpdate"

local ClanStore = {}

local function warn_(what: string, err: any)
	warn(`[ClanStore] {what} failed: {err}`)
end

local function nameKey(name: string): string
	return "name_" .. string.lower(name)
end

-- Reserves the name and writes the new clan. Returns (ok, reason).
function ClanStore.create(record: ClanRecord): (boolean, string?)
	local reserved = false
	local ok, err = pcall(function()
		nameStore:UpdateAsync(nameKey(record.name), function(old: any): any
			if old ~= nil then
				return nil -- name taken
			end
			reserved = true
			return record.id
		end)
	end)
	if not ok then
		warn_("reserve name", err)
		return false, "StoreError"
	end
	if not reserved then
		return false, "NameTaken"
	end
	local saved, saveErr = pcall(function()
		clanStore:SetAsync("clan_" .. record.id, record)
	end)
	if not saved then
		warn_("create clan", saveErr)
		pcall(function()
			nameStore:RemoveAsync(nameKey(record.name))
		end)
		return false, "StoreError"
	end
	return true, nil
end

-- Returns (record or nil, requestSucceeded). (nil, true) means the clan doesn't exist;
-- (nil, false) means the store couldn't be reached, so don't treat it as deleted.
function ClanStore.get(clanId: string): (ClanRecord?, boolean)
	local ok, result = pcall(function(): any
		return clanStore:GetAsync("clan_" .. clanId)
	end)
	if not ok then
		warn_("get clan", result)
		return nil, false
	end
	if typeof(result) == "table" then
		return result :: ClanRecord, true
	end
	return nil, true
end

-- Atomically changes a clan. `change` gets the current record and returns either
-- (newRecord, nil) to save, or (nil, reason) to cancel. It may run more than once.
-- Returns (savedRecord, nil) on success or (nil, reason) on failure.
function ClanStore.update(clanId: string, change: (ClanRecord) -> (ClanRecord?, string?)): (ClanRecord?, string?)
	local reason: string? = nil
	local saved: ClanRecord? = nil
	local ok, err = pcall(function()
		clanStore:UpdateAsync("clan_" .. clanId, function(old: any): any
			reason = nil
			if typeof(old) ~= "table" then
				reason = "ClanNotFound"
				return nil
			end
			local new, why = change(old :: ClanRecord)
			if new == nil then
				reason = why or "Rejected"
				return nil
			end
			new.version = (new.version or 0) + 1
			saved = new
			return new
		end)
	end)
	if not ok then
		warn_("update clan", err)
		return nil, "StoreError"
	end
	if saved == nil then
		return nil, reason or "Rejected"
	end
	return saved, nil
end

-- Deletes a clan (after its last member leaves) and frees its name.
function ClanStore.delete(record: ClanRecord)
	pcall(function()
		clanStore:RemoveAsync("clan_" .. record.id)
	end)
	pcall(function()
		nameStore:RemoveAsync(nameKey(record.name))
	end)
	pcall(function()
		openList:RemoveAsync(record.id)
	end)
end

function ClanStore.findByName(name: string): string?
	local ok, result = pcall(function(): any
		return nameStore:GetAsync(nameKey(name))
	end)
	if ok and typeof(result) == "string" then
		return result
	end
	return nil
end

-- Keeps the browse list in step with a clan: listed while it has free spots. Closed
-- clans are listed too (players send them join requests instead of joining).
function ClanStore.updateListing(record: ClanRecord, maxMembers: number)
	local listed = record.memberCount < maxMembers and record.memberCount > 0
	local ok, err = pcall(function()
		if listed then
			openList:SetAsync(record.id, record.memberCount)
		else
			openList:RemoveAsync(record.id)
		end
	end)
	if not ok then
		warn_("update listing", err)
	end
end

-- Open clans with free spots, most members first: { id, memberCount }.
function ClanStore.listOpen(count: number): { { id: string, memberCount: number } }?
	local ok, result = pcall(function(): any
		return openList:GetSortedAsync(false, count):GetCurrentPage()
	end)
	if not ok or typeof(result) ~= "table" then
		return nil
	end
	local list: { { id: string, memberCount: number } } = {}
	for _, entry in result do
		table.insert(list, { id = tostring(entry.key), memberCount = tonumber(entry.value) or 0 })
	end
	return list
end

---------------------------------------------------------------- raid (Phase 5b)

local function raidKey(clanId: string, weekId: number): string
	return `raid_{clanId}_{weekId}`
end

-- Returns (raid progress or nil, requestSucceeded). (nil, true) = nothing recorded yet.
function ClanStore.getRaid(clanId: string, weekId: number): (any, boolean)
	local ok, result = pcall(function(): any
		return raidStore:GetAsync(raidKey(clanId, weekId))
	end)
	if not ok then
		warn_("get raid", result)
		return nil, false
	end
	if typeof(result) == "table" then
		return result, true
	end
	return nil, true
end

-- Atomically changes a raid record (created empty if missing). Returns the saved value or nil.
function ClanStore.updateRaid(clanId: string, weekId: number, change: (any) -> any): any
	local saved: any = nil
	local ok, err = pcall(function()
		raidStore:UpdateAsync(raidKey(clanId, weekId), function(old: any): any
			local current = if typeof(old) == "table" then old else { units = 0, contributors = {} }
			saved = change(current)
			return saved
		end)
	end)
	if not ok then
		warn_("update raid", err)
		return nil
	end
	return saved
end

---------------------------------------------------------------- clan war

export type WarScore = { clanId: string, xp: number }

local function warBoard(weekId: number): OrderedDataStore
	return DataStoreService:GetOrderedDataStore(`ClanWar_{weekId}`)
end

-- Raises a clan's score for a week. Keeps the higher value, so two servers reporting at
-- the same moment can't lower it.
function ClanStore.setWarScore(weekId: number, clanId: string, xp: number)
	local ok, err = pcall(function()
		warBoard(weekId):UpdateAsync(clanId, function(old: any): any
			local value = math.floor(xp)
			if typeof(old) == "number" and old >= value then
				return nil -- already as high or higher
			end
			return value
		end)
	end)
	if not ok then
		warn_("set war score", err)
	end
end

-- Top clans of a week, highest first. Nil if the store couldn't be reached.
function ClanStore.getWarTop(weekId: number, count: number): { WarScore }?
	local ok, result = pcall(function(): any
		local page = warBoard(weekId):GetSortedAsync(false, count):GetCurrentPage()
		local list: { WarScore } = {}
		for _, entry in page do
			table.insert(list, { clanId = entry.key, xp = entry.value })
		end
		return list
	end)
	if not ok then
		warn_("get war top", result)
		return nil
	end
	return result
end

-- The locked-in results of a finished week: the first server to call this with `top`
-- writes it; everyone gets back the same stored list. With `top` = nil it only reads.
-- Returns (list or nil, requestSucceeded).
function ClanStore.warResult(weekId: number, top: { WarScore }?): ({ WarScore }?, boolean)
	local stored: any = nil
	local ok, err = pcall(function()
		if top == nil then
			stored = warResultStore:GetAsync(`result_{weekId}`)
			return
		end
		warResultStore:UpdateAsync(`result_{weekId}`, function(old: any): any
			if typeof(old) == "table" then
				stored = old
				return nil -- already decided
			end
			stored = top
			return top
		end)
	end)
	if not ok then
		warn_("war result", err)
		return nil, false
	end
	return if typeof(stored) == "table" then stored else nil, true
end

---------------------------------------------------------------- live nudges

-- Tells every server "this clan changed, re-read it". Best effort: if it's lost,
-- servers still pick up the change on their next poll.
function ClanStore.publish(clanId: string)
	task.spawn(function()
		pcall(function()
			MessagingService:PublishAsync(TOPIC, clanId)
		end)
	end)
end

function ClanStore.subscribe(callback: (clanId: string) -> ())
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(TOPIC, function(message: any)
				if typeof(message) == "table" and typeof(message.Data) == "string" then
					callback(message.Data)
				end
			end)
		end)
		if not ok then
			warn_("subscribe", err)
		end
	end)
end

return ClanStore
