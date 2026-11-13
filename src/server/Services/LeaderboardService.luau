--!strict
-- Global leaderboards (Top Commanders) and the Roblox player list stats.
--
--   * Player list: a "leaderstats" folder on each player with Best (all-time best stage)
--     and Honor (lifetime Honor earned). Roblox shows these in the top-right list.
--   * Global: OrderedDataStores "TopBestStage" and "TopHonor", key = user id. Each player
--     only ever writes their own key, so servers never conflict. Changed scores are saved
--     every WRITE_INTERVAL and when the player leaves; the top lists are read every
--     READ_INTERVAL and sent to everyone on this server.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local LeaderboardConfig = require(Shared:WaitForChild("Config"):WaitForChild("LeaderboardConfig"))
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)

type PlayerData = Types.PlayerData
type LeaderboardEntry = Types.LeaderboardEntry

local stageStore = DataStoreService:GetOrderedDataStore("TopBestStage")
local honorStore = DataStoreService:GetOrderedDataStore("TopHonor")

type Saved = { stage: number, honor: number }

local lastSaved: { [Player]: Saved } = {}
local stats: { [Player]: { best: IntValue, honor: StringValue } } = {}
local boards: Types.Leaderboards = { bestStage = {}, honor = {} }
local nameCache: { [number]: string } = {}

local LeaderboardService = {}

local function honorScore(data: PlayerData): number
	return math.min(math.floor(BigNum.toNumber(data.stats.honorEarned)), LeaderboardConfig.MAX_STORED)
end

local function updateStats(player: Player, data: PlayerData)
	local entry = stats[player]
	if entry == nil then
		return
	end
	if entry.best.Value ~= data.bestStage then
		entry.best.Value = data.bestStage
	end
	local honorText = NumberFormat.big(data.stats.honorEarned)
	if entry.honor.Value ~= honorText then
		entry.honor.Value = honorText
	end
end

local function createStats(player: Player, data: PlayerData)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats" -- this exact name makes Roblox show it in the player list
	local best = Instance.new("IntValue")
	best.Name = "Best"
	best.Parent = folder
	local honor = Instance.new("StringValue")
	honor.Name = "Honor"
	honor.Parent = folder
	folder.Parent = player
	stats[player] = { best = best, honor = honor }
	updateStats(player, data)
end

local function save(player: Player, data: PlayerData)
	local current: Saved = { stage = data.bestStage, honor = honorScore(data) }
	local previous = lastSaved[player]
	if previous ~= nil and previous.stage == current.stage and previous.honor == current.honor then
		return
	end
	lastSaved[player] = current
	local key = tostring(player.UserId)
	local ok, err = pcall(function()
		stageStore:SetAsync(key, current.stage)
		honorStore:SetAsync(key, current.honor)
	end)
	if not ok then
		lastSaved[player] = previous -- try again next time
		warn(`[LeaderboardService] save failed: {err}`)
	end
end

local function getName(userId: number): string
	local cached = nameCache[userId]
	if cached ~= nil then
		return cached
	end
	local ok, name = pcall(function(): string
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok then name else `Player {userId}`
	nameCache[userId] = result
	return result
end

local function readTop(store: OrderedDataStore): { LeaderboardEntry }?
	local ok, page = pcall(function(): any
		return store:GetSortedAsync(false, LeaderboardConfig.TOP_COUNT):GetCurrentPage()
	end)
	if not ok or typeof(page) ~= "table" then
		return nil
	end
	local list: { LeaderboardEntry } = {}
	for _, entry in page do
		local userId = tonumber(entry.key)
		if userId ~= nil then
			table.insert(list, { name = getName(userId), value = tonumber(entry.value) or 0 })
		end
	end
	return list
end

local function refresh()
	local stage = readTop(stageStore)
	local honor = readTop(honorStore)
	boards = {
		bestStage = stage or boards.bestStage,
		honor = honor or boards.honor,
	}
	for _, player in Players:GetPlayers() do
		if SyncService.isReady(player) then
			RemoteService.fireClient(Remotes.Events.LeaderboardSync, player, boards)
		end
	end
end

local function every(seconds: number, job: () -> ())
	task.spawn(function()
		while true do
			task.wait(seconds)
			local ok, err = pcall(job)
			if not ok then
				warn(`[LeaderboardService] {err}`)
			end
		end
	end)
end

function LeaderboardService.start()
	DataService.ProfileLoaded:Connect(createStats)
	DataService.Changed:Connect(function(player: Player)
		local data = DataService.get(player)
		if data ~= nil then
			updateStats(player, data)
		end
	end)
	DataService.ProfileReleasing:Connect(function(player: Player)
		local data = DataService.get(player)
		if data ~= nil then
			save(player, data) -- reads data before yielding, so this is safe here
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		stats[player] = nil
		task.defer(function()
			lastSaved[player] = nil
		end)
	end)
	SyncService.ClientReady:Connect(function(player: Player)
		RemoteService.fireClient(Remotes.Events.LeaderboardSync, player, boards)
	end)

	every(LeaderboardConfig.WRITE_INTERVAL, function()
		for _, player in Players:GetPlayers() do
			local data = DataService.get(player)
			if data ~= nil then
				save(player, data)
			end
		end
	end)
	every(LeaderboardConfig.READ_INTERVAL, refresh)
	task.spawn(refresh)
end

return LeaderboardService
