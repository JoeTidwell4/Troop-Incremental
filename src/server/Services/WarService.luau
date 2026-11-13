--!strict
-- Faction war rules: who earns points, the daily cap, standings, picking the weekly
-- winner, and the winner's gold bonus. All storage goes through WarStore.
--
-- Flow on each server:
--   1. Kills (StageService.Killed) give war points to the player's save, with the frontier
--      rule and daily cap applied here. Points also go into a local buffer.
--   2. Every FLUSH_INTERVAL the buffer is added to the shared totals (atomic MemoryStore
--      update). If that fails, the points stay in the buffer and are retried.
--   3. Every POLL_INTERVAL the server reads the shared totals and sends them to its players.
--   4. One "leader" server at a time copies the totals to a DataStore as a backup.
--   5. After a week ends (plus FINALIZE_DELAY for late points), any server computes the
--      winner and writes it once; every server then reads that same stored result.
--   6. Players who were ACTIVE in the winning faction get the gold bonus all next week.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local FactionConfig = require(Shared:WaitForChild("Config"):WaitForChild("FactionConfig"))
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local ModifierService = require(Services.ModifierService)
local StageService = require(Services.StageService)
local SyncService = require(Services.SyncService)
local WarStore = require(Services.WarStore)
local ActivityService = require(Services.ActivityService)

type PlayerData = Types.PlayerData
type WarRecord = Types.WarRecord
type WarResult = Types.WarResult
type WarState = Types.WarState
type FactionStanding = Types.FactionStanding

-- In Studio JobId is empty; give each test server its own id.
local jobId = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)
local shard = (string.len(jobId) + string.byte(jobId, 1)) % FactionConfig.SHARDS + 1

-- Points earned on this server not yet sent to the shared totals, per week + faction.
local buffer: { [number]: { [string]: { points: number, active: number } } } = {}
-- Players whose leaderboard entry needs writing.
local contributionDirty: { [Player]: boolean } = {}

local standings: { [string]: FactionStanding } = {}
local top: { [string]: { { name: string, points: number } } } = {}
local results: { [number]: WarResult } = {} -- cached final results by week
local available = true
local nameCache: { [number]: string } = {}

local WarService = {}

local function now(): number
	return os.time()
end

local function currentWeek(): number
	return Formulas.warWeek(now())
end

local function newRecord(weekId: number, factionId: string): WarRecord
	return { weekId = weekId, faction = factionId, points = 0, dayId = -1, dayPoints = 0, active = false }
end

-- Moves the player onto this week's record (archiving last week's) if the week changed.
local function syncRecord(data: PlayerData)
	local week = currentWeek()
	if data.war.weekId ~= week then
		if data.war.weekId >= 0 and data.war.points > 0 then
			data.lastWar = data.war
		end
		data.war = newRecord(week, data.faction)
	end
end

local function addToBuffer(weekId: number, factionId: string, points: number, newActive: number)
	local week = buffer[weekId]
	if week == nil then
		week = {}
		buffer[weekId] = week
	end
	local entry = week[factionId]
	if entry == nil then
		entry = { points = 0, active = 0 }
		week[factionId] = entry
	end
	entry.points += points
	entry.active += newActive
end

local function onKilled(player: Player, stage: number, kills: number, wasBoss: boolean)
	local data = DataService.get(player)
	if data == nil or data.faction == "" then
		return
	end
	-- Only kills near your best stage this run count (no farming easy stages).
	if stage < data.highestStage - FactionConfig.FRONTIER_WINDOW then
		return
	end
	syncRecord(data)
	local record = data.war

	local day = Formulas.warDay(now())
	if record.dayId ~= day then
		record.dayId = day
		record.dayPoints = 0
	end
	local earned = if wasBoss then FactionConfig.POINTS_PER_BOSS else kills * FactionConfig.POINTS_PER_KILL
	earned = math.min(earned, FactionConfig.DAILY_CAP - record.dayPoints)
	if earned <= 0 then
		return
	end

	record.points += earned
	record.dayPoints += earned
	local newActive = 0
	if not record.active and record.points >= FactionConfig.ACTIVE_THRESHOLD then
		record.active = true
		newActive = 1
	end
	addToBuffer(record.weekId, record.faction, earned, newActive)
	contributionDirty[player] = true
	ActivityService.record(player, "WarPoints", earned)
end

-- Called by FactionService after a pick or switch. Points already earned stay with the
-- old faction; this week starts fresh for the new one. The daily cap carries over, so
-- switching can't be used to reset it.
function WarService.onFactionChanged(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	syncRecord(data)
	local dayId, dayPoints = data.war.dayId, data.war.dayPoints
	data.war = newRecord(currentWeek(), data.faction)
	data.war.dayId = dayId
	data.war.dayPoints = dayPoints
end

-- Seconds left in the current war week.
function WarService.secondsLeft(): number
	return math.max(0, Formulas.warWeekStart(currentWeek() + 1) - now())
end

-- True during the last part of a war, when switching faction is locked.
function WarService.isSwitchLocked(): boolean
	return WarService.secondsLeft() <= FactionConfig.SWITCH_LOCK_SECONDS
end

-- Did this player win last week (active in the winning faction)?
function WarService.hasWinnerBonus(data: PlayerData): boolean
	local lastWeek = currentWeek() - 1
	local result = results[lastWeek]
	if result == nil or result.winner == "" then
		return false
	end
	local record = if data.war.weekId == lastWeek then data.war else data.lastWar
	return record.weekId == lastWeek and record.active and record.faction == result.winner
end

local function computeStandings(totals: WarStore.Totals): { [string]: FactionStanding }
	local out: { [string]: FactionStanding } = {}
	for _, factionId in FactionConfig.ORDER do
		local total = totals[factionId] or { points = 0, active = 0 }
		out[factionId] = {
			points = total.points,
			active = total.active,
			average = if total.active > 0 then total.points / total.active else 0,
		}
	end
	return out
end

local function pickWinner(weekId: number, table_: { [string]: FactionStanding }): WarResult
	local winner = ""
	local best: FactionStanding? = nil
	for _, factionId in FactionConfig.ORDER do
		local standing = table_[factionId]
		if standing.points > 0 then
			local better = best == nil
				or standing.average > best.average
				or (standing.average == best.average and standing.points > best.points)
			if better then
				winner = factionId
				best = standing
			end
		end
	end
	return { weekId = weekId, winner = winner, standings = table_ }
end

local function buildState(): WarState
	local week = currentWeek()
	local display: { [string]: FactionStanding } = {}
	-- Include this server's not-yet-sent points so your own progress shows up quickly.
	local pending = buffer[week] or {}
	for _, factionId in FactionConfig.ORDER do
		local base = standings[factionId] or { points = 0, active = 0, average = 0 }
		local extra = pending[factionId] or { points = 0, active = 0 }
		local points = base.points + extra.points
		local active = base.active + extra.active
		display[factionId] = {
			points = points,
			active = active,
			average = if active > 0 then points / active else 0,
		}
	end
	return {
		weekId = week,
		secondsLeft = WarService.secondsLeft(),
		studioTestMode = FactionConfig.IS_STUDIO_TEST_MODE,
		available = available,
		standings = display,
		top = top,
		lastResult = results[week - 1],
	}
end

local function broadcast()
	local state = buildState()
	for _, player in Players:GetPlayers() do
		if SyncService.isReady(player) then
			RemoteService.fireClient(Remotes.Events.WarSync, player, state)
		end
	end
end

---------------------------------------------------------------- background jobs

local function flush()
	for weekId, factions in buffer do
		for factionId, entry in factions do
			if entry.points > 0 or entry.active > 0 then
				if WarStore.addPoints(weekId, factionId, shard, entry.points, entry.active) then
					factions[factionId] = nil
				end
			else
				factions[factionId] = nil
			end
		end
		if next(factions) == nil then
			buffer[weekId] = nil
		end
	end
end

local function poll()
	local week = currentWeek()
	local totals, found = WarStore.readTotals(week)
	available = totals ~= nil
	if totals ~= nil then
		standings = computeStandings(totals)
		-- Leader only: back up totals, and restore them if MemoryStore lost everything.
		if WarStore.tryLeader(jobId) then
			if found == 0 then
				local backup = WarStore.loadBackup(week)
				if backup ~= nil then
					WarStore.restoreTotals(week, backup)
				end
			end
		end
	end

	-- Decide last week's winner once late points have had time to arrive.
	local lastWeek = week - 1
	if results[lastWeek] == nil and now() >= Formulas.warWeekStart(week) + FactionConfig.FINALIZE_DELAY then
		local stored = WarStore.getResult(lastWeek)
		if stored == nil then
			local lastTotals = WarStore.readTotals(lastWeek) or WarStore.loadBackup(lastWeek)
			if lastTotals ~= nil then
				stored = WarStore.finalizeResult(lastWeek, pickWinner(lastWeek, computeStandings(lastTotals)))
			end
		end
		if stored ~= nil then
			results[lastWeek] = stored
			for _, player in Players:GetPlayers() do
				DataService.markChanged(player) -- winner bonus may have changed
			end
		end
	end

	broadcast()
end

local function backup()
	if not WarStore.tryLeader(jobId) then
		return
	end
	local week = currentWeek()
	local totals, found = WarStore.readTotals(week)
	if totals ~= nil and found > 0 then
		WarStore.saveBackup(week, totals)
	end
end

local function getName(userId: number): string
	local cached = nameCache[userId]
	if cached ~= nil then
		return cached
	end
	local ok, name = pcall(function(): string
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok then name else `Player {userId}`
	nameCache[userId] = result
	return result
end

local function readLeaderboards()
	local week = currentWeek()
	local newTop: { [string]: { { name: string, points: number } } } = {}
	for _, factionId in FactionConfig.ORDER do
		local entries = WarStore.getTop(week, factionId, FactionConfig.TOP_COUNT)
		local list: { { name: string, points: number } } = {}
		for _, entry in entries or {} do
			table.insert(list, { name = getName(entry.userId), points = entry.points })
		end
		newTop[factionId] = list
	end
	top = newTop
end

local function writeContribution(player: Player)
	local data = DataService.get(player)
	if data == nil or data.war.faction == "" or data.war.points <= 0 then
		return
	end
	WarStore.setContribution(data.war.weekId, data.war.faction, player.UserId, data.war.points)
end

local function every(seconds: number, job: () -> ())
	task.spawn(function()
		while true do
			task.wait(seconds)
			local ok, err = pcall(job)
			if not ok then
				warn(`[WarService] background job error: {err}`)
			end
		end
	end)
end

function WarService.start()
	StageService.Killed:Connect(onKilled)

	ModifierService.register(function(player: Player): ModifierService.PartialModifiers?
		local data = DataService.get(player)
		if data ~= nil and WarService.hasWinnerBonus(data) then
			return { gold = FactionConfig.WINNER_GOLD_MULTIPLIER }
		end
		return nil
	end)

	DataService.ProfileLoaded:Connect(function(_player: Player, data: PlayerData)
		syncRecord(data)
	end)

	SyncService.ClientReady:Connect(function(player: Player)
		RemoteService.fireClient(Remotes.Events.WarSync, player, buildState())
	end)

	DataService.ProfileReleasing:Connect(function(player: Player)
		contributionDirty[player] = nil
		task.spawn(writeContribution, player) -- data is still readable during this call
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		contributionDirty[player] = nil
	end)

	every(FactionConfig.FLUSH_INTERVAL, flush)
	every(FactionConfig.POLL_INTERVAL, poll)
	every(FactionConfig.BACKUP_INTERVAL, backup)
	every(FactionConfig.LEADERBOARD_READ_INTERVAL, readLeaderboards)
	every(FactionConfig.LEADERBOARD_WRITE_INTERVAL, function()
		for player in contributionDirty do
			contributionDirty[player] = nil
			writeContribution(player)
		end
	end)

	-- Send any buffered points before the server shuts down.
	game:BindToClose(function()
		pcall(flush)
	end)

	task.spawn(poll) -- first standings right away
end

return WarService
