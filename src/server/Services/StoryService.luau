--!strict
-- Story mode (StoryConfig): which scenes a player has watched, which chapters are cleared,
-- the permanent bonus and the one-time chapter rewards. The scenes themselves play on the
-- client (StoryController + CutsceneUI).
--
--   * StoryRequest("Begin", sceneId): the client is about to play a scene. The first time
--     for an unseen scene the fight is frozen (StageService.pause, capped at
--     MAX_PAUSE_SECONDS) so a cutscene never costs a boss. Replays don't freeze anything.
--   * StoryRequest("End", sceneId): unfreeze and remember the scene as watched.
--   * A chapter clears on the first win against its land's boss (stage 10, 20, ... 100):
--     +BONUS_PER_CHAPTER damage forever (ModifierService) and REWARD once (Notice
--     "StoryChapter").
--   * Existing players: on their first load with story mode, chapters they're already past
--     are cleared (bonus + rewards) and those scenes marked watched (Notice "StoryCaughtUp").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local StoryConfig = require(Shared:WaitForChild("Config"):WaitForChild("StoryConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)
local ModifierService = require(Services.ModifierService)
local StageService = require(Services.StageService)
local DailyService = require(Services.DailyService)

type PlayerData = Types.PlayerData
type Result = Types.StoryResult

local StoryService = {}

-- Scenes that already froze the fight this session (each may freeze once).
local froze: { [Player]: { [string]: boolean } } = {}
-- Chapters marked cleared on the first load, announced once the client is ready.
local caughtUp: { [Player]: number } = {}

local function notify(player: Player, notice: Types.Notice)
	RemoteService.fireClient(Remotes.Events.Notice, player, notice)
end

local function clearedCount(data: PlayerData): number
	local count = 0
	for _ in data.story.cleared do
		count += 1
	end
	return count
end

-- Marks a chapter cleared and pays its reward (once).
local function clear(player: Player, data: PlayerData, number: number): boolean
	local key = tostring(number)
	if data.story.cleared[key] then
		return false
	end
	data.story.cleared[key] = true
	DailyService.grant(player, data, StoryConfig.REWARD, "Story")
	data.relics.dust += StoryConfig.REWARD_DUST
	return true
end

-- First load with story mode: catch up on chapters the player is already past.
local function initialize(player: Player, data: PlayerData)
	if data.story.initialized then
		return
	end
	data.story.initialized = true
	local count = 0
	for _, chapter in StoryConfig.CHAPTERS do
		if data.bestStage > chapter.bossStage then
			if clear(player, data, chapter.number) then
				count += 1
			end
			for _, kind in { "Arrive", "Boss", "Outro" } do
				data.story.seen[`{kind}_{chapter.number}`] = true
			end
		end
	end
	if count > 0 then
		caughtUp[player] = count
	end
end

local function onBossDefeated(player: Player, bossStage: number)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	for _, chapter in StoryConfig.CHAPTERS do
		if chapter.bossStage == bossStage then
			if clear(player, data, chapter.number) then
				notify(player, { kind = "StoryChapter", stage = bossStage, chapter = chapter.number })
				DataService.markChanged(player)
			end
			return
		end
	end
end

local ACTIONS = { Begin = true, End = true }

type Request = { action: string, sceneId: string }

local function handle(player: Player, request: Request): Result
	local action, sceneId = request.action, request.sceneId
	local data = DataService.get(player)
	if data == nil then
		return { ok = false, reason = "NotLoaded" }
	end
	if action == "Begin" then
		local mine = froze[player]
		if mine == nil then
			mine = {}
			froze[player] = mine
		end
		if not data.story.seen[sceneId] and not mine[sceneId] then
			mine[sceneId] = true
			StageService.pause(player, StoryConfig.MAX_PAUSE_SECONDS)
		end
		return { ok = true }
	end
	-- End
	StageService.resume(player)
	if not data.story.seen[sceneId] then
		data.story.seen[sceneId] = true
		DataService.markChanged(player)
	end
	return { ok = true }
end

function StoryService.start()
	DataService.ProfileLoaded:Connect(function(player: Player, data: PlayerData)
		initialize(player, data)
	end)
	SyncService.ClientReady:Connect(function(player: Player)
		local count = caughtUp[player]
		if count ~= nil then
			caughtUp[player] = nil
			notify(player, { kind = "StoryCaughtUp", stage = 0, chapter = count })
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		froze[player] = nil
		caughtUp[player] = nil
	end)
	StageService.BossDefeated:Connect(function(player: Player, bossStage: number)
		onBossDefeated(player, bossStage)
	end)

	ModifierService.register(function(player: Player): ModifierService.PartialModifiers?
		local data = DataService.get(player)
		if data == nil then
			return nil
		end
		local count = clearedCount(data)
		if count == 0 then
			return nil
		end
		return { damage = 1 + count * StoryConfig.BONUS_PER_CHAPTER }
	end)

	SyncService.addSnapshotFields(function(_player: Player, data: PlayerData): { [string]: any }
		return {
			storySeen = data.story.seen,
			storyCleared = data.story.cleared,
		}
	end)

	RemoteService.onInvoke(
		Remotes.Functions.StoryRequest,
		RateLimiter.new(StoryConfig.REQUESTS_BURST, StoryConfig.REQUESTS_PER_SECOND),
		function(action: unknown, sceneId: unknown): Request?
			if typeof(action) ~= "string" or not ACTIONS[action :: string] then
				return nil
			end
			if typeof(sceneId) ~= "string" or StoryConfig.SCENES[sceneId :: string] == nil then
				return nil
			end
			return { action = action :: string, sceneId = sceneId :: string }
		end,
		handle,
		{ ok = false, reason = "Rejected" } :: Result
	)
end

return StoryService
