--!strict
-- The Endless Tower (TowerConfig): climbing, first-clear rewards, Tower Chests, the
-- permanent bonus and the daily Tribute. The fight itself runs in StageService
-- (startTower / TowerFinished); the laws are applied where the thing they change lives
-- (CombatService, AbilityService, WeakPointService, StageService), all read from
-- Formulas.towerFloor.
--
-- "Climb" fights the floor above your best and keeps going after each win (a short pause
-- between floors) until you lose or press Leave. Losing costs nothing.

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
local TowerConfig = require(Config:WaitForChild("TowerConfig"))
local DailyConfig = require(Config:WaitForChild("DailyConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)
local ModifierService = require(Services.ModifierService)
local StageService = require(Services.StageService)
local ActivityService = require(Services.ActivityService)
local DailyService = require(Services.DailyService)
local RelicService = require(Services.RelicService)

type PlayerData = Types.PlayerData
type Result = Types.TowerResult

local random = Random.new()
-- Players who pressed Climb and haven't lost or left since: the next floor starts by itself.
local climbing: { [Player]: boolean } = {}

local TowerService = {}

local function today(): number
	return os.time() // DailyConfig.DAY_SECONDS
end

local function notify(player: Player, notice: Types.Notice)
	RemoteService.fireClient(Remotes.Events.Notice, player, notice)
end

-- nil when the player may start a floor right now, else why not.
local function blocked(player: Player, data: PlayerData): string?
	if data.bestStage < TowerConfig.UNLOCK_STAGE then
		return "Locked"
	end
	if data.challenge.active ~= "" then
		return "InChallenge" -- challenge rules would skew the climb
	end
	local encounter = StageService.getEncounter(player)
	if encounter == nil or encounter.kind ~= "Normal" then
		return "InFight"
	end
	return nil
end

local function climb(player: Player, data: PlayerData): Result
	local reason = blocked(player, data)
	if reason ~= nil then
		return { ok = false, reason = reason }
	end
	if not StageService.startTower(player, data.tower.best + 1) then
		return { ok = false, reason = "InFight" }
	end
	climbing[player] = true
	return { ok = true }
end

-- Stops climbing; walks out of the current floor if one is being fought.
local function leave(player: Player): Result
	climbing[player] = nil
	StageService.leaveTower(player)
	return { ok = true }
end

local function tribute(player: Player, data: PlayerData): Result
	if data.tower.best < 1 then
		return { ok = false, reason = "NoFloors" }
	end
	local day = today()
	if data.tower.tributeDay == day then
		return { ok = false, reason = "Claimed" }
	end
	data.tower.tributeDay = day
	local minutes, dust = Formulas.towerTribute(data.tower.best)
	DailyService.grant(player, data, { goldMinutes = minutes }, "Tower")
	data.relics.dust += dust
	DataService.markChanged(player)
	notify(player, { kind = "TowerTribute", stage = data.tower.best, seconds = minutes * 60, dust = dust })
	return { ok = true }
end

local function rollPrize(): Types.TowerPrizeDef
	local total = 0
	for _, prize in TowerConfig.CHEST_PRIZES do
		total += prize.weight
	end
	local roll = random:NextNumber() * total
	for _, prize in TowerConfig.CHEST_PRIZES do
		roll -= prize.weight
		if roll < 0 then
			return prize
		end
	end
	return TowerConfig.CHEST_PRIZES[1]
end

-- First clear of `floor`: Dust + Honor, a Tower Chest on chest floors.
local function reward(player: Player, data: PlayerData, floor: number)
	local info = Formulas.towerFloor(floor)
	local honor = DailyService.grant(player, data, {
		honorShare = TowerConfig.FLOOR_HONOR_SHARE,
		honor = TowerConfig.FLOOR_HONOR_MIN,
	}, "Tower")
	local dust = Formulas.towerFloorDust(floor)
	local prizeId: string? = nil
	if info.chest then
		local prize = rollPrize()
		prizeId = prize.id
		if prize.scrolls ~= nil then
			data.generals.scrolls += prize.scrolls
		end
		if prize.heroChests ~= nil then
			data.packs.hero += prize.heroChests
		end
		if prize.id == "Dust" then
			dust += Formulas.towerChestDust(floor)
		elseif prize.id == "Relic" then
			RelicService.drop(player, data, "Epic")
		elseif prize.id == "Jackpot" then
			RelicService.drop(player, data, "Legendary")
		end
	end
	data.relics.dust += dust
	ActivityService.record(player, "TowerFloor", 1)
	notify(player, {
		kind = "TowerFloor",
		stage = floor,
		honor = BigNum.toNumber(honor),
		dust = dust,
		prize = prizeId,
		bonus = floor % TowerConfig.BONUS_EVERY == 0,
	})
end

local function onFinished(player: Player, floor: number, won: boolean, reason: string)
	local data = DataService.get(player)
	if data == nil then
		climbing[player] = nil
		return
	end
	if not won then
		climbing[player] = nil
		if reason == "OutOfTime" or reason == "ArmyDefeated" then
			notify(player, { kind = "TowerFailed", stage = floor, reason = reason :: any })
		end
		return
	end
	if floor == data.tower.best + 1 then
		data.tower.best = floor
		reward(player, data, floor)
	end
	DataService.markChanged(player)
	if climbing[player] then
		-- Keep climbing: the next floor after a short pause (the boss's death plays out).
		task.delay(TowerConfig.NEXT_FLOOR_DELAY, function()
			local current = DataService.get(player)
			if current == nil or not climbing[player] then
				return
			end
			if blocked(player, current) ~= nil or not StageService.startTower(player, current.tower.best + 1) then
				climbing[player] = nil
			end
		end)
	end
end

local ACTIONS: { [string]: boolean } = { Climb = true, Leave = true, Tribute = true }

local function handle(player: Player, action: string): Result
	local data = DataService.get(player)
	if data == nil then
		return { ok = false, reason = "NotLoaded" }
	end
	if action == "Climb" then
		return climb(player, data)
	elseif action == "Leave" then
		return leave(player)
	end
	return tribute(player, data)
end

---------------------------------------------------------------- Studio test panel

-- Adds floors to the best floor without fights or rewards.
function TowerService.debugAddFloors(player: Player, floors: number)
	local data = DataService.get(player)
	if data ~= nil then
		data.tower.best += floors
		DataService.markChanged(player)
	end
end

function TowerService.debugResetTribute(player: Player)
	local data = DataService.get(player)
	if data ~= nil then
		data.tower.tributeDay = -1
		DataService.markChanged(player)
	end
end

function TowerService.start()
	StageService.TowerFinished:Connect(onFinished)
	Players.PlayerRemoving:Connect(function(player: Player)
		climbing[player] = nil
	end)

	-- Permanent bonus from the best floor.
	ModifierService.register(function(player: Player): ModifierService.PartialModifiers?
		local data = DataService.get(player)
		if data == nil then
			return nil
		end
		local bonus = Formulas.towerBonus(data.tower.best)
		return { damage = bonus, gold = bonus }
	end)

	SyncService.addSnapshotFields(function(_player: Player, data: PlayerData): { [string]: any }
		return {
			towerBest = data.tower.best,
			towerTributeReady = data.tower.best >= 1 and data.tower.tributeDay ~= today(),
		}
	end)

	RemoteService.onInvoke(
		Remotes.Functions.TowerRequest,
		RateLimiter.new(TowerConfig.REQUESTS_BURST, TowerConfig.REQUESTS_PER_SECOND),
		function(action: unknown): string?
			if typeof(action) == "string" and ACTIONS[action :: string] then
				return action :: string
			end
			return nil
		end,
		handle,
		{ ok = false, reason = "Rejected" } :: Result
	)
end

return TowerService
