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
local StoreNames = require(script.Parent.Parent.Util.StoreNames)
local Types = require(Shared:WaitForChild("Types"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local GearConfig = require(Shared:WaitForChild("Config"):WaitForChild("GearConfig"))
local FactionConfig = require(Shared:WaitForChild("Config"):WaitForChild("FactionConfig"))
local DailyConfig = require(Shared:WaitForChild("Config"):WaitForChild("DailyConfig"))
local AbilityConfig = require(Shared:WaitForChild("Config"):WaitForChild("AbilityConfig"))
local SkillConfig = require(Shared:WaitForChild("Config"):WaitForChild("SkillConfig"))
local GeneralConfig = require(Shared:WaitForChild("Config"):WaitForChild("GeneralConfig"))
local RelicConfig = require(Shared:WaitForChild("Config"):WaitForChild("RelicConfig"))
local TutorialConfig = require(Shared:WaitForChild("Config"):WaitForChild("TutorialConfig"))
local ChallengeConfig = require(Shared:WaitForChild("Config"):WaitForChild("ChallengeConfig"))
local ExpeditionConfig = require(Shared:WaitForChild("Config"):WaitForChild("ExpeditionConfig"))
local GeneralConfig = require(Shared:WaitForChild("Config"):WaitForChild("GeneralConfig"))
local Formulas = require(Shared:WaitForChild("Formulas"))
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

local store: Store = ProfileStoreModule.New(StoreNames.of(DataConfig.STORE_NAME), ProfileTemplate)
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
	if typeof(data.clanRequest.clanId) ~= "string" then
		data.clanRequest.clanId = ""
	end
	data.clanRequest.at = wholeNumber(data.clanRequest.at, 0, 0)
	data.clanTokens = wholeNumber(data.clanTokens, 0, 0)
	-- Commander Level + skills: known nodes only, ranks within the max, and never more
	-- points spent than the level gives (if so, the tree is reset rather than guessed at).
	data.commanderXp = math.max(0, if typeof(data.commanderXp) == "number" and data.commanderXp == data.commanderXp then data.commanderXp else 0)
	data.skills.respecDay = wholeNumber(data.skills.respecDay, -1, -1)
	local ranks: { [string]: number } = {}
	if typeof(data.skills.ranks) == "table" then
		for nodeId, rank in data.skills.ranks do
			local node = SkillConfig.NODES[nodeId]
			if node ~= nil then
				local clean = math.min(wholeNumber(rank, 0, 0), node.maxRank)
				if clean > 0 then
					ranks[nodeId] = clean
				end
			end
		end
	end
	local level = Formulas.commanderLevel(data.commanderXp)
	if Formulas.skillSpent(ranks) > Formulas.skillPoints(level) then
		ranks = {}
	end
	data.skills.ranks = ranks
	-- Generals: known ids, stars/level in range, fielded = FIELD_SLOTS owned-or-empty, no repeats.
	local generals = data.generals
	local owned: { [string]: Types.GeneralState } = {}
	if typeof(generals.owned) == "table" then
		for generalId, state in generals.owned do
			if GeneralConfig.GENERALS[generalId] ~= nil and typeof(state) == "table" then
				local stars = math.clamp(wholeNumber(state.stars, 1, 1), 1, GeneralConfig.MAX_STARS)
				owned[generalId] = {
					stars = stars,
					level = math.clamp(wholeNumber(state.level, 1, 1), 1, Formulas.generalMaxLevel(stars)),
					copies = wholeNumber(state.copies, 0, 0),
				}
			end
		end
	end
	generals.owned = owned
	local fielded: { string } = {}
	for slot = 1, GeneralConfig.FIELD_SLOTS do
		local generalId = if typeof(generals.fielded) == "table" then generals.fielded[slot] else nil
		local valid = typeof(generalId) == "string" and owned[generalId] ~= nil and table.find(fielded, generalId) == nil
		fielded[slot] = if valid then generalId :: string else ""
	end
	generals.fielded = fielded
	generals.scrolls = wholeNumber(generals.scrolls, 0, 0)
	generals.shards = wholeNumber(generals.shards, 0, 0)
	generals.pity.sinceLegendary = wholeNumber(generals.pity.sinceLegendary, 0, 0)
	generals.pity.sinceMythic = wholeNumber(generals.pity.sinceMythic, 0, 0)
	if typeof(generals.welcomed) ~= "boolean" then
		generals.welcomed = false
	end
	-- Relics: known slot / set / rarity / stats only; equipped must point at a relic of
	-- that slot; nextId above every id in use.
	local relics = data.relics
	local items: { [string]: Types.RelicItem } = {}
	local highestId = 0
	if typeof(relics.items) == "table" then
		for id, item in relics.items do
			if typeof(id) == "string" and typeof(item) == "table" and table.find(RelicConfig.SLOTS, item.slot) ~= nil
				and RelicConfig.SETS[item.set] ~= nil and RelicConfig.RARITIES[item.rarity] ~= nil and typeof(item.lines) == "table"
			then
				local lines: { Types.RelicLine } = {}
				for _, line in item.lines do
					if typeof(line) == "table" and RelicConfig.STATS[line.stat] ~= nil and typeof(line.roll) == "number" and line.roll == line.roll and #lines < 4 then
						table.insert(lines, { stat = line.stat, roll = math.clamp(line.roll, 0, 3) })
					end
				end
				items[id] = {
					id = id,
					slot = item.slot,
					set = item.set,
					rarity = item.rarity,
					level = math.clamp(wholeNumber(item.level, 0, 0), 0, RelicConfig.MAX_LEVEL),
					lines = lines,
					locked = item.locked == true,
				}
				highestId = math.max(highestId, tonumber(id) or 0)
			end
		end
	end
	relics.items = items
	local equipped: { [string]: string } = {}
	if typeof(relics.equipped) == "table" then
		for _, slot in RelicConfig.SLOTS do
			local id = relics.equipped[slot]
			if typeof(id) == "string" and items[id] ~= nil and items[id].slot == slot then
				equipped[slot] = id
			end
		end
	end
	relics.equipped = equipped
	relics.dust = wholeNumber(relics.dust, 0, 0)
	relics.nextId = math.max(wholeNumber(relics.nextId, 1, 1), highestId + 1)
	relics.pity.sinceLegendary = wholeNumber(relics.pity.sinceLegendary, 0, 0)
	relics.pity.sinceMythic = wholeNumber(relics.pity.sinceMythic, 0, 0)
	-- Tutorial: only real lesson ids.
	local seenLessons: { [string]: boolean } = {}
	if typeof(data.tutorial.seen) == "table" then
		for lessonId, value in data.tutorial.seen do
			if typeof(lessonId) == "string" and value == true and TutorialConfig.BY_ID[lessonId] ~= nil then
				seenLessons[lessonId] = true
			end
		end
	end
	data.tutorial.seen = seenLessons
	if typeof(data.tutorial.initialized) ~= "boolean" then
		data.tutorial.initialized = false
	end
	do
		-- Expeditions: only well-formed missions; a General can be on one team at most and
		-- must still be owned (else the team is just smaller). Generals on a team can't
		-- also be fielded: they come off the field.
		local exp = data.expeditions
		exp.day = wholeNumber(exp.day, -1, -1)
		exp.rerollDay = wholeNumber(exp.rerollDay, -1, -1)
		exp.rerolls = wholeNumber(exp.rerolls, 0, 0)
		exp.nextId = wholeNumber(exp.nextId, 1, 1)
		local function goodMission(m: any): boolean
			return typeof(m) == "table" and typeof(m.id) == "number"
				and ExpeditionConfig.DURATIONS[m.duration] ~= nil
				and ExpeditionConfig.REWARDS[m.reward] ~= nil
				and ExpeditionConfig.DURATIONS[m.duration].rewards[m.reward] ~= nil
				and GeneralConfig.HOUSES[m.house] ~= nil
		end
		local board = {}
		if typeof(exp.board) == "table" then
			for _, m in exp.board do
				if goodMission(m) and #board < ExpeditionConfig.BOARD_SIZE then
					table.insert(board, m)
				end
			end
		end
		exp.board = board
		local active = {}
		local busy: { [string]: boolean } = {}
		if typeof(exp.active) == "table" then
			for _, run in exp.active :: any do
				if typeof(run) == "table" and goodMission(run.mission) and typeof(run.generals) == "table"
					and #active < ExpeditionConfig.SLOTS + 1 then
					local team = {}
					for _, generalId in run.generals do
						if typeof(generalId) == "string" and data.generals.owned[generalId] ~= nil and not busy[generalId]
							and #team < ExpeditionConfig.TEAM_SIZE then
							busy[generalId] = true
							table.insert(team, generalId)
						end
					end
					table.insert(active, {
						mission = run.mission,
						generals = team,
						power = if typeof(run.power) == "number" and run.power == run.power then math.max(0, run.power) else ExpeditionConfig.SCOUT_POWER,
						endsAt = wholeNumber(run.endsAt, 0, 0),
					})
				end
			end
		end
		exp.active = active
		for slot, generalId in data.generals.fielded do
			if busy[generalId] then
				data.generals.fielded[slot] = ""
			end
		end
	end
	data.tower.best = wholeNumber(data.tower.best, 0, 0)
	data.tower.tributeDay = wholeNumber(data.tower.tributeDay, -1, -1)
	do
		-- Challenge runs: known challenges only, tiers within the ladder, and a parked main
		-- run that is complete. If the parked run is damaged the challenge is dropped and the
		-- challenge run simply becomes the main run (nothing better can be rebuilt).
		local challenge = data.challenge
		local tiers: { [string]: number } = {}
		if typeof(challenge.tiers) == "table" then
			for challengeId, tier in challenge.tiers do
				if typeof(challengeId) == "string" and ChallengeConfig.CHALLENGES[challengeId] ~= nil then
					tiers[challengeId] = math.min(wholeNumber(tier, 0, 0), #ChallengeConfig.TIER_GOALS)
				end
			end
		end
		challenge.tiers = tiers
		challenge.goldMinutes = wholeNumber(challenge.goldMinutes, 0, 0)
		local stash = challenge.stash :: any
		local stashOk = typeof(stash) == "table" and typeof(stash.troops) == "table" and typeof(stash.gear) == "table"
		if typeof(challenge.active) ~= "string" or ChallengeConfig.CHALLENGES[challenge.active] == nil or not stashOk then
			challenge.active = ""
			challenge.stash = nil
		else
			stash.gold = BigNum.sanitize(stash.gold)
			stash.stage = wholeNumber(stash.stage, 1, 1)
			stash.highestStage = math.max(wholeNumber(stash.highestStage, 1, 1), stash.stage)
			stash.killsInStage = wholeNumber(stash.killsInStage, 0, 0)
			if typeof(stash.autoAdvance) ~= "boolean" then
				stash.autoAdvance = true
			end
			stash.highestBossDefeated = wholeNumber(stash.highestBossDefeated, 0, 0)
			stash.rewardedBossStage = wholeNumber(stash.rewardedBossStage, 0, 0)
			stash.weakenStage = wholeNumber(stash.weakenStage, 0, 0)
			stash.weakenFails = wholeNumber(stash.weakenFails, 0, 0)
			for troopId in data.troops do
				stash.troops[troopId] = wholeNumber(stash.troops[troopId], 0, 0)
				local troopGear = stash.gear[troopId]
				if typeof(troopGear) ~= "table" then
					troopGear = {}
					stash.gear[troopId] = troopGear
				end
				for _, slot in GearConfig.SLOTS do
					local state = troopGear[slot]
					if typeof(state) ~= "table" then
						troopGear[slot] = { level = 0, rarity = 1 }
					else
						state.level = math.min(wholeNumber(state.level, 0, 0), GearConfig.MAX_LEVEL)
						state.rarity = math.clamp(wholeNumber(state.rarity, 1, 1), 1, #GearConfig.RARITIES)
					end
				end
			end
			-- The parked run's best counts as the all-time best too.
			data.bestStage = math.max(data.bestStage, stash.highestStage)
		end
	end
	-- Ability loadout: exactly as many known, different abilities as there are slots.
	local loadout: { string } = {}
	local seen: { [string]: boolean } = {}
	if typeof(data.abilityLoadout) == "table" then
		for _, abilityId in data.abilityLoadout do
			if typeof(abilityId) == "string" and AbilityConfig.ABILITIES[abilityId] ~= nil and not seen[abilityId] then
				seen[abilityId] = true
				table.insert(loadout, abilityId)
			end
		end
	end
	local slots = Formulas.loadoutSlots(data.skills.ranks)
	local fill = table.clone(AbilityConfig.DEFAULT_LOADOUT)
	for _, abilityId in AbilityConfig.ORDER do
		table.insert(fill, abilityId)
	end
	for _, abilityId in fill do
		if #loadout >= slots then
			break
		end
		if not seen[abilityId] then
			seen[abilityId] = true
			table.insert(loadout, abilityId)
		end
	end
	while #loadout > slots do
		table.remove(loadout)
	end
	data.abilityLoadout = loadout
	local legacy = data.legacy
	legacy.count = wholeNumber(legacy.count, 0, 0)
	legacy.crowns = wholeNumber(legacy.crowns, 0, 0)
	legacy.crownsEarned = wholeNumber(legacy.crownsEarned, 0, 0)
	legacy.honorAtStart = BigNum.sanitize(legacy.honorAtStart)
	for upgradeId, level in legacy.upgrades do
		legacy.upgrades[upgradeId] = wholeNumber(level, 0, 0)
	end
	-- Before any Legacy, everything played so far counts as the first one.
	legacy.best = wholeNumber(legacy.best, 1, 1)
	if legacy.count == 0 then
		legacy.best = math.max(legacy.best, data.bestStage)
	end
	legacy.best = math.max(legacy.best, data.highestStage)
	data.clanQuestClaims.weekId = wholeNumber(data.clanQuestClaims.weekId, -1, -1)
	data.bossWeaken.stage = wholeNumber(data.bossWeaken.stage, 0, 0)
	data.bossWeaken.fails = wholeNumber(data.bossWeaken.fails, 0, 0)
	for _, field in { "weekId", "dayId", "lastWeekId", "claimedWeek" } do
		(data.clanWar :: any)[field] = wholeNumber((data.clanWar :: any)[field], -1, -1)
	end
	for _, field in { "xp", "dayXp", "lastXp" } do
		(data.clanWar :: any)[field] = wholeNumber((data.clanWar :: any)[field], 0, 0)
	end
	for _, field in { "clanId", "lastClanId" } do
		if typeof((data.clanWar :: any)[field]) ~= "string" then
			(data.clanWar :: any)[field] = ""
		end
	end
	data.analytics.onboardingStep = wholeNumber(data.analytics.onboardingStep, 0, 0)
	data.packs.sinceEpic = wholeNumber(data.packs.sinceEpic, 0, 0)
	data.packs.opened = wholeNumber(data.packs.opened, 0, 0)
	data.packs.rewardedBossStage = wholeNumber(data.packs.rewardedBossStage, 0, 0)
end

-- Day and week numbers saved in the "future" can only come from Studio's test mode
-- (3-minute days, 10-minute weeks give much bigger numbers) back when Studio shared the
-- live saves. Left alone they block live rewards for months (e.g. "already claimed week
-- 2,900,000"), so they're reset. Also guards against any other bad clock value.
local function repairFutureIds(data: PlayerData)
	local now = os.time()
	local day = now // DailyConfig.DAY_SECONDS
	if data.daily.lastClaimDay > day then
		data.daily.lastClaimDay = -1
		data.daily.streak = 0
	end
	if data.quests.day > day then
		data.quests.day = -1 -- new quests get rolled for today
	end
	if data.expeditions.day > day then
		data.expeditions.day = -1
	end
	if data.expeditions.rerollDay > day then
		data.expeditions.rerollDay = -1
	end
	if data.tower.tributeDay > day then
		data.tower.tributeDay = -1
	end
	if data.skills.respecDay > day then
		data.skills.respecDay = -1
	end

	local raidWeek, raidDay = Formulas.raidWeek(now), Formulas.raidDay(now)
	if data.raid.weekId > raidWeek then
		data.raid.weekId = -1
		data.raid.attacks = 0
		data.raid.units = 0
		data.raid.clanId = ""
	end
	if data.raid.claimedWeek > raidWeek then
		data.raid.claimedWeek = -1
	end
	if data.raid.dayId > raidDay then
		data.raid.dayId = -1
		data.raid.attacksToday = 0
	end

	local warWeek, warDay = Formulas.warWeek(now), Formulas.warDay(now)
	for _, record in { data.war, data.lastWar } do
		if record.weekId > warWeek then
			record.weekId = -1
			record.points = 0
			record.active = false
		end
		if record.dayId > warDay then
			record.dayId = -1
			record.dayPoints = 0
		end
	end

	local clanWeek, clanDay = Formulas.clanWarWeek(now), Formulas.clanDay(now)
	local clanWar = data.clanWar
	if clanWar.weekId > clanWeek then
		clanWar.weekId = -1
		clanWar.xp = 0
	end
	if clanWar.lastWeekId > clanWeek then
		clanWar.lastWeekId = -1
		clanWar.lastXp = 0
	end
	if clanWar.claimedWeek > clanWeek then
		clanWar.claimedWeek = -1
	end
	if clanWar.dayId > clanDay then
		clanWar.dayId = -1
		clanWar.dayXp = 0
	end
	if data.clanQuestClaims.weekId > clanWeek then
		data.clanQuestClaims.weekId = -1
		data.clanQuestClaims.claimed = {}
	end
	if data.clanDonation.dayId > clanDay then
		data.clanDonation.dayId = -1
		data.clanDonation.amount = 0
	end
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
	repairFutureIds(profile.Data)
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

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = deepCopy(inner)
	end
	return copy
end

-- Studio test panel only: resets this player's save to a brand-new one. The caller
-- kicks the player afterwards so everything restarts cleanly from the fresh save.
function DataService.debugWipe(player: Player)
	local profile = profiles[player]
	if profile == nil or not StoreNames.isStudio() then
		return
	end
	local data = profile.Data :: any
	for key in data do
		data[key] = nil
	end
	for key, value in ProfileTemplate :: any do
		data[key] = deepCopy(value)
	end
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
