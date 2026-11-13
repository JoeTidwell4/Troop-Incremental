--!strict
-- Sends gameplay analytics to Roblox (AnalyticsService), so balance changes can use
-- real player data instead of only the Python sims. Results: Creator Dashboard ->
-- your experience -> Analytics.
--
--   Onboarding funnel  first-time milestones, in order (where do new players quit?)
--   Progression "Boss" every boss attempt: start / complete / fail (+ why it failed)
--   Economy "Honor"    Honor earned (Ascend, daily, raid) and spent (Honor shop)
--   Custom "Ascend"    value = stage reached that run
--   Custom "SessionEnd" value = minutes played, with best stage + ascension buckets
--
-- Every call is pcall-wrapped and rate-capped per player: analytics must never break
-- or slow the game. Other services report through the small public functions below.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local AnalyticsConfig = require(Shared:WaitForChild("Config"):WaitForChild("AnalyticsConfig"))
local DataService = require(Services.DataService)
local StageService = require(Services.StageService)

type PlayerData = Types.PlayerData
type BigNum = BigNum.BigNum

local IS_STUDIO = RunService:IsStudio()
local FIELD_1 = Enum.AnalyticsCustomFieldKeys.CustomField01.Name
local FIELD_2 = Enum.AnalyticsCustomFieldKeys.CustomField02.Name

local Analytics = {}

---------------------------------------------------------------- sending

-- Per-player budget: { windowStart, count }.
local budgets: { [Player]: { start: number, count: number } } = {}
local sessionStart: { [Player]: number } = {}

local function allowed(player: Player): boolean
	local now = os.clock()
	local budget = budgets[player]
	if budget == nil or now - budget.start >= 60 then
		budget = { start = now, count = 0 }
		budgets[player] = budget
	end
	if budget.count >= AnalyticsConfig.MAX_EVENTS_PER_PLAYER_PER_MINUTE then
		return false
	end
	budget.count += 1
	return true
end

local function send(player: Player, description: string, call: () -> ())
	if not allowed(player) then
		return
	end
	if IS_STUDIO then
		-- Studio play-tests never reach the dashboard; just show what would be sent.
		if AnalyticsConfig.PRINT_IN_STUDIO then
			print(`[Analytics] {player.Name}: {description}`)
		end
		return
	end
	local ok, err = pcall(call)
	if not ok then
		warn(`[Analytics] {description} failed: {err}`)
	end
end

local function stageBucket(stage: number): string
	local size = AnalyticsConfig.STAGE_BUCKET
	local low = (math.max(1, stage) - 1) // size * size + 1
	return `{low}-{low + size - 1}`
end

local function ascensionBucket(count: number): string
	return if count >= 10 then "10+" else tostring(count)
end

---------------------------------------------------------------- onboarding funnel

local function totalTroops(data: PlayerData): number
	local total = 0
	for _, count in data.troops do
		total += count
	end
	return total
end

local function anyGear(data: PlayerData): boolean
	for _, troopGear in data.gear do
		if troopGear.weapon.level > 0 or troopGear.armor.level > 0 then
			return true
		end
	end
	return false
end

type Step = { name: string, reached: (data: PlayerData) -> boolean }

-- In order; a step is only logged after every step before it. Checks are generous for
-- old saves (e.g. owning troops counts as "bought a troop").
local ONBOARDING: { Step } = {
	{
		name = "Joined",
		reached = function(_data: PlayerData): boolean
			return true
		end,
	},
	{
		name = "FirstKill",
		reached = function(data: PlayerData): boolean
			return data.stats.totalKills > 0
		end,
	},
	{
		name = "FirstTroop",
		reached = function(data: PlayerData): boolean
			return (data.lifetime.TroopBuy or 0) > 0 or totalTroops(data) > 0 or data.stats.ascensions > 0
		end,
	},
}
for index, stage in AnalyticsConfig.STAGE_STEPS do
	table.insert(ONBOARDING, {
		name = if stage == 11 then "BeatFirstBoss" else `Stage{stage}`,
		reached = function(data: PlayerData): boolean
			return data.bestStage >= stage
		end,
	})
	if index == 2 then
		-- First gear upgrade sits right after the first boss in a normal run.
		table.insert(ONBOARDING, {
			name = "FirstGear",
			reached = function(data: PlayerData): boolean
				return (data.lifetime.GearUpgrade or 0) > 0 or anyGear(data) or data.stats.ascensions > 0
			end,
		})
	end
end
table.insert(ONBOARDING, {
	name = "FirstAscend",
	reached = function(data: PlayerData): boolean
		return data.stats.ascensions > 0
	end,
})

local dirty: { [Player]: boolean } = {}

local function checkOnboarding(player: Player, data: PlayerData)
	local saved = tonumber(data.analytics.onboardingStep) or 0
	local step = saved
	while step < #ONBOARDING and ONBOARDING[step + 1].reached(data) do
		step += 1
		local name = ONBOARDING[step].name
		local stepNumber = step
		send(player, `onboarding {stepNumber} {name}`, function()
			AnalyticsService:LogOnboardingFunnelStepEvent(player, stepNumber, name)
		end)
	end
	if step ~= saved then
		data.analytics.onboardingStep = step
		DataService.markChanged(player)
	end
end

---------------------------------------------------------------- public

-- Where Honor comes from / goes, mapped to Roblox's standard transaction types.
local HONOR_TRANSACTIONS: { [string]: Enum.AnalyticsEconomyTransactionType } = {
	Ascend = Enum.AnalyticsEconomyTransactionType.Gameplay,
	Raid = Enum.AnalyticsEconomyTransactionType.Gameplay,
	Achievement = Enum.AnalyticsEconomyTransactionType.Gameplay,
	Daily = Enum.AnalyticsEconomyTransactionType.TimedReward,
	HonorShop = Enum.AnalyticsEconomyTransactionType.Shop,
}

-- Honor gained ("Source") or spent ("Sink"). `reason`: "Ascend", "Raid", "Achievement",
-- "Daily" or "HonorShop"; `item` names what was bought (Honor shop upgrade id).
function Analytics.honor(player: Player, flow: "Source" | "Sink", amount: BigNum, balance: BigNum, reason: string, item: string?)
	local value = BigNum.toNumber(amount)
	if value <= 0 then
		return
	end
	local flowType = if flow == "Source" then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink
	local transaction = (HONOR_TRANSACTIONS[reason] or Enum.AnalyticsEconomyTransactionType.Gameplay).Name
	local sku = item or reason
	send(player, `honor {flow} {value} ({reason} {sku})`, function()
		AnalyticsService:LogEconomyEvent(player, flowType, "Honor", value, BigNum.toNumber(balance), transaction, sku)
	end)
end

-- A finished run: the stage reached before Ascending.
function Analytics.ascended(player: Player, stage: number, ascensions: number)
	send(player, `ascend at stage {stage}`, function()
		AnalyticsService:LogCustomEvent(player, "Ascend", stage, {
			[FIELD_1] = ascensionBucket(ascensions),
		})
	end)
end

-- A Legacy (second prestige): value = best stage this Legacy, field = how many so far.
function Analytics.legacy(player: Player, stage: number, count: number, crowns: number)
	send(player, `legacy #{count} at stage {stage} for {crowns} Crowns`, function()
		AnalyticsService:LogCustomEvent(player, "Legacy", stage, {
			[FIELD_1] = `legacy {math.min(count, 10)}`,
		})
	end)
end

---------------------------------------------------------------- start

function Analytics.start()
	DataService.ProfileLoaded:Connect(function(player: Player, _data: PlayerData)
		sessionStart[player] = os.clock()
		dirty[player] = true
	end)
	DataService.Changed:Connect(function(player: Player)
		dirty[player] = true
	end)

	StageService.BossStarted:Connect(function(player: Player, stage: number)
		send(player, `boss {stage} start`, function()
			AnalyticsService:LogProgressionStartEvent(player, "Boss", stage, `Stage {stage}`)
		end)
	end)
	StageService.BossDefeated:Connect(function(player: Player, stage: number, _firstClear: boolean)
		send(player, `boss {stage} complete`, function()
			AnalyticsService:LogProgressionCompleteEvent(player, "Boss", stage, `Stage {stage}`)
		end)
	end)
	StageService.BossFailed:Connect(function(player: Player, stage: number, reason: string)
		send(player, `boss {stage} fail ({reason})`, function()
			AnalyticsService:LogProgressionFailEvent(player, "Boss", stage, `Stage {stage}`, {
				[FIELD_1] = reason,
			})
		end)
	end)

	-- Session length and how far the player got, sent when they leave (the save is
	-- still readable while ProfileReleasing listeners run).
	DataService.ProfileReleasing:Connect(function(player: Player)
		local started = sessionStart[player]
		local data = DataService.get(player)
		if started ~= nil and data ~= nil then
			local minutes = math.floor((os.clock() - started) / 60 * 10) / 10
			local bestStage = data.bestStage
			local ascensions = data.stats.ascensions
			send(player, `session end {minutes} min`, function()
				AnalyticsService:LogCustomEvent(player, "SessionEnd", minutes, {
					[FIELD_1] = stageBucket(bestStage),
					[FIELD_2] = ascensionBucket(ascensions),
				})
			end)
		end
		sessionStart[player] = nil
		dirty[player] = nil
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		task.delay(5, function()
			budgets[player] = nil -- after the SessionEnd event has used it
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(AnalyticsConfig.CHECK_INTERVAL)
			for player in dirty do
				dirty[player] = nil
				local data = DataService.get(player)
				if data ~= nil then
					checkOnboarding(player, data)
				end
			end
		end
	end)
end

return Analytics
