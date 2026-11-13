--!strict
-- All cross-server storage for the faction war. Game rules live in WarService; this file
-- only reads and writes. Every call is wrapped in pcall and returns nil/false on failure,
-- so a storage outage never breaks gameplay (points stay buffered and retry later).
--
-- Where things live:
--   MemoryStore HashMap "FactionWar"       live totals, key "w{week}:{faction}:{shard}"
--                                           value { p = points, a = active members }
--   MemoryStore HashMap "FactionWarMeta"   "leader" lock { job = JobId, untilTime = os.time }
--   DataStore "FactionWar"                 "backup_{week}" totals copy (leader only)
--                                           "result_{week}" final result (written once)
--   OrderedDataStore "WarTop_{week}_{faction}"  per-player weekly points (leaderboard)
--
-- Why this split:
--   * MemoryStore UpdateAsync is atomic and fast: many servers can add to the same total
--     without losing updates. Totals are split into SHARDS keys to spread the load.
--   * DataStore keys allow ~1 write per 6 seconds, too slow for a hot shared counter,
--     but they're permanent: used for the backup and the one-time final result.
--   * OrderedDataStore can sort by value (whole numbers only) for the top contributors.
--     Each player writes only their own key, so servers never fight over one entry.

local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local StoreNames = require(script.Parent.Parent.Util.StoreNames)
local FactionConfig = require(Shared:WaitForChild("Config"):WaitForChild("FactionConfig"))

type WarResult = Types.WarResult

-- Raw totals per faction: points and active members (averages are computed by WarService).
export type Totals = { [string]: { points: number, active: number } }

local totalsMap = MemoryStoreService:GetHashMap(StoreNames.of("FactionWar"))
local metaMap = MemoryStoreService:GetHashMap(StoreNames.of("FactionWarMeta"))
local warStore = DataStoreService:GetDataStore(StoreNames.of("FactionWar"))

local WarStore = {}

local function warn_(what: string, err: any)
	warn(`[WarStore] {what} failed: {err}`)
end

local function totalsKey(weekId: number, factionId: string, shard: number): string
	return `w{weekId}:{factionId}:{shard}`
end

local function emptyTotals(): Totals
	local totals: Totals = {}
	for _, factionId in FactionConfig.ORDER do
		totals[factionId] = { points = 0, active = 0 }
	end
	return totals
end

-- Atomically adds points (and newly active members) to one shard. Returns true on success.
function WarStore.addPoints(weekId: number, factionId: string, shard: number, points: number, newActive: number): boolean
	local ok, err = pcall(function()
		totalsMap:UpdateAsync(totalsKey(weekId, factionId, shard), function(old: any): any
			local current = if typeof(old) == "table" then old else { p = 0, a = 0 }
			return { p = (current.p or 0) + points, a = (current.a or 0) + newActive }
		end, FactionConfig.MEMORY_EXPIRATION)
	end)
	if not ok then
		warn_("addPoints", err)
	end
	return ok
end

-- Sums every shard for every faction. Returns (totals, keysFound) or nil on failure.
-- keysFound = how many shard keys existed (0 means nothing was ever written, or it was lost).
function WarStore.readTotals(weekId: number): (Totals?, number)
	local totals = emptyTotals()
	local found = 0
	local ok, err = pcall(function()
		for _, factionId in FactionConfig.ORDER do
			for shard = 1, FactionConfig.SHARDS do
				local value = totalsMap:GetAsync(totalsKey(weekId, factionId, shard))
				if typeof(value) == "table" then
					found += 1
					totals[factionId].points += tonumber(value.p) or 0
					totals[factionId].active += tonumber(value.a) or 0
				end
			end
		end
	end)
	if not ok then
		warn_("readTotals", err)
		return nil, 0
	end
	return totals, found
end

-- Restores totals into shard 1 only if that key doesn't exist (used after data loss).
function WarStore.restoreTotals(weekId: number, totals: Totals)
	for factionId, total in totals do
		pcall(function()
			totalsMap:UpdateAsync(totalsKey(weekId, factionId, 1), function(old: any): any
				if old ~= nil then
					return nil -- something exists already; don't overwrite
				end
				return { p = total.points, a = total.active }
			end, FactionConfig.MEMORY_EXPIRATION)
		end)
	end
end

-- Tries to become (or stay) the leader server. Only the leader writes backups.
function WarStore.tryLeader(jobId: string): boolean
	local now = os.time()
	local ok, result = pcall(function(): any
		return metaMap:UpdateAsync("leader", function(old: any): any
			if typeof(old) == "table" and old.job ~= jobId and (tonumber(old.untilTime) or 0) > now then
				return nil -- someone else holds the lock
			end
			return { job = jobId, untilTime = now + FactionConfig.LEADER_LOCK_SECONDS }
		end, FactionConfig.LEADER_LOCK_SECONDS * 2)
	end)
	return ok and typeof(result) == "table" and result.job == jobId
end

function WarStore.saveBackup(weekId: number, totals: Totals)
	local ok, err = pcall(function()
		warStore:SetAsync(`backup_{weekId}`, totals)
	end)
	if not ok then
		warn_("saveBackup", err)
	end
end

function WarStore.loadBackup(weekId: number): Totals?
	local ok, result = pcall(function(): any
		return warStore:GetAsync(`backup_{weekId}`)
	end)
	if ok and typeof(result) == "table" then
		return result :: Totals
	end
	return nil
end

function WarStore.getResult(weekId: number): WarResult?
	local ok, result = pcall(function(): any
		return warStore:GetAsync(`result_{weekId}`)
	end)
	if ok and typeof(result) == "table" then
		return result :: WarResult
	end
	return nil
end

-- Writes the result only if none exists yet, then returns whatever is stored.
-- Every server that tries ends up with the same result.
function WarStore.finalizeResult(weekId: number, result: WarResult): WarResult?
	local ok, err = pcall(function()
		warStore:UpdateAsync(`result_{weekId}`, function(old: any): any
			if old ~= nil then
				return nil -- already decided: keep it
			end
			return result
		end)
	end)
	if not ok then
		warn_("finalizeResult", err)
	end
	return WarStore.getResult(weekId)
end

local function leaderboard(weekId: number, factionId: string): OrderedDataStore
	return DataStoreService:GetOrderedDataStore(StoreNames.of(`WarTop_{weekId}_{factionId}`))
end

function WarStore.setContribution(weekId: number, factionId: string, userId: number, points: number)
	local ok, err = pcall(function()
		leaderboard(weekId, factionId):SetAsync(tostring(userId), math.floor(points))
	end)
	if not ok then
		warn_("setContribution", err)
	end
end

-- Top contributors as { userId, points }, highest first. Nil on failure.
function WarStore.getTop(weekId: number, factionId: string, count: number): { { userId: number, points: number } }?
	local ok, result = pcall(function(): any
		local pages = leaderboard(weekId, factionId):GetSortedAsync(false, count)
		return pages:GetCurrentPage()
	end)
	if not ok or typeof(result) ~= "table" then
		return nil
	end
	local top: { { userId: number, points: number } } = {}
	for _, entry in result do
		local userId = tonumber(entry.key)
		if userId ~= nil then
			table.insert(top, { userId = userId, points = tonumber(entry.value) or 0 })
		end
	end
	return top
end

return WarStore
