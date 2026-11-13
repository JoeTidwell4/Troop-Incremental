--!strict
-- Weekly clan raid boss.
--
-- Attacks: a member uses the "RaidAttack" clan action; StageService runs a 30-second
-- raid fight on their battlefield. When it ends, the damage is turned into raid units
-- (Formulas.raidUnits) and added to the clan's raid record with an atomic UpdateAsync, so
-- members attacking at the same moment on different servers never overwrite each other.
-- Attacks are counted when they START, so leaving mid-attack can't be used to retry.
--
-- Rewards: each player's save remembers the raid week and clan they attacked for. Once
-- that week is over, the next time they play we read that clan's final total and grant
-- Honor + free packs for the tiers reached, then mark the week claimed. The claim lives in
-- the session-locked save, so it can't be granted twice.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local RaidConfig = require(Shared:WaitForChild("Config"):WaitForChild("RaidConfig"))
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)
local StageService = require(Services.StageService)
local ClanService = require(Services.ClanService)
local ClanBankService = require(Services.ClanBankService)
local ClanStore = require(Services.ClanStore)
local ActivityService = require(Services.ActivityService)

type PlayerData = Types.PlayerData
type RaidRecord = Types.RaidRecord
type RaidProgress = Types.RaidProgress
type ClanResult = Types.ClanResult

-- Latest raid progress per clan (this week), for clans with members online here.
local progress: { [string]: RaidProgress } = {}
-- Raid results that failed to save; retried on the next poll.
local unsaved: { { clanId: string, weekId: number, userKey: string, name: string, units: number } } = {}
local claiming: { [Player]: boolean } = {}

local RaidService = {}

local function currentWeek(): number
	return Formulas.raidWeek(os.time())
end

local function notify(player: Player, notice: Types.Notice)
	RemoteService.fireClient(Remotes.Events.Notice, player, notice)
end

local function newRecord(weekId: number): RaidRecord
	return { weekId = weekId, clanId = "", attacks = 0, units = 0, dayId = -1, attacksToday = 0, claimedWeek = -1 }
end

-- Rewards for a finished week, if not claimed yet. Yields (reads the clan's raid record).
-- Only after the claim is settled does the player's record move to the current week.
local function claimIfDue(player: Player, data: PlayerData)
	local record = data.raid
	local week = currentWeek()
	if record.weekId == week then
		return
	end
	if claiming[player] then
		return
	end
	local needsClaim = record.weekId >= 0 and record.attacks > 0 and record.claimedWeek < record.weekId
	if needsClaim then
		claiming[player] = true
		local finished, ok = ClanStore.getRaid(record.clanId, record.weekId)
		claiming[player] = nil
		local fresh = DataService.get(player)
		if fresh == nil or fresh.raid ~= record then
			return -- left, or something else already handled it
		end
		if not ok then
			return -- couldn't reach the store; try again on the next poll
		end
		if finished == nil then
			finished = { units = 0, contributors = {} } -- nothing was recorded that week
		end
		local tier = Formulas.raidTier(tonumber(finished.units) or 0)
		local honor, packs = Formulas.raidRewards(tier)
		fresh.honor = BigNum.add(fresh.honor, BigNum.fromNumber(honor))
		fresh.stats.honorEarned = BigNum.add(fresh.stats.honorEarned, BigNum.fromNumber(honor))
		fresh.packs.free += packs
		local claimedWeek = record.weekId
		fresh.raid = newRecord(week)
		fresh.raid.claimedWeek = claimedWeek
		DataService.markChanged(player)
		if tier > 0 then
			notify(player, { kind = "RaidRewards", stage = 0, tier = tier, honor = honor, packs = packs })
		end
		return
	end
	local claimedWeek = record.claimedWeek
	data.raid = newRecord(week)
	data.raid.claimedWeek = claimedWeek
end

local function resetDay(record: RaidRecord)
	local day = Formulas.raidDay(os.time())
	if record.dayId ~= day then
		record.dayId = day
		record.attacksToday = 0
	end
end

local function buildView(clanId: string): Types.RaidView
	local raid = progress[clanId] or { units = 0, contributors = {} }
	local top: { { name: string, units: number, attacks: number } } = {}
	for _, entry in raid.contributors do
		table.insert(top, { name = entry.name, units = entry.units, attacks = entry.attacks })
	end
	table.sort(top, function(a, b)
		return a.units > b.units
	end)
	while #top > RaidConfig.TOP_COUNT do
		table.remove(top)
	end
	local week = currentWeek()
	return {
		weekId = week,
		secondsLeft = math.max(0, Formulas.raidWeekStart(week + 1) - os.time()),
		units = raid.units,
		tier = Formulas.raidTier(raid.units),
		top = top,
		studioTestMode = RaidConfig.IS_STUDIO_TEST_MODE,
	}
end

local function pushView(player: Player)
	local record = ClanService.getClan(player)
	if record ~= nil and SyncService.isReady(player) then
		RemoteService.fireClient(Remotes.Events.RaidSync, player, buildView(record.id))
	end
end

local function pushClan(clanId: string)
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data ~= nil and data.clanId == clanId then
			pushView(player)
		end
	end
end

local function refreshProgress(clanId: string)
	local raid, ok = ClanStore.getRaid(clanId, currentWeek())
	if not ok then
		return -- keep what we had
	end
	progress[clanId] = if raid ~= nil then raid :: RaidProgress else { units = 0, contributors = {} }
	pushClan(clanId)
end

-- Adds one finished attack to the clan's shared raid record.
local function saveResult(clanId: string, weekId: number, userKey: string, name: string, units: number): boolean
	local saved = ClanStore.updateRaid(clanId, weekId, function(raid: any): any
		raid.units = (tonumber(raid.units) or 0) + units
		raid.contributors = raid.contributors or {}
		local entry = raid.contributors[userKey] or { name = name, units = 0, attacks = 0 }
		entry.name = name
		entry.units += units
		entry.attacks += 1
		raid.contributors[userKey] = entry
		return raid
	end)
	if saved == nil then
		return false
	end
	if weekId == currentWeek() then
		progress[clanId] = saved :: RaidProgress
		pushClan(clanId)
	end
	return true
end

local function attack(player: Player, data: PlayerData, _arg: any): ClanResult
	local clan = ClanService.getClan(player)
	if clan == nil then
		return { ok = false, reason = "NotInClan" }
	end
	claimIfDue(player, data)
	local fresh = DataService.get(player)
	if fresh == nil or fresh.raid.weekId ~= currentWeek() then
		return { ok = false, reason = "StoreError" } -- last week's rewards still being settled
	end
	local record = fresh.raid
	resetDay(record)
	if record.attacksToday >= RaidConfig.ATTACKS_PER_DAY then
		return { ok = false, reason = "NoAttacksLeft" }
	end
	local encounter = StageService.getEncounter(player)
	if encounter == nil then
		return { ok = false, reason = "NotLoaded" }
	end
	if encounter.kind == "Boss" then
		return { ok = false, reason = "InBoss" }
	elseif encounter.kind == "Raid" then
		return { ok = false, reason = "AlreadyRaiding" }
	end

	-- The HP bar empties exactly when the per-attack unit cap is reached.
	local multiplier = ClanBankService.getRaidMultiplier(player)
	local maxDamage = BigNum.mulNumber(Formulas.enemyHp(fresh.highestStage), RaidConfig.UNITS_CAP_PER_ATTACK / multiplier)
	if not StageService.startRaid(player, RaidConfig.ATTACK_SECONDS, maxDamage) then
		return { ok = false, reason = "Busy" }
	end
	record.attacksToday += 1
	record.attacks += 1
	record.clanId = clan.id
	ActivityService.record(player, "RaidAttack", 1)
	DataService.markChanged(player)
	return { ok = true }
end

local function onRaidFinished(player: Player, damage: BigNum.BigNum)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local record = data.raid
	local units = Formulas.raidUnits(damage, data.highestStage, ClanBankService.getRaidMultiplier(player))
	record.units += units
	DataService.markChanged(player)
	notify(player, { kind = "RaidResult", stage = 0, units = units })

	if record.clanId == "" or units <= 0 then
		return
	end
	local userKey = tostring(player.UserId)
	-- Everything needed is captured above: the save may be released while this yields.
	if not saveResult(record.clanId, record.weekId, userKey, player.Name, units) then
		table.insert(unsaved, {
			clanId = record.clanId,
			weekId = record.weekId,
			userKey = userKey,
			name = player.Name,
			units = units,
		})
	end
end

local function poll()
	-- Retry results that failed to save.
	local retry = unsaved
	unsaved = {}
	for _, entry in retry do
		if not saveResult(entry.clanId, entry.weekId, entry.userKey, entry.name, entry.units) then
			table.insert(unsaved, entry)
		end
	end

	local clanIds: { [string]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data ~= nil then
			claimIfDue(player, data)
			if data.clanId ~= "" then
				clanIds[data.clanId] = true
			end
		end
	end
	for clanId in progress do
		if not clanIds[clanId] then
			progress[clanId] = nil
		end
	end
	for clanId in clanIds do
		refreshProgress(clanId)
	end
end

function RaidService.start()
	ClanService.registerAction("RaidAttack", function(_arg: unknown): (boolean, any)
		return true, nil
	end, attack)

	StageService.RaidFinished:Connect(onRaidFinished)

	SyncService.addSnapshotFields(function(player: Player, data: PlayerData): { [string]: any }
		local record = data.raid
		local current = record.weekId == currentWeek()
		local today = current and record.dayId == Formulas.raidDay(os.time())
		local live = 0
		local encounter = StageService.getEncounter(player)
		if encounter ~= nil and encounter.kind == "Raid" then
			live = Formulas.raidUnits(encounter.raidDamage, data.highestStage, ClanBankService.getRaidMultiplier(player))
		end
		return {
			raidAttacksLeft = if current
				then RaidConfig.ATTACKS_PER_DAY - (if today then record.attacksToday else 0)
				else RaidConfig.ATTACKS_PER_DAY,
			raidUnitsWeek = if current then record.units else 0,
			raidUnitsLive = live,
		}
	end)

	DataService.ProfileLoaded:Connect(function(player: Player, data: PlayerData)
		claimIfDue(player, data)
		if data.clanId ~= "" and progress[data.clanId] == nil then
			refreshProgress(data.clanId)
		end
	end)
	SyncService.ClientReady:Connect(pushView)
	ClanService.ClanChanged:Connect(function(clanId: string)
		if progress[clanId] == nil then
			task.spawn(refreshProgress, clanId) -- e.g. someone just joined
		else
			pushClan(clanId)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		claiming[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(RaidConfig.POLL_INTERVAL)
			local ok, err = pcall(poll)
			if not ok then
				warn(`[RaidService] poll error: {err}`)
			end
		end
	end)
end

return RaidService
