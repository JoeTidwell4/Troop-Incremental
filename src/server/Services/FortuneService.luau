--!strict
-- The Fortune Wheel (FortuneConfig): a free daily spin (given automatically at the day
-- change, banked up to MAX_SPINS), extra spins from daily rewards (DailyService.grant
-- `spins`), and the spin itself: weighted roll with a Jackpot pity counter. Nothing is
-- ever spent but a spin, and spins are never sold.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = Shared:WaitForChild("Config")
local FortuneConfig = require(Config:WaitForChild("FortuneConfig"))
local RelicConfig = require(Config:WaitForChild("RelicConfig"))
local DailyConfig = require(Config:WaitForChild("DailyConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)
local ActivityService = require(Services.ActivityService)
local DailyService = require(Services.DailyService)
local RelicService = require(Services.RelicService)

type PlayerData = Types.PlayerData
type Result = Types.FortuneResult

local random = Random.new()

local FortuneService = {}

local function today(): number
	return os.time() // DailyConfig.DAY_SECONDS
end

local function unlocked(data: PlayerData): boolean
	return data.bestStage >= FortuneConfig.UNLOCK_STAGE
end

-- Today's free spin, once per day. Returns true if one was added.
local function giveFree(data: PlayerData): boolean
	local day = today()
	if not unlocked(data) or data.fortune.freeDay == day then
		return false
	end
	data.fortune.freeDay = day
	data.fortune.spins = math.min(data.fortune.spins + 1, FortuneConfig.MAX_SPINS)
	return true
end

local function roll(data: PlayerData): number
	data.fortune.pity += 1
	local index = 1
	if data.fortune.pity >= FortuneConfig.PITY_JACKPOT then
		for i, prize in FortuneConfig.PRIZES do
			if prize.id == FortuneConfig.JACKPOT then
				index = i
			end
		end
	else
		local total = 0
		for _, prize in FortuneConfig.PRIZES do
			total += prize.weight
		end
		local value = random:NextNumber() * total
		for i, prize in FortuneConfig.PRIZES do
			value -= prize.weight
			if value < 0 then
				index = i
				break
			end
		end
	end
	if FortuneConfig.PRIZES[index].id == FortuneConfig.JACKPOT then
		data.fortune.pity = 0
	end
	return index
end

local function spin(player: Player, data: PlayerData): Result
	if not unlocked(data) then
		return { ok = false, reason = "Locked" }
	end
	giveFree(data)
	if data.fortune.spins <= 0 then
		return { ok = false, reason = "NoSpins" }
	end
	data.fortune.spins -= 1
	local index = roll(data)
	local prize = FortuneConfig.PRIZES[index]
	local result: Result = { ok = true, index = index }

	local dust = prize.dust or 0
	if prize.relic ~= nil then
		if data.bestStage >= RelicConfig.UNLOCK_STAGE then
			RelicService.drop(player, data, prize.relic)
			result.relic = true
		else
			dust += FortuneConfig.RELIC_FALLBACK_DUST
		end
	end
	if dust > 0 then
		data.relics.dust += dust
		result.dust = dust
	end
	local goldBefore = data.gold
	local honor = DailyService.grant(player, data, prize.reward, "Fortune")
	if not BigNum.isZero(honor) then
		result.honor = BigNum.toNumber(honor)
	end
	if prize.reward.goldMinutes ~= nil and BigNum.gt(data.gold, goldBefore) then
		result.gold = BigNum.sub(data.gold, goldBefore)
	end
	ActivityService.record(player, "WheelSpin", 1)
	DataService.markChanged(player)
	return result
end

---------------------------------------------------------------- Studio test panel

function FortuneService.debugAddSpins(player: Player, count: number)
	local data = DataService.get(player)
	if data ~= nil then
		data.fortune.spins = math.min(data.fortune.spins + count, FortuneConfig.MAX_SPINS)
		DataService.markChanged(player)
	end
end

function FortuneService.start()
	DataService.ProfileLoaded:Connect(function(_player: Player, data: PlayerData)
		giveFree(data)
	end)
	-- The day change for players who stay online (and the unlock).
	task.spawn(function()
		while true do
			task.wait(15)
			for _, player in Players:GetPlayers() do
				local data = DataService.get(player)
				if data ~= nil and giveFree(data) then
					DataService.markChanged(player)
				end
			end
		end
	end)

	SyncService.addSnapshotFields(function(_player: Player, data: PlayerData): { [string]: any }
		return {
			fortuneSpins = data.fortune.spins,
			fortunePity = data.fortune.pity,
			fortuneFreeAt = (today() + 1) * DailyConfig.DAY_SECONDS,
		}
	end)

	RemoteService.onInvoke(
		Remotes.Functions.FortuneRequest,
		RateLimiter.new(FortuneConfig.REQUESTS_BURST, FortuneConfig.REQUESTS_PER_SECOND),
		function(action: unknown): string?
			return if action == "Spin" then "Spin" else nil
		end,
		function(player: Player, _action: string): Result
			local data = DataService.get(player)
			if data == nil then
				return { ok = false, reason = "NotLoaded" }
			end
			return spin(player, data)
		end,
		{ ok = false, reason = "Rejected" } :: Result
	)
end

return FortuneService
