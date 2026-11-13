--!strict
-- Remembers which tutorial lessons a player has seen (TutorialConfig), so each pops up
-- once per account. The lessons themselves are shown by the client (TutorialUI).
--
-- First run on an older save: every lesson whose stage is below the player's best stage
-- counts as seen, so veterans aren't hit with 30 lessons at once (all are in the GUIDE).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local TutorialConfig = require(Shared:WaitForChild("Config"):WaitForChild("TutorialConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)

type PlayerData = Types.PlayerData

local TutorialService = {}

local function initialize(data: PlayerData)
	if data.tutorial.initialized then
		return
	end
	data.tutorial.initialized = true
	for _, lesson in TutorialConfig.LESSONS do
		if lesson.stage < data.bestStage then
			data.tutorial.seen[lesson.id] = true
		end
	end
end

function TutorialService.start()
	DataService.ProfileLoaded:Connect(function(_player: Player, data: PlayerData)
		initialize(data)
	end)
	SyncService.addSnapshotFields(function(_player: Player, data: PlayerData): { [string]: any }
		return { tutorialSeen = data.tutorial.seen }
	end)
	RemoteService.onEvent(Remotes.Events.TutorialSeen, RateLimiter.new(10, 2), function(lessonId: unknown): string?
		if typeof(lessonId) ~= "string" or TutorialConfig.BY_ID[lessonId :: string] == nil then
			return nil
		end
		return lessonId :: string
	end, function(player: Player, lessonId: string)
		local data = DataService.get(player)
		if data ~= nil and not data.tutorial.seen[lessonId] then
			data.tutorial.seen[lessonId] = true
			DataService.markChanged(player)
		end
	end)
end

return TutorialService
