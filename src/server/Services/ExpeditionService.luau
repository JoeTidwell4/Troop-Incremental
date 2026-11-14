--!strict
-- Expeditions (ExpeditionConfig): the mission board, sending teams of spare Generals (or
-- the Scout Party), and collecting what they bring back. Times are os.time(), so missions
-- keep running while the player is offline. Missions always succeed.

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
local ExpeditionConfig = require(Config:WaitForChild("ExpeditionConfig"))
local GeneralConfig = require(Config:WaitForChild("GeneralConfig"))
local DailyConfig = require(Config:WaitForChild("DailyConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)
local ActivityService = require(Services.ActivityService)
local DailyService = require(Services.DailyService)
local RelicService = require(Services.RelicService)

type PlayerData = Types.PlayerData
type Mission = Types.ExpeditionMission
type Result = Types.ExpeditionResult

local random = Random.new()

local ExpeditionService = {}

local function today(): number
	return os.time() // DailyConfig.DAY_SECONDS
end

local function unlocked(data: PlayerData): boolean
	return data.bestStage >= ExpeditionConfig.UNLOCK_STAGE
end

local function weighted<T>(list: { T }, weightOf: (T) -> number): T
	local total = 0
	for _, item in list do
		total += weightOf(item)
	end
	local roll = random:NextNumber() * total
	for _, item in list do
		roll -= weightOf(item)
		if roll < 0 then
			return item
		end
	end
	return list[1]
end

-- A new mission. `durationId` forces the length (the board keeps one of each).
local function newMission(data: PlayerData, durationId: string?): Mission
	local exp = data.expeditions
	local duration = durationId
		or ExpeditionConfig.DURATION_ORDER[random:NextInteger(1, #ExpeditionConfig.DURATION_ORDER)]
	local allowed: { string } = {}
	for _, rewardId in ExpeditionConfig.REWARD_ORDER do
		if ExpeditionConfig.DURATIONS[duration].rewards[rewardId] ~= nil then
			table.insert(allowed, rewardId)
		end
	end
	local reward = weighted(allowed, function(rewardId: string): number
		return ExpeditionConfig.REWARDS[rewardId].weight
	end)
	local mission: Mission = {
		id = exp.nextId,
		duration = duration,
		reward = reward,
		house = GeneralConfig.HOUSE_ORDER[random:NextInteger(1, #GeneralConfig.HOUSE_ORDER)],
	}
	exp.nextId += 1
	return mission
end

-- A whole new board: one of each length, the rest random.
local function newBoard(data: PlayerData)
	local board: { Mission } = {}
	for i = 1, ExpeditionConfig.BOARD_SIZE do
		table.insert(board, newMission(data, ExpeditionConfig.DURATION_ORDER[i]))
	end
	data.expeditions.board = board
end

-- New day: new board. Returns true if anything changed.
local function ensureBoard(data: PlayerData): boolean
	local exp = data.expeditions
	local day = today()
	if exp.day ~= day then
		exp.day = day
		newBoard(data)
		return true
	end
	while #exp.board < ExpeditionConfig.BOARD_SIZE do
		table.insert(exp.board, newMission(data, nil))
	end
	return false
end

local function busyGenerals(data: PlayerData): { [string]: boolean }
	local busy: { [string]: boolean } = {}
	for _, run in data.expeditions.active do
		for _, generalId in run.generals do
			busy[generalId] = true
		end
	end
	return busy
end

local function send(player: Player, data: PlayerData, missionId: number, team: { string }): Result
	local exp = data.expeditions
	if #exp.active >= Formulas.expeditionSlots(data.bestStage) then
		return { ok = false, reason = "NoSlots" }
	end
	local index: number? = nil
	for i, mission in exp.board do
		if mission.id == missionId then
			index = i
		end
	end
	if index == nil then
		return { ok = false, reason = "NoMission" }
	end
	local busy = busyGenerals(data)
	if #team == 0 then
		for _, run in exp.active do
			if #run.generals == 0 then
				return { ok = false, reason = "ScoutsBusy" } -- one Scout Party at a time
			end
		end
	end
	local seen: { [string]: boolean } = {}
	for _, generalId in team do
		if data.generals.owned[generalId] == nil then
			return { ok = false, reason = "NotOwned" }
		elseif seen[generalId] then
			return { ok = false, reason = "Rejected" }
		elseif busy[generalId] then
			return { ok = false, reason = "Busy" }
		elseif table.find(data.generals.fielded, generalId) ~= nil then
			return { ok = false, reason = "Fielded" } -- fielded Generals are busy fighting
		end
		seen[generalId] = true
	end
	local mission = table.remove(exp.board, index :: number) :: Mission
	table.insert(exp.active, {
		mission = mission,
		generals = table.clone(team),
		power = Formulas.expeditionPower(data.generals, team, mission.house),
		endsAt = os.time() + ExpeditionConfig.DURATIONS[mission.duration].seconds,
	})
	table.insert(exp.board, index :: number, newMission(data, nil))
	DataService.markChanged(player)
	return { ok = true }
end

local function collect(player: Player, data: PlayerData, slot: number): Result
	local run = data.expeditions.active[slot]
	if run == nil then
		return { ok = false, reason = "NoMission" }
	end
	if os.time() < run.endsAt then
		return { ok = false, reason = "NotBack" }
	end
	table.remove(data.expeditions.active, slot)

	local mission = run.mission
	local bonus = weighted(ExpeditionConfig.BONUS, function(entry): number
		return entry.weight
	end)
	local scale = Formulas.expeditionScale(mission.duration, run.power)
	if bonus.id == "Bountiful" then
		scale *= ExpeditionConfig.BOUNTIFUL
	end
	local amount = Formulas.expeditionAmount(mission, scale)
	local loot: Types.ExpeditionLoot = { bonus = bonus.id }
	local reward: Types.RewardDef = {}
	if mission.reward == "Dust" then
		data.relics.dust += amount
		loot.dust = amount
	elseif mission.reward == "Gold" then
		reward.goldMinutes = amount
	elseif mission.reward == "Honor" then
		reward.honorShare = amount
		reward.honor = 1
	elseif mission.reward == "Scrolls" then
		reward.scrolls = amount
		loot.scrolls = amount
	elseif mission.reward == "HeroChest" then
		reward.heroChests = amount
		loot.heroChests = amount
	elseif mission.reward == "Relic" then
		local minRarity = ExpeditionConfig.DURATIONS[mission.duration].rewards.Relic
		RelicService.drop(player, data, minRarity)
		loot.relic = true
	end
	if bonus.id == "Scroll" then
		reward.scrolls = (reward.scrolls or 0) + 1
		loot.scrolls = (loot.scrolls or 0) + 1
	elseif bonus.id == "Relic" then
		RelicService.drop(player, data, "Epic")
		loot.relic = true
	end
	local goldBefore = data.gold
	local honor = DailyService.grant(player, data, reward, "Expedition")
	if not BigNum.isZero(honor) then
		loot.honor = BigNum.toNumber(honor)
	end
	if reward.goldMinutes ~= nil then
		local gained = BigNum.sub(data.gold, goldBefore)
		loot.gold = if BigNum.isZero(gained) then nil else gained -- held inside a challenge
	end
	ActivityService.record(player, "ExpeditionDone", 1)
	DataService.markChanged(player)
	return { ok = true, loot = loot }
end

local function reroll(player: Player, data: PlayerData): Result
	local exp = data.expeditions
	local day = today()
	if exp.rerollDay ~= day then
		exp.rerollDay = day
		exp.rerolls = 0
	end
	if exp.rerolls >= ExpeditionConfig.REROLLS_PER_DAY then
		return { ok = false, reason = "NoRerolls" }
	end
	exp.rerolls += 1
	newBoard(data)
	DataService.markChanged(player)
	return { ok = true }
end

type Request = { action: string, missionId: number?, team: { string }?, slot: number? }

local function validate(action: unknown, arg: unknown, extra: unknown): Request?
	if action == "Send" then
		if typeof(arg) ~= "number" or arg ~= math.floor(arg :: number) or typeof(extra) ~= "table" then
			return nil
		end
		local team: { string } = {}
		for key, generalId in extra :: { [any]: any } do
			if typeof(key) ~= "number" or typeof(generalId) ~= "string" or GeneralConfig.GENERALS[generalId] == nil then
				return nil
			end
			table.insert(team, generalId)
		end
		if #team > ExpeditionConfig.TEAM_SIZE then
			return nil
		end
		return { action = "Send", missionId = arg :: number, team = team }
	elseif action == "Collect" then
		if typeof(arg) ~= "number" or arg ~= math.floor(arg :: number) or (arg :: number) < 1 or (arg :: number) > 5 then
			return nil
		end
		return { action = "Collect", slot = arg :: number }
	elseif action == "Reroll" then
		return { action = "Reroll" }
	end
	return nil
end

local function handle(player: Player, request: Request): Result
	local data = DataService.get(player)
	if data == nil then
		return { ok = false, reason = "NotLoaded" }
	end
	if not unlocked(data) then
		return { ok = false, reason = "Locked" }
	end
	ensureBoard(data)
	if request.action == "Send" then
		return send(player, data, request.missionId :: number, request.team :: { string })
	elseif request.action == "Collect" then
		return collect(player, data, request.slot :: number)
	end
	return reroll(player, data)
end

---------------------------------------------------------------- Studio test panel

function ExpeditionService.debugFinishAll(player: Player)
	local data = DataService.get(player)
	if data ~= nil then
		for _, run in data.expeditions.active do
			run.endsAt = os.time()
		end
		DataService.markChanged(player)
	end
end

function ExpeditionService.debugNewBoard(player: Player)
	local data = DataService.get(player)
	if data ~= nil then
		data.expeditions.rerolls = 0
		newBoard(data)
		DataService.markChanged(player)
	end
end

function ExpeditionService.start()
	DataService.ProfileLoaded:Connect(function(_player: Player, data: PlayerData)
		if unlocked(data) then
			ensureBoard(data)
		end
	end)
	-- New board at the day change for players who stay online.
	task.spawn(function()
		while true do
			task.wait(15)
			for _, player in Players:GetPlayers() do
				local data = DataService.get(player)
				if data ~= nil and unlocked(data) and ensureBoard(data) then
					DataService.markChanged(player)
				end
			end
		end
	end)

	SyncService.addSnapshotFields(function(_player: Player, data: PlayerData): { [string]: any }
		return {
			expeditions = data.expeditions,
			expeditionSlots = Formulas.expeditionSlots(data.bestStage),
		}
	end)

	RemoteService.onInvoke(
		Remotes.Functions.ExpeditionRequest,
		RateLimiter.new(ExpeditionConfig.REQUESTS_BURST, ExpeditionConfig.REQUESTS_PER_SECOND),
		validate,
		handle,
		{ ok = false, reason = "Rejected" } :: Result
	)
end

return ExpeditionService
