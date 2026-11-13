--!strict
-- Daily login calendar and daily quests (plus granting rewards for both).
--
-- Everything is checked and granted here on the server; the client only asks to claim.
-- Days are UTC days (DailyConfig.DAY_SECONDS; shorter in Studio for testing).
--
-- Login: claim once per day. Claiming the day after your last claim moves to the next
-- reward; any gap starts over at reward 1. After reward 7 it loops to 1.
-- Quests: a fresh set of QUESTS_PER_DAY each day, chosen from quests you can actually do.
-- Progress comes from ActivityService. One free reroll per day; finishing (claiming) all
-- of them unlocks a bonus reward.

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
local DailyConfig = require(Config:WaitForChild("DailyConfig"))
local AbilityConfig = require(Config:WaitForChild("AbilityConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)
local CombatService = require(Services.CombatService)
local ModifierService = require(Services.ModifierService)
local ActivityService = require(Services.ActivityService)
local Analytics = require(Services.AnalyticsService)

type PlayerData = Types.PlayerData
type QuestState = Types.QuestState
type RewardDef = Types.RewardDef
type Result = { ok: boolean, reason: string? }
type Request = { action: string, arg: any }

local QUEST_BY_KEY: { [string]: Types.QuestDef } = {}
for _, def in DailyConfig.QUESTS do
	QUEST_BY_KEY[def.key] = def
end

local rng = Random.new()
-- Extra parts of the client view added by other services (achievements).
local viewProviders: { (player: Player, data: PlayerData) -> { [string]: any } } = {}
local dirty: { [Player]: boolean } = {}

local DailyService = {}

local function today(): number
	return os.time() // DailyConfig.DAY_SECONDS
end

---------------------------------------------------------------- rewards

-- Grants a reward bundle. Must not yield.
-- `source` names where the reward came from, for analytics (default "Daily").
function DailyService.grant(player: Player, data: PlayerData, reward: RewardDef, source: string?)
	if reward.goldMinutes ~= nil then
		local gold = Formulas.incomeGold(
			CombatService.getDps(player),
			ModifierService.get(player).gold,
			data.highestStage,
			reward.goldMinutes,
			DailyConfig.GOLD_MINIMUM
		)
		data.gold = BigNum.add(data.gold, gold)
		data.stats.lifetimeGold = BigNum.add(data.stats.lifetimeGold, gold)
	end
	if reward.packs ~= nil then
		data.packs.free += reward.packs
	end
	if reward.heroChests ~= nil then
		data.packs.hero += reward.heroChests
	end
	if reward.honor ~= nil then
		local honor = BigNum.fromNumber(reward.honor)
		data.honor = BigNum.add(data.honor, honor)
		data.stats.honorEarned = BigNum.add(data.stats.honorEarned, honor)
		Analytics.honor(player, "Source", honor, data.honor, source or "Daily")
	end
	DataService.markChanged(player)
end

---------------------------------------------------------------- quests

local function canDo(data: PlayerData, requirement: string?): boolean
	if requirement == nil then
		return true
	elseif requirement == "abilities" then
		return data.bestStage >= AbilityConfig.ABILITIES.Rally.unlockStage
	elseif requirement == "gear" then
		return data.bestStage >= 10
	elseif requirement == "faction" then
		return data.faction ~= ""
	elseif requirement == "clan" then
		return data.clanId ~= ""
	end
	return false
end

-- A random quest the player can do that isn't in `exclude`.
local function rollQuest(data: PlayerData, exclude: { [string]: boolean }): QuestState?
	local options: { Types.QuestDef } = {}
	for _, def in DailyConfig.QUESTS do
		if not exclude[def.key] and canDo(data, def.requires) then
			table.insert(options, def)
		end
	end
	if #options == 0 then
		return nil
	end
	local def = options[rng:NextInteger(1, #options)]
	local difficulty = rng:NextInteger(1, #def.targets)
	return { key = def.key, difficulty = difficulty, target = def.targets[difficulty], progress = 0, claimed = false }
end

-- Starts a new day's quests if the day changed.
local function ensureToday(data: PlayerData)
	local day = today()
	if data.quests.day == day then
		return
	end
	local list: { QuestState } = {}
	local used: { [string]: boolean } = {}
	for _ = 1, DailyConfig.QUESTS_PER_DAY do
		local quest = rollQuest(data, used)
		if quest ~= nil then
			used[quest.key] = true
			table.insert(list, quest)
		end
	end
	data.quests = { day = day, list = list, rerollsUsed = 0, bonusClaimed = false }
end

---------------------------------------------------------------- view

function DailyService.addViewFields(provider: (player: Player, data: PlayerData) -> { [string]: any })
	table.insert(viewProviders, provider)
end

function DailyService.markDirty(player: Player)
	dirty[player] = true
end

local function nextLoginIndex(data: PlayerData): number
	local day = today()
	local continuing = data.daily.lastClaimDay == day - 1 or data.daily.lastClaimDay == day
	if continuing then
		return data.daily.streak % #DailyConfig.LOGIN_REWARDS + 1
	end
	return 1
end

local function buildView(player: Player, data: PlayerData): Types.ProgressView
	ensureToday(data)
	local day = today()
	local view: Types.ProgressView = {
		studioTestMode = DailyConfig.IS_STUDIO_TEST_MODE,
		secondsToNextDay = (day + 1) * DailyConfig.DAY_SECONDS - os.time(),
		login = {
			canClaim = data.daily.lastClaimDay ~= day,
			nextIndex = nextLoginIndex(data),
			streak = if data.daily.lastClaimDay >= day - 1 then data.daily.streak else 0,
		},
		quests = data.quests.list,
		rerollsLeft = math.max(0, DailyConfig.REROLLS_PER_DAY - data.quests.rerollsUsed),
		bonusClaimed = data.quests.bonusClaimed,
		achievements = {},
	}
	for _, provider in viewProviders do
		for key, value in provider(player, data) do
			(view :: any)[key] = value
		end
	end
	return view
end

local function push(player: Player)
	local data = DataService.get(player)
	if data ~= nil and SyncService.isReady(player) then
		RemoteService.fireClient(Remotes.Events.ProgressSync, player, buildView(player, data))
	end
end

---------------------------------------------------------------- actions

local function claimLogin(player: Player, data: PlayerData): Result
	local day = today()
	if data.daily.lastClaimDay == day then
		return { ok = false, reason = "AlreadyClaimed" }
	end
	local index = nextLoginIndex(data)
	data.daily.lastClaimDay = day
	data.daily.streak = index
	DailyService.grant(player, data, DailyConfig.LOGIN_REWARDS[index])
	return { ok = true }
end

local function claimQuest(player: Player, data: PlayerData, index: number): Result
	local quest = data.quests.list[index]
	if quest == nil then
		return { ok = false, reason = "Rejected" }
	end
	if quest.claimed then
		return { ok = false, reason = "AlreadyClaimed" }
	end
	if quest.progress < quest.target then
		return { ok = false, reason = "NotDone" }
	end
	local def = QUEST_BY_KEY[quest.key]
	quest.claimed = true
	if def ~= nil then
		DailyService.grant(player, data, { goldMinutes = def.minutes[quest.difficulty] })
	end
	return { ok = true }
end

local function reroll(player: Player, data: PlayerData, index: number): Result
	local quest = data.quests.list[index]
	if quest == nil or quest.claimed then
		return { ok = false, reason = "Rejected" }
	end
	if data.quests.rerollsUsed >= DailyConfig.REROLLS_PER_DAY then
		return { ok = false, reason = "NoRerolls" }
	end
	local used: { [string]: boolean } = {}
	for _, other in data.quests.list do
		used[other.key] = true
	end
	local replacement = rollQuest(data, used)
	if replacement == nil then
		return { ok = false, reason = "NoOtherQuests" }
	end
	data.quests.list[index] = replacement
	data.quests.rerollsUsed += 1
	DataService.markChanged(player)
	return { ok = true }
end

local function claimBonus(player: Player, data: PlayerData): Result
	if data.quests.bonusClaimed then
		return { ok = false, reason = "AlreadyClaimed" }
	end
	if #data.quests.list == 0 then
		return { ok = false, reason = "NotDone" }
	end
	for _, quest in data.quests.list do
		if not quest.claimed then
			return { ok = false, reason = "NotDone" }
		end
	end
	data.quests.bonusClaimed = true
	DailyService.grant(player, data, DailyConfig.ALL_QUESTS_BONUS)
	return { ok = true }
end

-- Other services (achievements) add their own actions to the ProgressRequest remote.
local actions: { [string]: (player: Player, data: PlayerData, arg: any) -> Result } = {
	ClaimLogin = function(player, data, _arg)
		return claimLogin(player, data)
	end,
	ClaimQuest = function(player, data, arg)
		return claimQuest(player, data, arg)
	end,
	RerollQuest = function(player, data, arg)
		return reroll(player, data, arg)
	end,
	ClaimBonus = function(player, data, _arg)
		return claimBonus(player, data)
	end,
}

function DailyService.registerAction(name: string, handler: (player: Player, data: PlayerData, arg: any) -> Result)
	actions[name] = handler
end

---------------------------------------------------------------- lifecycle

function DailyService.start()
	ActivityService.Recorded:Connect(function(player: Player, activity: string, amount: number)
		local data = DataService.get(player)
		if data == nil then
			return
		end
		ensureToday(data)
		for _, quest in data.quests.list do
			local def = QUEST_BY_KEY[quest.key]
			if def ~= nil and def.activity == activity and not quest.claimed and quest.progress < quest.target then
				quest.progress = math.min(quest.target, quest.progress + amount)
				dirty[player] = true
			end
		end
	end)

	RemoteService.onInvoke(
		Remotes.Functions.ProgressRequest,
		RateLimiter.new(DailyConfig.REQUESTS_BURST, DailyConfig.REQUESTS_PER_SECOND),
		function(action: unknown, arg: unknown): Request?
			if typeof(action) ~= "string" or actions[action :: string] == nil then
				return nil
			end
			-- Every action takes nothing, a small whole number (list index), or a short string id.
			if arg ~= nil then
				local isIndex = typeof(arg) == "number" and arg == arg and (arg :: number) % 1 == 0
					and (arg :: number) >= 1 and (arg :: number) <= 50
				local isId = typeof(arg) == "string" and #(arg :: string) <= 40
				if not isIndex and not isId then
					return nil
				end
			end
			return { action = action :: string, arg = arg }
		end,
		function(player: Player, request: Request): Result
			local data = DataService.get(player)
			if data == nil then
				return { ok = false, reason = "NotLoaded" }
			end
			ensureToday(data)
			local result = actions[request.action](player, data, request.arg)
			dirty[player] = true
			return result
		end,
		{ ok = false, reason = "Rejected" } :: Result
	)

	SyncService.ClientReady:Connect(push)
	Players.PlayerRemoving:Connect(function(player: Player)
		dirty[player] = nil
	end)

	-- Send changes at most once a second, and refresh everyone when a new day starts.
	local lastDay = today()
	task.spawn(function()
		while true do
			task.wait(1)
			local day = today()
			for _, player in Players:GetPlayers() do
				if dirty[player] or day ~= lastDay then
					dirty[player] = nil
					push(player)
				end
			end
			lastDay = day
		end
	end)
end

return DailyService
