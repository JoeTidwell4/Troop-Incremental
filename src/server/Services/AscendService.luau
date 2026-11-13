--!strict
-- Ascend (prestige): trade this run's progress for permanent Honor.
--
-- Checked and applied entirely on the server, with no yields in between, so it can't be
-- done twice or half-way. See AscendConfig for exactly what resets and what's kept.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = Shared:WaitForChild("Config")
local AscendConfig = require(Config:WaitForChild("AscendConfig"))
local TroopConfig = require(Config:WaitForChild("TroopConfig"))
local GearConfig = require(Config:WaitForChild("GearConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local StageService = require(Services.StageService)
local Analytics = require(Services.AnalyticsService)
local ActivityService = require(Services.ActivityService)

type AscendResult = Types.AscendResult
type PlayerData = Types.PlayerData

local REJECTED: AscendResult = { ok = false, reason = "Rejected" }

local AscendService = {}

-- Honor the player would get for Ascending right now (zero if not allowed yet).
function AscendService.preview(data: PlayerData): BigNum.BigNum
	return Formulas.ascendHonor(data.highestStage, data.legacy.upgrades, data.skills.ranks)
end

-- Wipes everything that belongs to a single run (LegacyService uses it too).
function AscendService.resetRun(data: PlayerData)
	-- This run's best still counts toward unlocking the next Legacy.
	data.legacy.best = math.max(data.legacy.best, data.highestStage)
	data.gold = Formulas.startingGold(data.honorUpgrades)
	data.stage = 1
	data.highestStage = 1
	data.killsInStage = 0
	data.autoAdvance = true
	data.highestBossDefeated = 0
	data.packs.rewardedBossStage = 0 -- free packs are earned again each run
	for _, troopId in TroopConfig.ORDER do
		data.troops[troopId] = 0
		local troopGear = data.gear[troopId] :: any
		for _, slot in GearConfig.SLOTS do
			troopGear[slot] = { level = 0, rarity = 1 }
		end
	end
end

local function ascend(player: Player, _payload: boolean): AscendResult
	local data = DataService.get(player)
	if data == nil then
		return { ok = false, reason = "NotLoaded" }
	end
	if data.highestStage < AscendConfig.MIN_STAGE then
		return { ok = false, reason = "TooEarly" }
	end
	-- Not mid-raid: raid units are scored against this run's stage, which Ascending resets.
	local encounter = StageService.getEncounter(player)
	if encounter ~= nil and encounter.kind == "Raid" then
		return { ok = false, reason = "InRaid" }
	end

	local honor = AscendService.preview(data)
	data.honor = BigNum.add(data.honor, honor)
	data.stats.honorEarned = BigNum.add(data.stats.honorEarned, honor)
	data.stats.ascensions += 1
	ActivityService.record(player, "AscendStage", data.highestStage) -- Commander XP
	Analytics.ascended(player, data.highestStage, data.stats.ascensions)
	Analytics.honor(player, "Source", honor, data.honor, "Ascend")
	AscendService.resetRun(data)

	StageService.restart(player) -- also recalculates the (now empty) army
	return { ok = true, honor = honor }
end

function AscendService.start()
	local limiter = RateLimiter.new(AscendConfig.REQUESTS_BURST, AscendConfig.REQUESTS_PER_SECOND)
	RemoteService.onInvoke(Remotes.Functions.Ascend, limiter, function(): boolean?
		return true -- takes no arguments
	end, ascend, REJECTED)
end

return AscendService
