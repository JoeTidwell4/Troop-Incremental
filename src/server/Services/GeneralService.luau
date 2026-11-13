--!strict
-- Generals (GeneralConfig, Phase 13c): recruiting with Recruit Scrolls, stars from
-- duplicates, leveling with gold, fielding 3. Everything is in the player's own
-- session-locked save; rolls happen here with odds + pity from the config.
--
-- Scrolls come from: Ascending (1 per PER_ASCEND_STAGES stages of the run), claiming
-- achievements, the daily all-quests bonus and login day 7 (DailyService.grant
-- `scrolls`), golden enemies (small chance), Legacy, and a one-time welcome gift when
-- Generals unlock.
--
-- Bonuses of the fielded Generals: global ones through a ModifierService source here;
-- per-troop ones through Formulas.fightDamageMultipliers / troopHpMultipliers
-- (CombatService.refreshArmy); crit chance, boss timer and golden chance are read where
-- those happen (CombatService, StageService) via Formulas.generalBonuses.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local GeneralConfig = require(Shared:WaitForChild("Config"):WaitForChild("GeneralConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)
local ModifierService = require(Services.ModifierService)
local CombatService = require(Services.CombatService)
local StageService = require(Services.StageService)
local ActivityService = require(Services.ActivityService)

type PlayerData = Types.PlayerData
type RecruitResult = Types.RecruitResult
type Result = { ok: boolean, reason: string?, levels: number? }

local random = Random.new()

local GeneralService = {}

local function addScrolls(player: Player, data: PlayerData, count: number)
	if count > 0 then
		data.generals.scrolls += count
		DataService.markChanged(player)
	end
end

-- Generals unlock: a few free scrolls, once.
local function welcome(player: Player, data: PlayerData)
	if not data.generals.welcomed and data.bestStage >= GeneralConfig.UNLOCK_STAGE then
		data.generals.welcomed = true
		addScrolls(player, data, GeneralConfig.SCROLLS.FIRST_SCROLLS)
	end
end

---------------------------------------------------------------- recruiting

local function rollRarity(data: PlayerData): string
	local pity = data.generals.pity
	pity.sinceLegendary += 1
	pity.sinceMythic += 1
	local total = 0
	for _, rarityId in GeneralConfig.RARITY_ORDER do
		total += GeneralConfig.RARITIES[rarityId].odds
	end
	local roll = random:NextNumber() * total
	local rarity = "Rare"
	for _, rarityId in GeneralConfig.RARITY_ORDER do
		roll -= GeneralConfig.RARITIES[rarityId].odds
		if roll < 0 then
			rarity = rarityId
			break
		end
	end
	local order = GeneralConfig.RARITIES[rarity].order
	if pity.sinceMythic >= GeneralConfig.PITY_MYTHIC then
		rarity = "Mythic"
	elseif pity.sinceLegendary >= GeneralConfig.PITY_LEGENDARY and order < GeneralConfig.RARITIES.Legendary.order then
		rarity = "Legendary"
	end
	order = GeneralConfig.RARITIES[rarity].order
	if order >= GeneralConfig.RARITIES.Legendary.order then
		pity.sinceLegendary = 0
	end
	if rarity == "Mythic" then
		pity.sinceMythic = 0
	end
	return rarity
end

local function pickOfRarity(rarity: string): string
	local pool: { string } = {}
	for _, generalId in GeneralConfig.ORDER do
		if GeneralConfig.GENERALS[generalId].rarity == rarity then
			table.insert(pool, generalId)
		end
	end
	return pool[random:NextInteger(1, #pool)]
end

-- Adds one copy of a General: new, a star, or shards once maxed.
local function addCopy(data: PlayerData, generalId: string): { id: string, isNew: boolean, stars: number, shards: number }
	local generals = data.generals
	local state = generals.owned[generalId]
	if state == nil then
		generals.owned[generalId] = { stars = 1, level = 1, copies = 0 }
		-- Fill an empty field slot right away so a new player sees it working.
		for slot, fieldedId in generals.fielded do
			if fieldedId == "" then
				generals.fielded[slot] = generalId
				break
			end
		end
		return { id = generalId, isNew = true, stars = 1, shards = 0 }
	end
	if state.stars >= GeneralConfig.MAX_STARS then
		generals.shards += GeneralConfig.SHARDS_PER_EXTRA
		local scrolls = generals.shards // GeneralConfig.SHARDS_PER_SCROLL
		generals.shards -= scrolls * GeneralConfig.SHARDS_PER_SCROLL
		generals.scrolls += scrolls
		return { id = generalId, isNew = false, stars = state.stars, shards = GeneralConfig.SHARDS_PER_EXTRA }
	end
	state.copies += 1
	local needed = GeneralConfig.STAR_COPIES[state.stars]
	if needed ~= nil and state.copies >= needed then
		state.copies -= needed
		state.stars += 1
	end
	return { id = generalId, isNew = false, stars = state.stars, shards = 0 }
end

local function recruit(player: Player, data: PlayerData, count: number): RecruitResult
	if data.bestStage < GeneralConfig.UNLOCK_STAGE then
		return { ok = false, reason = "Locked" }
	end
	if data.generals.scrolls < count then
		return { ok = false, reason = "NoScrolls" }
	end
	data.generals.scrolls -= count
	local results = {}
	for _ = 1, count do
		table.insert(results, addCopy(data, pickOfRarity(rollRarity(data))))
	end
	ActivityService.record(player, "Recruit", count)
	CombatService.refreshArmy(player) -- a new General may have gone straight into the field
	return { ok = true, results = results }
end

---------------------------------------------------------------- field + level

local function field(player: Player, data: PlayerData, slot: number, generalId: string): Result
	local generals = data.generals
	if generalId ~= "" and generals.owned[generalId] == nil then
		return { ok = false, reason = "NotOwned" }
	end
	local current = generals.fielded[slot]
	local other = if generalId ~= "" then table.find(generals.fielded, generalId) else nil
	if other ~= nil then
		generals.fielded[other] = current -- swap places
	end
	generals.fielded[slot] = generalId
	CombatService.refreshArmy(player)
	return { ok = true }
end

local function levelUp(player: Player, data: PlayerData, generalId: string, max: boolean): Result
	local state = data.generals.owned[generalId]
	if state == nil then
		return { ok = false, reason = "NotOwned" }
	end
	local levels = 0
	while levels < (if max then 100 else 1) do
		if state.level >= Formulas.generalMaxLevel(state.stars) then
			break
		end
		local cost = Formulas.generalLevelCost(generalId, state.level, data.bestStage)
		if BigNum.lt(data.gold, cost) then
			break
		end
		data.gold = BigNum.sub(data.gold, cost)
		state.level += 1
		levels += 1
	end
	if levels == 0 then
		return { ok = false, reason = if state.level >= Formulas.generalMaxLevel(state.stars) then "MaxLevel" else "CantAfford" }
	end
	if table.find(data.generals.fielded, generalId) ~= nil then
		CombatService.refreshArmy(player)
	end
	return { ok = true, levels = levels }
end

---------------------------------------------------------------- remote

type Request = { action: string, count: number?, slot: number?, generalId: string?, max: boolean? }

local function handle(player: Player, request: Request): any
	local data = DataService.get(player)
	if data == nil then
		return { ok = false, reason = "NotLoaded" }
	end
	local result: any
	if request.action == "Recruit" then
		result = recruit(player, data, request.count or 1)
	elseif request.action == "Field" then
		result = field(player, data, request.slot or 1, request.generalId or "")
	elseif request.action == "LevelUp" then
		result = levelUp(player, data, request.generalId or "", request.max == true)
	else
		result = { ok = false, reason = "Rejected" }
	end
	if result.ok then
		DataService.markChanged(player)
	end
	return result
end

local function validate(action: unknown, arg: unknown, extra: unknown): Request?
	if action == "Recruit" then
		if arg ~= 1 and arg ~= GeneralConfig.MAX_RECRUIT_AT_ONCE then
			return nil
		end
		return { action = "Recruit", count = arg :: number }
	elseif action == "Field" then
		if typeof(arg) ~= "number" or arg ~= math.floor(arg :: number) or (arg :: number) < 1 or (arg :: number) > GeneralConfig.FIELD_SLOTS then
			return nil
		end
		if extra ~= "" and (typeof(extra) ~= "string" or GeneralConfig.GENERALS[extra :: string] == nil) then
			return nil
		end
		return { action = "Field", slot = arg :: number, generalId = extra :: string }
	elseif action == "LevelUp" then
		if typeof(arg) ~= "string" or GeneralConfig.GENERALS[arg :: string] == nil then
			return nil
		end
		return { action = "LevelUp", generalId = arg :: string, max = extra == true }
	end
	return nil
end

function GeneralService.start()
	-- Scroll sources.
	ActivityService.Recorded:Connect(function(player: Player, activity: string, amount: number)
		local data = DataService.get(player)
		if data == nil then
			return
		end
		if activity == "AscendStage" then
			addScrolls(player, data, amount // GeneralConfig.SCROLLS.PER_ASCEND_STAGES)
		elseif activity == "AchievementClaim" then
			addScrolls(player, data, GeneralConfig.SCROLLS.ACHIEVEMENT * amount)
		elseif activity == "Legacy" then
			addScrolls(player, data, GeneralConfig.SCROLLS.LEGACY)
		end
	end)
	StageService.GoldenKilled:Connect(function(player: Player)
		local data = DataService.get(player)
		if data ~= nil and random:NextNumber() < GeneralConfig.SCROLLS.GOLDEN_CHANCE then
			addScrolls(player, data, 1)
		end
	end)
	StageService.BossDefeated:Connect(function(player: Player)
		local data = DataService.get(player)
		if data ~= nil then
			welcome(player, data)
		end
	end)
	DataService.ProfileLoaded:Connect(function(player: Player, data: PlayerData)
		welcome(player, data)
	end)

	-- Global bonuses of the fielded Generals (per-troop ones go through CombatService).
	ModifierService.register(function(player: Player): ModifierService.PartialModifiers?
		local data = DataService.get(player)
		if data == nil then
			return nil
		end
		local bonuses = Formulas.generalBonuses(data.generals)
		return {
			damage = bonuses.damage,
			armyHp = bonuses.armyHp,
			gold = bonuses.gold,
			tap = bonuses.tap,
			bossDamage = bonuses.bossDamage,
		}
	end)

	SyncService.addSnapshotFields(function(_player: Player, data: PlayerData): { [string]: any }
		return { generals = data.generals }
	end)

	RemoteService.onInvoke(
		Remotes.Functions.GeneralRequest,
		RateLimiter.new(GeneralConfig.REQUESTS_BURST, GeneralConfig.REQUESTS_PER_SECOND),
		validate,
		handle,
		{ ok = false, reason = "Rejected" }
	)

	-- Players who were already past the unlock stage before this update get the gift too.
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data ~= nil then
			welcome(player, data)
		end
	end
end

return GeneralService
