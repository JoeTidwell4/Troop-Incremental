--!strict
-- Clan XP, clan levels and the weekly Clan War league (Phase 10c).
--
-- XP: members earn XP for their clan by playing (ClanConfig.XP_PER_ACTIVITY, from
-- ActivityService). Each member adds at most XP_DAILY_CAP per day; the day and week
-- counters live in the member's session-locked save (data.clanWar). XP is buffered per
-- clan and per week on this server and added to the clan record every FLUSH_INTERVAL in
-- one UpdateAsync (so two servers adding at once can't overwrite each other). A failed
-- write puts the batch back and retries. Each batch remembers the week it was earned in,
-- so XP from the last seconds of a week still counts for that week.
--
-- Level: from the clan's lifetime XP (Formulas.clanLevel); every member gets
-- Formulas.clanLevelBonus (gold + damage) through ModifierService.
--
-- League: after each flush the clan's week XP goes to an OrderedDataStore per week (the
-- score only goes up). Every WAR_BOARD_REFRESH this server reads the top clans and sends
-- the standings to its players (ClanWarSync). WAR_FINALIZE_DELAY after a week ends, the
-- first server to look writes the final top list once (ClanStore.warResult); every server
-- reads that same copy, so they all agree. Rewards are claimed on the member's next
-- login / poll; data.clanWar.claimedWeek stops double claims. You must have added at least
-- WAR_MIN_CONTRIBUTION XP to that clan that week to get anything.
--
-- Known limits: standings lag up to a couple of minutes; a store error that reports
-- failure after actually saving could count one batch twice (same as the faction war).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ClanConfig = require(Shared:WaitForChild("Config"):WaitForChild("ClanConfig"))
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)
local ModifierService = require(Services.ModifierService)
local ActivityService = require(Services.ActivityService)
local ClanService = require(Services.ClanService)
local ClanStore = require(Services.ClanStore)
local DailyService = require(Services.DailyService)

type ClanRecord = Types.ClanRecord
type ClanWarEntry = Types.ClanWarEntry
type PlayerData = Types.PlayerData
type WarScore = ClanStore.WarScore

local pending: { [string]: { [number]: number } } = {} -- clanId -> weekId -> XP not yet saved
local fractions: { [Player]: number } = {} -- leftover fractions of XP (kills, donations)
local dirty: { [Player]: boolean } = {} -- contribution changed; refresh their clan view
local claiming: { [Player]: boolean } = {}
local results: { [number]: { WarScore } } = {} -- finished weeks' locked-in top lists
local names: { [string]: { name: string, tag: string } } = {}
local board: { weekId: number, top: { ClanWarEntry } } = { weekId = -1, top = {} }

local ClanWarService = {}

local function currentWeek(): number
	return Formulas.clanWarWeek(os.time())
end

-- Starts a new day / week in the player's record when needed. Last week's numbers are
-- kept (for rewards) only if they actually earned XP that week.
local function rollover(data: PlayerData)
	local record = data.clanWar
	local week = currentWeek()
	if record.weekId ~= week then
		if record.weekId >= 0 and record.xp > 0 then
			record.lastWeekId = record.weekId
			record.lastClanId = record.clanId
			record.lastXp = record.xp
		end
		record.weekId = week
		record.clanId = ""
		record.xp = 0
	end
	local today = Formulas.clanDay(os.time())
	if record.dayId ~= today then
		record.dayId = today
		record.dayXp = 0
	end
end

---------------------------------------------------------------- earning XP

local function onActivity(player: Player, activity: string, amount: number)
	local perUnit = ClanConfig.XP_PER_ACTIVITY[activity]
	if perUnit == nil then
		return
	end
	local data = DataService.get(player)
	local clan = ClanService.getClan(player)
	if data == nil or clan == nil then
		return
	end
	rollover(data)
	local record = data.clanWar
	local total = (fractions[player] or 0) + amount * perUnit
	local whole = math.floor(total)
	fractions[player] = total - whole
	whole = math.min(whole, ClanConfig.XP_DAILY_CAP - record.dayXp)
	if whole <= 0 then
		return
	end
	if record.clanId ~= clan.id then
		-- Changed clans this week: your contribution starts over for the new clan.
		record.clanId = clan.id
		record.xp = 0
	end
	record.dayXp += whole
	record.xp += whole
	local byWeek = pending[clan.id]
	if byWeek == nil then
		byWeek = {}
		pending[clan.id] = byWeek
	end
	byWeek[record.weekId] = (byWeek[record.weekId] or 0) + whole
	dirty[player] = true
end

---------------------------------------------------------------- saving XP

-- Adds a batch (week -> XP) to a clan record. Older records get the new fields here.
local function applyXp(r: ClanRecord, byWeek: { [number]: number })
	r.xp = r.xp or 0
	r.weekId = r.weekId or -1
	r.weekXp = r.weekXp or 0
	r.lastWeekId = r.lastWeekId or -1
	r.lastWeekXp = r.lastWeekXp or 0
	local weeks: { number } = {}
	for week in byWeek do
		table.insert(weeks, week)
	end
	table.sort(weeks)
	for _, week in weeks do
		local xp = byWeek[week]
		if week > (r.weekId :: number) then
			r.lastWeekId = r.weekId
			r.lastWeekXp = r.weekXp
			r.weekId = week
			r.weekXp = 0
		end
		if week == r.weekId then
			r.weekXp = (r.weekXp :: number) + xp
		elseif week == r.lastWeekId then
			r.lastWeekXp = (r.lastWeekXp :: number) + xp
		end
		r.xp = (r.xp :: number) + xp
	end
end

local function requeue(clanId: string, byWeek: { [number]: number })
	local current = pending[clanId]
	if current == nil then
		pending[clanId] = byWeek
		return
	end
	for week, xp in byWeek do
		current[week] = (current[week] or 0) + xp
	end
end

-- A clan's XP for one week, from its record.
local function weekXpOf(record: ClanRecord, weekId: number): number
	if record.weekId == weekId then
		return record.weekXp or 0
	elseif record.lastWeekId == weekId then
		return record.lastWeekXp or 0
	end
	return 0
end

local function flush()
	local batches = pending
	pending = {}
	for clanId, byWeek in batches do
		local record, reason = ClanStore.update(clanId, function(r: ClanRecord): (ClanRecord?, string?)
			applyXp(r, byWeek)
			return r, nil
		end)
		if record ~= nil then
			ClanService.afterChange(record)
			for week in byWeek do
				ClanStore.setWarScore(week, clanId, weekXpOf(record, week))
			end
		elseif reason ~= "ClanNotFound" then
			requeue(clanId, byWeek)
		end
	end
end

---------------------------------------------------------------- standings

local function nameOf(clanId: string): { name: string, tag: string }
	local cached = names[clanId]
	if cached ~= nil then
		return cached
	end
	local record, ok = ClanStore.get(clanId)
	local entry = if record ~= nil
		then { name = record.name, tag = record.tag }
		else { name = "(disbanded)", tag = "-" }
	if ok then
		names[clanId] = entry -- names never change, so cache for good
	end
	return entry
end

local function toEntries(scores: { WarScore }): { ClanWarEntry }
	local list: { ClanWarEntry } = {}
	for rank, score in scores do
		local info = nameOf(score.clanId)
		table.insert(list, { rank = rank, clanId = score.clanId, name = info.name, tag = info.tag, xp = score.xp })
	end
	return list
end

-- Locked-in results for a finished week (nil until they can be decided, or on error).
local function getResult(weekId: number): { WarScore }?
	local cached = results[weekId]
	if cached ~= nil then
		return cached
	end
	if os.time() < Formulas.clanWarWeekStart(weekId + 1) + ClanConfig.WAR_FINALIZE_DELAY then
		return nil -- still waiting for late XP
	end
	local stored, ok = ClanStore.warResult(weekId, nil)
	if not ok then
		return nil
	end
	if stored == nil then
		local top = ClanStore.getWarTop(weekId, ClanConfig.WAR_TOP_COUNT)
		if top == nil then
			return nil
		end
		stored, ok = ClanStore.warResult(weekId, top)
		if not ok or stored == nil then
			return nil
		end
	end
	results[weekId] = stored :: { WarScore }
	return stored
end

local function pushWar(player: Player)
	if not SyncService.isReady(player) then
		return
	end
	local data = DataService.get(player)
	local myRank: number? = nil
	if data ~= nil and data.clanId ~= "" then
		for _, entry in board.top do
			if entry.clanId == data.clanId then
				myRank = entry.rank
			end
		end
	end
	local week = currentWeek()
	RemoteService.fireClient(Remotes.Events.ClanWarSync, player, {
		weekId = week,
		secondsLeft = math.max(0, Formulas.clanWarWeekStart(week + 1) - os.time()),
		top = if board.weekId == week then board.top else {},
		myRank = myRank,
	})
end

---------------------------------------------------------------- rewards

local function claimIfDue(player: Player)
	if claiming[player] then
		return
	end
	local data = DataService.get(player)
	if data == nil then
		return
	end
	rollover(data)
	local record = data.clanWar
	local weekId = record.lastWeekId
	if weekId < 0 or weekId >= currentWeek() or record.claimedWeek >= weekId then
		return
	end
	claiming[player] = true
	local result = getResult(weekId) -- may yield
	local reward: { honor: number?, heroChests: number?, packs: number? }? = nil
	local rank: number? = nil
	local decided = result ~= nil
	if result ~= nil and record.lastXp >= ClanConfig.WAR_MIN_CONTRIBUTION then
		for index, score in result do
			if score.clanId == record.lastClanId then
				rank = index
			end
		end
		reward = Formulas.clanWarReward(rank)
		if reward == nil then
			-- Not on the board: the small reward if the clan still had a solid week.
			local clan, ok = ClanStore.get(record.lastClanId)
			if not ok then
				decided = false -- couldn't check; try again on the next poll
			elseif clan ~= nil and weekXpOf(clan, weekId) >= ClanConfig.WAR_PARTICIPATION_XP then
				reward = ClanConfig.WAR_PARTICIPATION_REWARD
			end
		end
	end
	claiming[player] = nil

	local fresh = DataService.get(player)
	if not decided or fresh == nil or fresh.clanWar ~= record or record.claimedWeek >= weekId then
		return
	end
	record.claimedWeek = weekId
	DataService.markChanged(player)
	if reward ~= nil then
		DailyService.grant(player, fresh, {
			honor = reward.honor,
			heroChests = reward.heroChests,
			packs = reward.packs,
		}, "ClanWar")
		RemoteService.fireClient(Remotes.Events.Notice, player, {
			kind = "ClanWarRewards",
			stage = 0,
			rank = rank,
			honor = reward.honor,
			heroChests = reward.heroChests,
			packs = reward.packs,
		})
	end
end

---------------------------------------------------------------- start

local function refreshBoard()
	local week = currentWeek()
	local top = ClanStore.getWarTop(week, ClanConfig.WAR_TOP_COUNT)
	if top ~= nil then
		board = { weekId = week, top = toEntries(top) }
	end
	for _, player in Players:GetPlayers() do
		pushWar(player)
		task.spawn(claimIfDue, player)
	end
end

function ClanWarService.start()
	ActivityService.Recorded:Connect(onActivity)

	-- What members see: include XP still buffered here, and their own contribution.
	ClanService.decorateView = function(player: Player, view: Types.ClanView)
		local clan = view.clan
		local data = DataService.get(player)
		if clan == nil or data == nil then
			return
		end
		local week = currentWeek()
		local byWeek = pending[clan.id]
		local buffered, bufferedThisWeek = 0, 0
		if byWeek ~= nil then
			for weekId, xp in byWeek do
				buffered += xp
				if weekId == week then
					bufferedThisWeek += xp
				end
			end
		end
		clan.xp = (clan.xp or 0) + buffered
		clan.weekXp = weekXpOf(clan, week) + bufferedThisWeek
		clan.weekId = week
		local record = data.clanWar
		view.myWeekXp = if record.weekId == week and record.clanId == clan.id then record.xp else 0
		view.myDayXp = if record.dayId == Formulas.clanDay(os.time()) then record.dayXp else 0
	end

	ModifierService.register(function(player: Player): ModifierService.PartialModifiers?
		local clan = ClanService.getClan(player)
		if clan == nil then
			return nil
		end
		local level = Formulas.clanLevel(clan.xp or 0)
		local gold, damage = Formulas.clanLevelBonus(level)
		return { gold = gold, damage = damage }
	end)

	SyncService.ClientReady:Connect(function(player: Player)
		pushWar(player)
		task.spawn(claimIfDue, player)
	end)

	-- Contribution changed: refresh that member's clan view now and then.
	task.spawn(function()
		while true do
			task.wait(5)
			for player in dirty do
				dirty[player] = nil
				ClanService.pushView(player)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(ClanConfig.FLUSH_INTERVAL)
			local ok, err = pcall(flush)
			if not ok then
				warn(`[ClanWarService] flush error: {err}`)
			end
		end
	end)
	task.spawn(function()
		while true do
			local ok, err = pcall(refreshBoard)
			if not ok then
				warn(`[ClanWarService] board error: {err}`)
			end
			task.wait(ClanConfig.WAR_BOARD_REFRESH)
		end
	end)
	game:BindToClose(function()
		pcall(flush)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		fractions[player] = nil
		dirty[player] = nil
		claiming[player] = nil
	end)
end

return ClanWarService
