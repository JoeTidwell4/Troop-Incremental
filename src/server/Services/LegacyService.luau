--!strict
-- Legacy: the second prestige (LegacyConfig). Trades the whole Honor game (Honor, Honor
-- upgrades, ability upgrades) plus the current run for Crowns, which buy permanent
-- upgrades that are never reset.
--
-- Like Ascend, everything is checked and applied on the server with no yields in
-- between, so it can't happen twice or half-way. The player's save is session-locked, so
-- nothing here needs cross-server care.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local LegacyConfig = require(Shared:WaitForChild("Config"):WaitForChild("LegacyConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local Validate = require(Server.Util.Validate)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)
local ModifierService = require(Services.ModifierService)
local StageService = require(Services.StageService)
local AscendService = require(Services.AscendService)
local Analytics = require(Services.AnalyticsService)

type PlayerData = Types.PlayerData
type LegacyResult = Types.LegacyResult
type BuyResult = Types.BuyResult

local LegacyService = {}

-- Best stage reached during this Legacy, counting the run in progress.
local function bestThisLegacy(data: PlayerData): number
	return math.max(data.legacy.best, data.highestStage)
end

-- Crowns a Legacy right now would give (0 if not allowed yet).
function LegacyService.preview(data: PlayerData): number
	if bestThisLegacy(data) < LegacyConfig.MIN_STAGE then
		return 0
	end
	local earned = BigNum.max(BigNum.sub(data.stats.honorEarned, data.legacy.honorAtStart), BigNum.ZERO)
	return Formulas.legacyCrowns(earned)
end

local function doLegacy(player: Player, _payload: boolean): LegacyResult
	local data = DataService.get(player)
	if data == nil then
		return { ok = false, reason = "NotLoaded" }
	end
	if bestThisLegacy(data) < LegacyConfig.MIN_STAGE then
		return { ok = false, reason = "TooEarly" }
	end
	local crowns = LegacyService.preview(data)
	if crowns < 1 then
		return { ok = false, reason = "NoCrowns" }
	end
	-- Not mid-raid: raid units are scored against this run's stage.
	local encounter = StageService.getEncounter(player)
	if encounter ~= nil and encounter.kind == "Raid" then
		return { ok = false, reason = "InRaid" }
	end

	local stage = bestThisLegacy(data)
	local legacy = data.legacy
	legacy.count += 1
	legacy.crowns += crowns
	legacy.crownsEarned += crowns
	-- The Honor game starts over.
	data.honor = BigNum.ZERO
	data.honorUpgrades = {}
	data.abilityUpgrades = {}
	data.bossWeaken = { stage = 0, fails = 0 }
	AscendService.resetRun(data) -- gold (now with no Head Start), stage, troops, gear...
	legacy.best = 1
	legacy.honorAtStart = data.stats.honorEarned
	Analytics.legacy(player, stage, legacy.count, crowns)

	StageService.restart(player) -- also recalculates the (now empty) army
	return { ok = true, crowns = crowns }
end

local function buyUpgrade(player: Player, upgradeId: string): BuyResult
	local data = DataService.get(player)
	local def = LegacyConfig.UPGRADES[upgradeId]
	if data == nil or def == nil then
		return { ok = false, bought = 0, reason = "NotLoaded" }
	end
	local level = data.legacy.upgrades[upgradeId] or 0
	if def.maxLevel ~= nil and level >= def.maxLevel then
		return { ok = false, bought = 0, reason = "MaxReached" }
	end
	local cost = Formulas.crownUpgradeCost(upgradeId, level)
	if data.legacy.crowns < cost then
		return { ok = false, bought = 0, reason = "CantAfford" }
	end
	data.legacy.crowns -= cost
	data.legacy.upgrades[upgradeId] = level + 1
	DataService.markChanged(player)
	return { ok = true, bought = 1 }
end

function LegacyService.start()
	-- Permanent Crown bonuses: damage, army HP and gold. (Eternal Glory is applied to
	-- Ascend Honor in Formulas.ascendHonor.)
	ModifierService.register(function(player: Player): ModifierService.PartialModifiers?
		local data = DataService.get(player)
		if data == nil then
			return nil
		end
		local upgrades = data.legacy.upgrades
		return {
			damage = Formulas.crownMultiplier(upgrades, "damage"),
			armyHp = Formulas.crownMultiplier(upgrades, "armyHp"),
			gold = Formulas.crownMultiplier(upgrades, "gold"),
		}
	end)

	SyncService.addSnapshotFields(function(_player: Player, data: PlayerData): { [string]: any }
		return {
			legacyCount = data.legacy.count,
			crowns = data.legacy.crowns,
			crownUpgrades = data.legacy.upgrades,
			legacyBest = bestThisLegacy(data),
			legacyCrowns = LegacyService.preview(data),
		}
	end)

	local limiter = RateLimiter.new(LegacyConfig.REQUESTS_BURST, LegacyConfig.REQUESTS_PER_SECOND)
	RemoteService.onInvoke(Remotes.Functions.Legacy, limiter, function(): boolean?
		return true -- takes no arguments
	end, doLegacy, { ok = false, reason = "Rejected" } :: LegacyResult)
	RemoteService.onInvoke(Remotes.Functions.BuyCrownUpgrade, limiter, function(upgradeId: unknown): string?
		return Validate.keyOf(upgradeId, LegacyConfig.UPGRADES)
	end, buyUpgrade, { ok = false, bought = 0, reason = "Rejected" } :: BuyResult)
end

return LegacyService
