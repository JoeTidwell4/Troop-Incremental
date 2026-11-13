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
local BigNum = require(Shared:WaitForChild("BigNum"))
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
local CommanderService = require(Services.CommanderService)
local ClanShopService = require(Services.ClanShopService)

type ClanRecord = Types.ClanRecord
type ClanWarEntry = Types.ClanWarEntry
type PlayerData = Types.PlayerData
type WarScore = ClanStore.WarScore

-- XP not yet saved: clanId -> weekId -> { total, members = userId -> XP, activities =
-- activity -> count (for clan quests) }.
type Batch = { total: number, members: { [string]: number }, activities: { [string]: number } }
type Quest = { key: string, target: number, progress: number }
type Matchup = { bye: boolean, opponentId: string?, opponentName: string?, opponentTag: string?, opponentXp: number?, at: number }
local pending: { [string]: { [number]: Batch } } = {}
local fractions: { [Player]: number } = {} -- leftover fractions of XP (kills, donations)
local dirty: { [Player]: boolean } = {} -- contribution changed; refresh their clan view
local claiming: { [Player]: boolean } = {}
local results: { [number]: { WarScore } } = {} -- finished weeks' locked-in top lists
local names: { [string]: { name: string, tag: string } } = {}
local board: { weekId: number, top: { ClanWarEntry } } = { weekId = -1, top = {} }
local matchups: { [string]: Matchup } = {} -- this week's head-to-head per clan (cached)

-- Activities that count toward some clan quest.
local QUEST_ACTIVITIES: { [string]: boolean } = {}
for _, def in ClanConfig.QUEST_POOL do
	QUEST_ACTIVITIES[def.activity] = true
end

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

local function batchFor(clanId: string, weekId: number): Batch
	local byWeek = pending[clanId]
	if byWeek == nil then
		byWeek = {}
		pending[clanId] = byWeek
	end
	local batch = byWeek[weekId]
	if batch == nil then
		batch = { total = 0, members = {}, activities = {} }
		byWeek[weekId] = batch
	end
	return batch
end

local function onActivity(player: Player, activity: string, amount: number)
	local perUnit = ClanConfig.XP_PER_ACTIVITY[activity]
	local forQuests = QUEST_ACTIVITIES[activity] == true
	if perUnit == nil and not forQuests then
		return
	end
	local data = DataService.get(player)
	local clan = ClanService.getClan(player)
	if data == nil or clan == nil then
		return
	end
	rollover(data)
	local record = data.clanWar
	if forQuests then
		-- Quest progress counts everything (no daily cap: rewards need your own XP anyway).
		local batch = batchFor(clan.id, record.weekId)
		batch.activities[activity] = (batch.activities[activity] or 0) + amount
		dirty[player] = true
	end
	if perUnit == nil then
		return
	end
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
	local batch = batchFor(clan.id, record.weekId)
	local userKey = tostring(player.UserId)
	batch.total += whole
	batch.members[userKey] = (batch.members[userKey] or 0) + whole
	dirty[player] = true
end

---------------------------------------------------------------- clan quests

-- A simple stable number from a string (same on every server).
local function hash(text: string): number
	local value = 7
	for i = 1, #text do
		value = (value * 31 + string.byte(text, i)) % 2147483647
	end
	return value
end

-- This week's quests for a clan: picked from QUEST_POOL by clan + week (every server
-- agrees), targets scaled to the member count.
local function rollQuests(clanId: string, weekId: number, memberCount: number): { Quest }
	local rng = Random.new(hash(clanId) + weekId * 7919)
	local pool = table.clone(ClanConfig.QUEST_POOL)
	local quests: { Quest } = {}
	local members = math.max(ClanConfig.QUEST_MIN_MEMBERS, memberCount)
	for _ = 1, math.min(ClanConfig.QUESTS_PER_WEEK, #pool) do
		local def = table.remove(pool, rng:NextInteger(1, #pool)) :: any
		table.insert(quests, { key = def.key, target = math.max(1, math.floor(def.perMember * members)), progress = 0 })
	end
	return quests
end

local function questActivity(key: string): string
	for _, def in ClanConfig.QUEST_POOL do
		if def.key == key then
			return def.activity
		end
	end
	return ""
end

-- The clan's quests for `weekId` as stored (or freshly rolled if this week hasn't been
-- saved yet), as copies.
local function questsOf(record: ClanRecord, weekId: number): { Quest }
	local list: { Quest } = {}
	if record.questWeek == weekId and record.quests ~= nil then
		for _, quest in record.quests do
			table.insert(list, { key = quest.key, target = quest.target, progress = quest.progress })
		end
		return list
	end
	return rollQuests(record.id, weekId, record.memberCount)
end

---------------------------------------------------------------- saving XP

local function addMembers(target: { [string]: number }, from: { [string]: number })
	for userKey, xp in from do
		target[userKey] = (target[userKey] or 0) + xp
	end
end

-- Adds batches (week -> XP) to a clan record, including each member's share (for the
-- MVP). Older records get the new fields here.
local function applyXp(r: ClanRecord, byWeek: { [number]: Batch })
	r.xp = r.xp or 0
	r.weekId = r.weekId or -1
	r.weekXp = r.weekXp or 0
	r.lastWeekId = r.lastWeekId or -1
	r.lastWeekXp = r.lastWeekXp or 0
	r.memberWeekXp = r.memberWeekXp or {}
	r.lastMemberWeekXp = r.lastMemberWeekXp or {}
	-- Week numbers from the future can only be Studio test-mode weeks written back when
	-- Studio shared the live clans: drop them, or this clan's weeks and quests never roll.
	local now = currentWeek()
	if (r.weekId :: number) > now then
		r.weekId, r.weekXp, r.memberWeekXp = -1, 0, {}
	end
	if (r.lastWeekId :: number) > now then
		r.lastWeekId, r.lastWeekXp, r.lastMemberWeekXp = -1, 0, {}
	end
	if (r.questWeek or -1) > now then
		r.questWeek, r.quests = nil, nil
	end
	local weeks: { number } = {}
	for week in byWeek do
		table.insert(weeks, week)
	end
	table.sort(weeks)
	for _, week in weeks do
		local batch = byWeek[week]
		local xp = batch.total
		-- Clan quests: the first save of a new week rolls that week's quests.
		if week > (r.questWeek or -1) then
			r.questWeek = week
			r.quests = rollQuests(r.id, week, r.memberCount)
		end
		if week == r.questWeek and r.quests ~= nil then
			for _, quest in r.quests do
				quest.progress += batch.activities[questActivity(quest.key)] or 0
			end
		end
		if week > (r.weekId :: number) then
			r.lastWeekId = r.weekId
			r.lastWeekXp = r.weekXp
			r.lastMemberWeekXp = r.memberWeekXp
			r.weekId = week
			r.weekXp = 0
			r.memberWeekXp = {}
		end
		if week == r.weekId then
			r.weekXp = (r.weekXp :: number) + xp
			addMembers(r.memberWeekXp :: { [string]: number }, batch.members)
		elseif week == r.lastWeekId then
			r.lastWeekXp = (r.lastWeekXp :: number) + xp
			addMembers(r.lastMemberWeekXp :: { [string]: number }, batch.members)
		end
		r.xp = (r.xp :: number) + xp
	end
end

local function requeue(clanId: string, byWeek: { [number]: Batch })
	local current = pending[clanId]
	if current == nil then
		pending[clanId] = byWeek
		return
	end
	for week, batch in byWeek do
		local into = current[week]
		if into == nil then
			current[week] = batch
		else
			into.total += batch.total
			addMembers(into.members, batch.members)
			addMembers(into.activities, batch.activities)
		end
	end
end

-- Each member's XP for one week, from a clan record.
local function memberXpOf(record: ClanRecord, weekId: number): { [string]: number }
	if record.weekId == weekId then
		return record.memberWeekXp or {}
	elseif record.lastWeekId == weekId then
		return record.lastMemberWeekXp or {}
	end
	return {}
end

-- The member who gave the most XP that week (nil if nobody did).
local function mvpOf(record: ClanRecord, weekId: number): string?
	local best: string? = nil
	local bestXp = 0
	for userKey, xp in memberXpOf(record, weekId) do
		if xp > bestXp then
			best, bestXp = userKey, xp
		end
	end
	return best
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
			-- Local update only: XP isn't worth a cross-server message or a browse-list
			-- write every 30s per clan. Other servers see it on their next poll (60s).
			ClanService.applyRecord(record)
			for week in byWeek do
				local xp = weekXpOf(record, week)
				if xp > 0 then -- quest-only progress doesn't put a clan on the board
					ClanStore.setWarScore(week, clanId, xp)
				end
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
		local top = ClanStore.getWarTop(weekId, ClanConfig.WAR_RESULT_COUNT)
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
	local matchup = if data ~= nil and data.clanId ~= "" then matchups[data.clanId] else nil
	RemoteService.fireClient(Remotes.Events.ClanWarSync, player, {
		weekId = week,
		secondsLeft = math.max(0, Formulas.clanWarWeekStart(week + 1) - os.time()),
		top = if board.weekId == week then board.top else {},
		myRank = myRank,
		matchup = if matchup ~= nil
			then { bye = matchup.bye, opponentName = matchup.opponentName, opponentTag = matchup.opponentTag, opponentXp = matchup.opponentXp }
			else nil,
	})
end

---------------------------------------------------------------- head-to-head

-- Who a clan faces in `weekId`: paired by last week's locked-in ranking (1 v 2, 3 v 4...).
-- Returns (opponentId or nil for a bye, decided); decided = false while last week's
-- results aren't in yet.
local function opponentOf(clanId: string, weekId: number): (string?, boolean)
	local previous = getResult(weekId - 1)
	if previous == nil then
		return nil, false
	end
	for index, score in previous do
		if score.clanId == clanId then
			local partner = if index % 2 == 1 then index + 1 else index - 1
			local other = previous[partner]
			return if other ~= nil then other.clanId else nil, true
		end
	end
	return nil, true -- didn't place last week: a bye
end

-- Refreshes the cached matchup for a clan with members online here (yields).
local function refreshMatchup(clanId: string)
	local week = currentWeek()
	local cached = matchups[clanId]
	if cached ~= nil and os.clock() - cached.at < ClanConfig.OPPONENT_REFRESH then
		return
	end
	local opponent, decided = opponentOf(clanId, week)
	if not decided then
		matchups[clanId] = nil
		return
	end
	if opponent == nil then
		matchups[clanId] = { bye = true, at = os.clock() }
		return
	end
	local info = nameOf(opponent)
	local xp = ClanStore.getWarScore(week, opponent)
	matchups[clanId] = {
		bye = false,
		opponentId = opponent,
		opponentName = info.name,
		opponentTag = info.tag,
		opponentXp = xp,
		at = os.clock(),
	}
end

-- Did this clan win its head-to-head in `weekId`? "win" | "bye" | "loss" | nil (unknown yet).
local function headToHeadResult(clanId: string, myXp: number, weekId: number): string?
	local opponent, decided = opponentOf(clanId, weekId)
	if not decided then
		return nil
	end
	if opponent == nil then
		return if myXp >= ClanConfig.WAR_PARTICIPATION_XP then "bye" else "loss"
	end
	local theirXp, ok = ClanStore.getWarScore(weekId, opponent)
	if not ok then
		return nil
	end
	return if myXp >= theirXp and myXp > 0 then "win" else "loss"
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
	local reward: { honor: number?, honorShare: number?, heroChests: number?, packs: number? }? = nil
	local rank: number? = nil
	local decided = result ~= nil
	local mvp = false
	local tokens = 0
	local headToHead: string? = nil
	if result ~= nil and record.lastXp >= ClanConfig.WAR_MIN_CONTRIBUTION then
		for index, score in result do
			if score.clanId == record.lastClanId then
				rank = index
			end
		end
		reward = Formulas.clanWarReward(rank)
		local clan, ok = ClanStore.get(record.lastClanId)
		if not ok then
			decided = false -- couldn't check; try again on the next poll
		elseif clan ~= nil then
			local clanXp = weekXpOf(clan, weekId)
			if reward == nil and clanXp >= ClanConfig.WAR_PARTICIPATION_XP then
				-- Not on the board: the small reward if the clan still had a solid week.
				reward = ClanConfig.WAR_PARTICIPATION_REWARD
				tokens += ClanConfig.TOKENS_PARTICIPATION
			end
			mvp = mvpOf(clan, weekId) == tostring(player.UserId)
			headToHead = headToHeadResult(clan.id, clanXp, weekId)
			if headToHead == nil then
				decided = false -- opponent's score not readable yet; try again later
			end
		end
		if rank ~= nil then
			for _, tier in ClanConfig.TOKENS_FOR_RANK do
				if rank <= tier.maxRank then
					tokens += tier.tokens
					break
				end
			end
		end
	end
	if mvp then
		tokens += ClanConfig.TOKENS_MVP
	end
	if headToHead == "win" or headToHead == "bye" then
		tokens += ClanConfig.TOKENS_HEAD_TO_HEAD_WIN
		local base = reward or {}
		reward = {
			honor = (base.honor or 0) + ClanConfig.HEAD_TO_HEAD_WIN_HONOR,
			honorShare = (base.honorShare or 0) + ClanConfig.HEAD_TO_HEAD_HONOR_SHARE,
			heroChests = base.heroChests,
			packs = base.packs,
		}
	end
	if mvp then
		-- Last week's top contributor in the clan: extra Honor on top.
		local base = reward or {}
		reward = {
			honor = (base.honor or 0) + ClanConfig.MVP_HONOR,
			honorShare = (base.honorShare or 0) + ClanConfig.MVP_HONOR_SHARE,
			heroChests = base.heroChests,
			packs = base.packs,
		}
	end
	claiming[player] = nil

	local fresh = DataService.get(player)
	if not decided or fresh == nil or fresh.clanWar ~= record or record.claimedWeek >= weekId then
		return
	end
	record.claimedWeek = weekId
	DataService.markChanged(player)
	if rank ~= nil and record.lastXp >= ClanConfig.WAR_MIN_CONTRIBUTION then
		CommanderService.grantForClanWar(player, rank) -- War Banner / Seraph Wings
	end
	if tokens > 0 then
		ClanShopService.addTokens(player, tokens)
	end
	if reward ~= nil or tokens > 0 then
		local given = reward or {}
		local honor = DailyService.grant(player, fresh, {
			honor = given.honor,
			honorShare = given.honorShare,
			heroChests = given.heroChests,
			packs = given.packs,
		}, "ClanWar")
		RemoteService.fireClient(Remotes.Events.Notice, player, {
			kind = "ClanWarRewards",
			stage = 0,
			rank = rank,
			mvp = mvp,
			tokens = tokens,
			headToHead = headToHead,
			honor = if BigNum.isZero(honor) then nil else BigNum.toNumber(honor),
			heroChests = given.heroChests,
			packs = given.packs,
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
	local clansHere: { [string]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data ~= nil and data.clanId ~= "" then
			clansHere[data.clanId] = true
		end
	end
	for clanId in clansHere do
		refreshMatchup(clanId)
	end
	for _, player in Players:GetPlayers() do
		pushWar(player)
		task.spawn(claimIfDue, player)
	end
end

-- "ClaimClanQuest" action: collect a finished clan quest's reward (once per week each).
local function claimQuest(player: Player, data: PlayerData, index: number): Types.ClanResult
	local clan = ClanService.getClan(player)
	if clan == nil then
		return { ok = false, reason = "NotInClan" }
	end
	rollover(data)
	local week = currentWeek()
	local record = data.clanWar
	if record.clanId ~= clan.id or record.xp < ClanConfig.QUEST_MIN_XP then
		return { ok = false, reason = "NeedContribution" }
	end
	local claims = data.clanQuestClaims
	if claims.weekId ~= week then
		claims.weekId = week
		claims.claimed = {}
	end
	local slot = tostring(index)
	if claims.claimed[slot] then
		return { ok = false, reason = "AlreadyClaimed" }
	end
	local quest = questsOf(clan, week)[index]
	if quest == nil then
		return { ok = false, reason = "Rejected" }
	end
	local byWeek = pending[clan.id]
	local batch = if byWeek ~= nil then byWeek[week] else nil
	local progress = quest.progress + (if batch ~= nil then batch.activities[questActivity(quest.key)] or 0 else 0)
	if progress < quest.target then
		return { ok = false, reason = "QuestNotDone" }
	end
	claims.claimed[slot] = true
	ClanShopService.addTokens(player, ClanConfig.QUEST_REWARD.tokens)
	DailyService.grant(player, data, { goldMinutes = ClanConfig.QUEST_REWARD.goldMinutes }, "ClanQuest")
	dirty[player] = true
	return { ok = true }
end

---------------------------------------------------------------- Studio test panel (DebugService only)

-- Adds clan XP for this player's clan, skipping the daily cap. Returns false if not in a clan.
function ClanWarService.debugAddXp(player: Player, xp: number): boolean
	local data = DataService.get(player)
	local clan = ClanService.getClan(player)
	if data == nil or clan == nil then
		return false
	end
	rollover(data)
	local record = data.clanWar
	if record.clanId ~= clan.id then
		record.clanId = clan.id
		record.xp = 0
	end
	record.xp += xp
	local batch = batchFor(clan.id, record.weekId)
	local userKey = tostring(player.UserId)
	batch.total += xp
	batch.members[userKey] = (batch.members[userKey] or 0) + xp
	dirty[player] = true
	return true
end

-- Fills this week's clan quests (saved on the next flush, a few seconds).
function ClanWarService.debugFinishQuests(player: Player): boolean
	local data = DataService.get(player)
	local clan = ClanService.getClan(player)
	if data == nil or clan == nil then
		return false
	end
	rollover(data)
	local batch = batchFor(clan.id, data.clanWar.weekId)
	for _, quest in questsOf(clan, currentWeek()) do
		local activity = questActivity(quest.key)
		batch.activities[activity] = (batch.activities[activity] or 0) + quest.target
	end
	dirty[player] = true
	return true
end

function ClanWarService.start()
	ClanService.registerAction("ClaimClanQuest", function(arg: unknown): (boolean, any)
		local valid = typeof(arg) == "number" and arg == arg and (arg :: number) % 1 == 0
			and (arg :: number) >= 1 and (arg :: number) <= ClanConfig.QUESTS_PER_WEEK
		return valid, arg
	end, claimQuest)
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
		-- Copy before adding buffered XP: `clan` is a shallow copy of the cached record.
		local members = table.clone(memberXpOf(clan, week))
		if byWeek ~= nil then
			for weekId, batch in byWeek do
				buffered += batch.total
				if weekId == week then
					bufferedThisWeek += batch.total
					addMembers(members, batch.members)
				end
			end
		end
		-- Last week's per-member XP stays as stored (the MVP star uses it).
		if clan.weekId ~= week then
			clan.lastMemberWeekXp = memberXpOf(clan, week - 1)
			clan.lastWeekId = week - 1
			clan.lastWeekXp = weekXpOf(clan, week - 1)
		end
		-- This week's clan quests, with this server's unsaved progress added.
		local quests = questsOf(clan, week)
		local thisWeek = if byWeek ~= nil then byWeek[week] else nil
		if thisWeek ~= nil then
			for _, quest in quests do
				quest.progress += thisWeek.activities[questActivity(quest.key)] or 0
			end
		end
		clan.quests = quests
		clan.questWeek = week
		local claims = data.clanQuestClaims
		view.questClaims = if claims.weekId == week then table.clone(claims.claimed) else {}
		clan.xp = (clan.xp or 0) + buffered
		clan.weekXp = weekXpOf(clan, week) + bufferedThisWeek
		clan.memberWeekXp = members
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
