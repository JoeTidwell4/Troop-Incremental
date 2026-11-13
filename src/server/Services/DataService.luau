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
local GearConfig = require(Shared:WaitForChild("Config"):WaitForChild("GearConfig"))
local FactionConfig = require(Shared:WaitForChild("Config"):WaitForChild("FactionConfig"))
local DataConfig = require(Server.Data.DataConfig)
local ProfileTemplate = require(Server.Data.ProfileTemplate)
-- ProfileStore is third-party and not written in strict mode, so we describe only the
-- parts we use and cast the module to that shape.
local ProfileStoreModule = require(Server.Packages.ProfileStore) :: any

type PlayerData = Types.PlayerData

type Profile = {
	Data: PlayerData,
	LastSavedData: any,
	Save: (self: Profile) -> (),
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

-- Asks ProfileStore to save now, then waits until the saved copy passes `isSaved`.
-- Returns false on timeout or if the session ended. Used for Robux purchase receipts,
-- which must only be confirmed to Roblox once the grant is safely stored.
function DataService.saveAndWait(player: Player, isSaved: (savedData: any) -> boolean, timeout: number): boolean
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() then
		return false
	end
	profile:Save()
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if isSaved(profile.LastSavedData) then
			return true
		end
		if not profile:IsActive() then
			return false
		end
		task.wait(0.5)
	end
	return false
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
	-- bestStage was added in Phase 3; older saves start from their current highest stage.
	data.bestStage = math.max(wholeNumber(data.bestStage, 1, 1), data.highestStage)
	data.honor = BigNum.sanitize(data.honor)
	data.lastSeen = wholeNumber(data.lastSeen, 0, 0)
	if typeof(data.faction) ~= "string" or (data.faction ~= "" and FactionConfig.FACTIONS[data.faction] == nil) then
		data.faction = ""
	end
	data.factionChangedAt = wholeNumber(data.factionChangedAt, 0, 0)
	if typeof(data.clanId) ~= "string" then
		data.clanId = ""
	end
	data.clanDonation.dayId = wholeNumber(data.clanDonation.dayId, -1, -1)
	data.clanDonation.amount = wholeNumber(data.clanDonation.amount, 0, 0)
	-- Older saves had a single autoAbilities flag; carry an "off" setting over.
	local legacy = (data :: any).autoAbilities
	if legacy == false and data.passToggles.AutoAbilities == nil then
		data.passToggles.AutoAbilities = false
	end
	for key, value in data.passToggles do
		if typeof(value) ~= "boolean" then
			data.passToggles[key] = nil
		end
	end
	local cleanPurchases: { string } = {}
	for _, purchaseId in data.purchases do
		if typeof(purchaseId) == "string" then
			table.insert(cleanPurchases, purchaseId)
		end
	end
	data.purchases = cleanPurchases
	data.raid.weekId = wholeNumber(data.raid.weekId, -1, -1)
	data.raid.attacks = wholeNumber(data.raid.attacks, 0, 0)
	data.raid.units = wholeNumber(data.raid.units, 0, 0)
	data.raid.dayId = wholeNumber(data.raid.dayId, -1, -1)
	data.raid.attacksToday = wholeNumber(data.raid.attacksToday, 0, 0)
	data.raid.claimedWeek = wholeNumber(data.raid.claimedWeek, -1, -1)
	if typeof(data.raid.clanId) ~= "string" then
		data.raid.clanId = ""
	end
	for _, record in { data.war, data.lastWar } do
		record.weekId = wholeNumber(record.weekId, -1, -1)
		record.points = wholeNumber(record.points, 0, 0)
		record.dayId = wholeNumber(record.dayId, -1, -1)
		record.dayPoints = wholeNumber(record.dayPoints, 0, 0)
		if typeof(record.faction) ~= "string" then
			record.faction = ""
		end
		if typeof(record.active) ~= "boolean" then
			record.active = false
		end
	end
	for upgradeId, level in data.abilityUpgrades do
		data.abilityUpgrades[upgradeId] = wholeNumber(level, 0, 0)
	end
	for upgradeId, level in data.honorUpgrades do
		data.honorUpgrades[upgradeId] = wholeNumber(level, 0, 0)
	end
	data.killsInStage = wholeNumber(data.killsInStage, 0, 0)
	if typeof(data.autoAdvance) ~= "boolean" then
		data.autoAdvance = true
	end
	data.highestBossDefeated = wholeNumber(data.highestBossDefeated, 0, 0)
	for troopId, count in data.troops do
		data.troops[troopId] = wholeNumber(count, 0, 0)
	end
	data.stats.totalKills = wholeNumber(data.stats.totalKills, 0, 0)
	data.stats.totalTaps = wholeNumber(data.stats.totalTaps, 0, 0)
	data.stats.lifetimeGold = BigNum.sanitize(data.stats.lifetimeGold)
	data.stats.bossesDefeated = wholeNumber(data.stats.bossesDefeated, 0, 0)
	data.stats.ascensions = wholeNumber(data.stats.ascensions, 0, 0)
	data.stats.honorEarned = BigNum.sanitize(data.stats.honorEarned)

	for _, troopGear in data.gear do
		local slots = troopGear :: any
		for _, slot in GearConfig.SLOTS do
			local state = slots[slot]
			if typeof(state) ~= "table" then
				slots[slot] = { level = 0, rarity = 1 }
			else
				state.level = math.min(wholeNumber(state.level, 0, 0), GearConfig.MAX_LEVEL)
				state.rarity = math.clamp(wholeNumber(state.rarity, 1, 1), 1, #GearConfig.RARITIES)
			end
		end
	end
	data.packs.free = wholeNumber(data.packs.free, 0, 0)
	data.packs.hero = wholeNumber(data.packs.hero, 0, 0)
	data.daily.lastClaimDay = wholeNumber(data.daily.lastClaimDay, -1, -1)
	data.daily.streak = math.clamp(wholeNumber(data.daily.streak, 0, 0), 0, 7)
	data.quests.day = wholeNumber(data.quests.day, -1, -1)
	data.quests.rerollsUsed = wholeNumber(data.quests.rerollsUsed, 0, 0)
	if typeof(data.quests.bonusClaimed) ~= "boolean" then
		data.quests.bonusClaimed = false
	end
	local cleanQuests: { Types.QuestState } = {}
	for _, quest in data.quests.list do
		if typeof(quest) == "table" and typeof(quest.key) == "string" then
			table.insert(cleanQuests, {
				key = quest.key,
				difficulty = math.clamp(wholeNumber(quest.difficulty, 1, 1), 1, 3),
				target = wholeNumber(quest.target, 1, 1),
				progress = wholeNumber(quest.progress, 0, 0),
				claimed = quest.claimed == true,
			})
		end
	end
	data.quests.list = cleanQuests
	for id, status in data.achievements do
		if status ~= "unlocked" and status ~= "claimed" then
			data.achievements[id] = nil
		end
	end
	for key, value in data.lifetime do
		data.lifetime[key] = wholeNumber(value, 0, 0)
	end
	data.packs.forge = wholeNumber(data.packs.forge, 0, 0)
	data.analytics.onboardingStep = wholeNumber(data.analytics.onboardingStep, 0, 0)
	data.packs.sinceEpic = wholeNumber(data.packs.sinceEpic, 0, 0)
	data.packs.opened = wholeNumber(data.packs.opened, 0, 0)
	data.packs.rewardedBossStage = wholeNumber(data.packs.rewardedBossStage, 0, 0)
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
