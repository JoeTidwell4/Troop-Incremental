--!strict
-- Loads and saves player data with ProfileStore.
--
-- Session locking: ProfileStore makes sure only ONE server has a player's data open at
-- a time, so joining a second server can't duplicate or roll back progress.
-- In Studio without "Enable Studio Access to API Services", ProfileStore uses a
-- temporary in-memory store and nothing is saved between test runs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local DataConfig = require(Server.Data.DataConfig)
local ProfileTemplate = require(Server.Data.ProfileTemplate)
-- ProfileStore is third-party and not written in strict mode, so we describe only the
-- parts we use and cast the module to that shape.
local ProfileStoreModule = require(Server.Packages.ProfileStore) :: any

type PlayerData = Types.PlayerData

type Profile = {
	Data: PlayerData,
	OnSessionEnd: { Connect: (self: any, listener: () -> ()) -> any },
	AddUserId: (self: Profile, userId: number) -> (),
	Reconcile: (self: Profile) -> (),
	EndSession: (self: Profile) -> (),
	IsActive: (self: Profile) -> boolean,
}

type Store = {
	StartSessionAsync: (self: Store, key: string, params: any) -> Profile?,
}

local store: Store = ProfileStoreModule.New(DataConfig.STORE_NAME, ProfileTemplate)
local profiles: { [Player]: Profile } = {}

local DataService = {
	-- Fired once a player's data is loaded and ready to use.
	ProfileLoaded = Signal.new() :: Signal.Signal<Player, PlayerData>,
	-- Fired right before a player's data is saved for the last time (they're leaving).
	ProfileReleasing = Signal.new() :: Signal.Signal<Player>,
	-- Fired whenever a service changes a player's state. SyncService listens to this.
	Changed = Signal.new() :: Signal.Signal<Player>,
}

-- Returns the player's live data table, or nil if it isn't loaded (yet or anymore).
-- Changes made to this table are saved automatically.
function DataService.get(player: Player): PlayerData?
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() then
		return nil
	end
	return profile.Data
end

function DataService.markChanged(player: Player)
	DataService.Changed:Fire(player)
end

local function wholeNumber(value: unknown, min: number, fallback: number): number
	if typeof(value) ~= "number" then
		return fallback
	end
	local n = value :: number
	if n ~= n or n == math.huge or n < min then
		return fallback
	end
	return math.floor(n)
end

-- Repairs anything malformed in saved data so a bad value can't crash the game.
local function sanitize(data: PlayerData)
	data.gold = BigNum.sanitize(data.gold)
	data.stage = wholeNumber(data.stage, 1, 1)
	data.highestStage = math.max(wholeNumber(data.highestStage, 1, 1), data.stage)
	data.killsInStage = wholeNumber(data.killsInStage, 0, 0)
	if typeof(data.autoAdvance) ~= "boolean" then
		data.autoAdvance = true
	end
	for troopId, count in data.troops do
		data.troops[troopId] = wholeNumber(count, 0, 0)
	end
	data.stats.totalKills = wholeNumber(data.stats.totalKills, 0, 0)
	data.stats.totalTaps = wholeNumber(data.stats.totalTaps, 0, 0)
	data.stats.lifetimeGold = BigNum.sanitize(data.stats.lifetimeGold)
	data.stats.bossesDefeated = wholeNumber(data.stats.bossesDefeated, 0, 0)
end

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync(DataConfig.KEY_PREFIX .. player.UserId, {
		-- Stop trying if the player leaves while we're still loading.
		Cancel = function(): boolean
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		-- Couldn't get the data (DataStore outage, or the player already left).
		if player.Parent == Players then
			player:Kick(DataConfig.KICK_MESSAGE_LOAD_FAILED)
		end
		return
	end

	profile:AddUserId(player.UserId) -- GDPR: lets Roblox data-deletion requests find this key
	profile:Reconcile() -- fills in any fields added to the template since they last played

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick(DataConfig.KICK_MESSAGE_SESSION_ENDED)
	end)

	if player.Parent ~= Players then
		-- They left while loading.
		profile:EndSession()
		return
	end

	sanitize(profile.Data)
	profiles[player] = profile
	DataService.ProfileLoaded:Fire(player, profile.Data)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile == nil then
		return
	end
	-- Listeners run immediately (before EndSession) so they can write final values.
	DataService.ProfileReleasing:Fire(player)
	profiles[player] = nil
	profile:EndSession()
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- Players who joined before this script started (common in Studio).
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DataService
