--!strict
-- Challenge runs (ChallengeConfig): a fresh run with one nasty rule, played while the
-- main run is parked.
--
-- Start: the main run (gold, stage, troops, gear, boss tracking) is copied into
-- data.challenge.stash, then the run is reset like an Ascend (no Honor) and restarted.
-- Leave / final tier / Glass Army defeat: the stash is put back exactly as it was.
-- Beating the boss of a goal stage clears a tier: permanent bonus (ModifierService source
-- + Formulas.challengeBonuses hooks) and a one-off prize.
--
-- The rules themselves live where the thing they change lives (all through
-- Formulas.challengeRules / fightBuild): TroopService (onlyTroop), CombatService
-- (noClicks, noGear, noExtras), AbilityService + WeakPointService (noClicks),
-- StageService (boss time / HP / moves, noExtras), Skill / General / RelicService
-- (noExtras), here (goldScale, oneLife). Also: PackService (no free boss packs, Free /
-- Hero / Forge kept for the main run), AscendService, LegacyService and RaidService
-- refuse inside a challenge, and gold rewards / gold products are held in
-- data.challenge.goldMinutes and paid out here on the main run.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = Shared:WaitForChild("Config")
local ChallengeConfig = require(Config:WaitForChild("ChallengeConfig"))
local MonetizationConfig = require(Config:WaitForChild("MonetizationConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)
local ModifierService = require(Services.ModifierService)
local CombatService = require(Services.CombatService)
local StageService = require(Services.StageService)
local ActivityService = require(Services.ActivityService)
local AscendService = require(Services.AscendService)
local DailyService = require(Services.DailyService)

type PlayerData = Types.PlayerData
type Result = Types.ChallengeResult

local ChallengeService = {}

local function deepCopy<T>(value: T): T
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value :: any do
		copy[key] = deepCopy(item)
	end
	return copy :: any
end

local function notify(player: Player, notice: Types.Notice)
	RemoteService.fireClient(Remotes.Events.Notice, player, notice)
end

-- Copies the main run aside. Everything AscendService.resetRun touches must be here.
local function park(data: PlayerData): Types.ChallengeStash
	return {
		gold = data.gold,
		stage = data.stage,
		highestStage = data.highestStage,
		killsInStage = data.killsInStage,
		autoAdvance = data.autoAdvance,
		highestBossDefeated = data.highestBossDefeated,
		rewardedBossStage = data.packs.rewardedBossStage,
		weakenStage = data.bossWeaken.stage,
		weakenFails = data.bossWeaken.fails,
		troops = deepCopy(data.troops),
		gear = deepCopy(data.gear),
	}
end

local function restore(data: PlayerData, stash: Types.ChallengeStash)
	data.gold = stash.gold
	data.stage = stash.stage
	data.highestStage = stash.highestStage
	data.killsInStage = stash.killsInStage
	data.autoAdvance = stash.autoAdvance
	data.highestBossDefeated = stash.highestBossDefeated
	data.packs.rewardedBossStage = stash.rewardedBossStage
	data.bossWeaken.stage = stash.weakenStage
	data.bossWeaken.fails = stash.weakenFails
	for troopId in data.troops do
		data.troops[troopId] = stash.troops[troopId] or 0
		local parked = stash.gear[troopId]
		if parked ~= nil then
			data.gear[troopId] = parked
		end
	end
end

local function start(player: Player, data: PlayerData, challengeId: string): Result
	local def = ChallengeConfig.CHALLENGES[challengeId]
	if def == nil then
		return { ok = false, reason = "Rejected" }
	end
	if data.challenge.active ~= "" then
		return { ok = false, reason = "AlreadyIn" }
	end
	if data.stats.ascensions < def.unlockAscends then
		return { ok = false, reason = "Locked" }
	end
	if (data.challenge.tiers[challengeId] or 0) >= #ChallengeConfig.TIER_GOALS then
		return { ok = false, reason = "Complete" }
	end
	-- Not in a boss fight or a raid: the parked run must come back to a normal stage.
	local encounter = StageService.getEncounter(player)
	if encounter == nil or encounter.kind ~= "Normal" then
		return { ok = false, reason = "InFight" }
	end

	data.challenge.stash = park(data)
	data.challenge.active = challengeId
	AscendService.resetRun(data)
	data.bossWeaken.stage = 0
	data.bossWeaken.fails = 0
	StageService.restart(player) -- recalculates the (empty) army under the challenge's rules
	ActivityService.record(player, "ChallengeStart", 1)
	return { ok = true }
end

-- Ends the challenge and brings the main run back. `reason`: "Left" | "Complete" | "Defeated".
local function finish(player: Player, data: PlayerData, reason: string): Result
	local challengeId = data.challenge.active
	local stash = data.challenge.stash
	if challengeId == "" or stash == nil then
		return { ok = false, reason = "NotIn" }
	end
	data.challenge.active = ""
	data.challenge.stash = nil
	restore(data, stash)
	StageService.restart(player) -- army + encounter of the main run, normal rules again

	-- Gold rewards and gold purchases held during the challenge, at the main run's rate.
	local paid: BigNum.BigNum? = nil
	local minutes = data.challenge.goldMinutes
	if minutes > 0 then
		data.challenge.goldMinutes = 0
		local gold = Formulas.incomeGold(
			CombatService.getDps(player),
			ModifierService.get(player).gold,
			data.highestStage,
			minutes,
			MonetizationConfig.GOLD_PRODUCT_MINIMUM
		)
		data.gold = BigNum.add(data.gold, gold)
		data.stats.lifetimeGold = BigNum.add(data.stats.lifetimeGold, gold)
		paid = gold
	end
	DataService.markChanged(player)
	notify(player, { kind = "ChallengeEnded", stage = data.stage, challengeId = challengeId, challengeReason = reason, gold = paid })
	return { ok = true }
end

-- Clears every tier whose goal boss is beaten. Returns true if the last tier is done.
local function checkTiers(player: Player, data: PlayerData): boolean
	local challengeId = data.challenge.active
	if challengeId == "" then
		return false
	end
	local tiers = data.challenge.tiers
	local cleared = tiers[challengeId] or 0
	while true do
		local goal = Formulas.challengeGoal(cleared + 1)
		if goal == nil or data.highestBossDefeated < goal then
			break
		end
		cleared += 1
		tiers[challengeId] = cleared
		local reward = ChallengeConfig.TIER_REWARDS[cleared]
		local honor = DailyService.grant(player, data, {
			honorShare = reward.honorShare,
			honor = reward.honor,
			scrolls = reward.scrolls,
			heroChests = reward.heroChests,
		}, "Challenge")
		if reward.relicDust ~= nil then
			data.relics.dust += reward.relicDust
		end
		ActivityService.record(player, "ChallengeTier", 1)
		notify(player, {
			kind = "ChallengeTier",
			stage = goal,
			challengeId = challengeId,
			tier = cleared,
			honor = BigNum.toNumber(honor),
			scrolls = reward.scrolls,
			dust = reward.relicDust,
			heroChests = reward.heroChests,
		})
	end
	DataService.markChanged(player)
	return cleared >= #ChallengeConfig.TIER_GOALS
end

local ACTIONS: { [string]: boolean } = { Start = true, Leave = true }

local function validate(action: unknown, challengeId: unknown): { action: string, challengeId: string }?
	if typeof(action) ~= "string" or not ACTIONS[action :: string] then
		return nil
	end
	if action == "Start" and (typeof(challengeId) ~= "string" or ChallengeConfig.CHALLENGES[challengeId :: string] == nil) then
		return nil
	end
	return { action = action :: string, challengeId = if typeof(challengeId) == "string" then challengeId :: string else "" }
end

local function handle(player: Player, request: { action: string, challengeId: string }): Result
	local data = DataService.get(player)
	if data == nil then
		return { ok = false, reason = "NotLoaded" }
	end
	if request.action == "Start" then
		return start(player, data, request.challengeId)
	end
	return finish(player, data, "Left")
end

-- Test panel: clears the next tier of the challenge you're in (false when not in one).
function ChallengeService.debugClearTier(player: Player): boolean
	local data = DataService.get(player)
	if data == nil or data.challenge.active == "" then
		return false
	end
	local goal = Formulas.challengeGoal((data.challenge.tiers[data.challenge.active] or 0) + 1)
	if goal == nil then
		return false
	end
	data.highestBossDefeated = math.max(data.highestBossDefeated, goal)
	if checkTiers(player, data) then
		finish(player, data, "Complete")
	end
	return true
end

function ChallengeService.start()
	-- Permanent bonuses from cleared tiers, and the Poverty rule.
	ModifierService.register(function(player: Player): ModifierService.PartialModifiers?
		local data = DataService.get(player)
		if data == nil then
			return nil
		end
		local bonuses = Formulas.challengeBonuses(data.challenge.tiers)
		local damage = bonuses.damage
		local encounter = StageService.getEncounter(player)
		if encounter ~= nil and encounter.kind ~= "Normal" then
			damage *= bonuses.bossDamageDealt
		end
		return {
			damage = damage,
			armyHp = bonuses.armyHp,
			gold = bonuses.gold * (Formulas.challengeRules(data.challenge.active).goldScale or 1),
			tap = bonuses.tap,
		}
	end)

	SyncService.addSnapshotFields(function(_player: Player, data: PlayerData): { [string]: any }
		return { challengeActive = data.challenge.active, challengeTiers = data.challenge.tiers }
	end)

	-- Tier goals. Deferred: StageService is still in the middle of clearing the stage
	-- when this fires, and finishing a challenge swaps the whole run underneath it.
	StageService.BossDefeated:Connect(function(player: Player, _bossStage: number, _firstClear: boolean)
		local data = DataService.get(player)
		if data == nil or data.challenge.active == "" then
			return
		end
		if checkTiers(player, data) then
			task.defer(function()
				local current = DataService.get(player)
				if current ~= nil and current.challenge.active ~= "" then
					finish(player, current, "Complete")
				end
			end)
		end
	end)
	-- Glass Army: one lost boss fight ends the challenge.
	StageService.BossFailed:Connect(function(player: Player, _bossStage: number, _reason: string)
		local data = DataService.get(player)
		if data == nil or not Formulas.challengeRules(data.challenge.active).oneLife then
			return
		end
		task.defer(function()
			local current = DataService.get(player)
			if current ~= nil and Formulas.challengeRules(current.challenge.active).oneLife then
				finish(player, current, "Defeated")
			end
		end)
	end)

	RemoteService.onInvoke(
		Remotes.Functions.ChallengeRequest,
		RateLimiter.new(ChallengeConfig.REQUESTS_BURST, ChallengeConfig.REQUESTS_PER_SECOND),
		validate,
		handle,
		{ ok = false, reason = "Rejected" } :: Result
	)
end

return ChallengeService
