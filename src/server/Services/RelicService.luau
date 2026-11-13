--!strict
-- Relics (RelicConfig, Phase 13d): boss drops with rolled stats, 6 slots, sets, Dust.
--
-- Drops: DROP_CHANCE per boss win and RAID_DROP_CHANCE per raid attack, from
-- UNLOCK_STAGE (all-time best). Rarity rolled with odds + pity (data.relics.pity); slot,
-- set and stat lines rolled too. Inventory past MAX_ITEMS: the drop becomes Dust.
--
-- The inventory is big, so it's NOT in the 4x-a-second snapshot: it goes out on its own
-- `RelicSync` remote whenever it changes (the snapshot only carries `relicDust`).
-- Everything lives in the player's session-locked save.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local RelicConfig = require(Shared:WaitForChild("Config"):WaitForChild("RelicConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)
local ModifierService = require(Services.ModifierService)
local StageService = require(Services.StageService)
local ActivityService = require(Services.ActivityService)

type PlayerData = Types.PlayerData
type RelicItem = Types.RelicItem
type Result = { ok: boolean, reason: string?, dust: number?, count: number? }

local random = Random.new()

local RelicService = {}

local dirty: { [Player]: boolean } = {}

local function changed(player: Player)
	dirty[player] = true
	DataService.markChanged(player)
end

local function count(data: PlayerData): number
	local n = 0
	for _ in data.relics.items do
		n += 1
	end
	return n
end

---------------------------------------------------------------- rolling

local function rollRarity(data: PlayerData): string
	local pity = data.relics.pity
	pity.sinceLegendary += 1
	pity.sinceMythic += 1
	local total = 0
	for _, rarityId in RelicConfig.RARITY_ORDER do
		total += RelicConfig.RARITIES[rarityId].odds
	end
	local roll = random:NextNumber() * total
	local rarity = "Common"
	for _, rarityId in RelicConfig.RARITY_ORDER do
		roll -= RelicConfig.RARITIES[rarityId].odds
		if roll < 0 then
			rarity = rarityId
			break
		end
	end
	local legendaryOrder = RelicConfig.RARITIES.Legendary.order
	if pity.sinceMythic >= RelicConfig.PITY_MYTHIC then
		rarity = "Mythic"
	elseif pity.sinceLegendary >= RelicConfig.PITY_LEGENDARY and RelicConfig.RARITIES[rarity].order < legendaryOrder then
		rarity = "Legendary"
	end
	if RelicConfig.RARITIES[rarity].order >= legendaryOrder then
		pity.sinceLegendary = 0
	end
	if rarity == "Mythic" then
		pity.sinceMythic = 0
	end
	return rarity
end

local function rollValue(rarity: string): number
	local range = RelicConfig.RARITIES[rarity].range
	return range[1] + random:NextNumber() * (range[2] - range[1])
end

-- A stat this relic doesn't have yet (or any, if it has them all).
local function freshStat(item: RelicItem, except: string?): string
	local pool: { string } = {}
	for _, stat in RelicConfig.STAT_ORDER do
		local taken = false
		for _, line in item.lines do
			if line.stat == stat and stat ~= except then
				taken = true
			end
		end
		if not taken and stat ~= except then
			table.insert(pool, stat)
		end
	end
	if #pool == 0 then
		return RelicConfig.STAT_ORDER[random:NextInteger(1, #RelicConfig.STAT_ORDER)]
	end
	return pool[random:NextInteger(1, #pool)]
end

local function rollRelic(data: PlayerData): RelicItem
	local rarity = rollRarity(data)
	local id = tostring(data.relics.nextId)
	data.relics.nextId += 1
	local item: RelicItem = {
		id = id,
		slot = RelicConfig.SLOTS[random:NextInteger(1, #RelicConfig.SLOTS)],
		set = RelicConfig.SET_ORDER[random:NextInteger(1, #RelicConfig.SET_ORDER)],
		rarity = rarity,
		level = 0,
		lines = {},
		locked = false,
	}
	for _ = 1, RelicConfig.RARITIES[rarity].lines do
		table.insert(item.lines, { stat = freshStat(item, nil), roll = rollValue(rarity) })
	end
	return item
end

-- Gives the player a new relic (or its Dust if the inventory is full) and tells them.
function RelicService.drop(player: Player, data: PlayerData)
	if data.bestStage < RelicConfig.UNLOCK_STAGE then
		return
	end
	local item = rollRelic(data)
	local dust: number? = nil
	if count(data) >= RelicConfig.MAX_ITEMS then
		dust = Formulas.relicSalvageDust(item)
		data.relics.dust += dust :: number
	else
		data.relics.items[item.id] = item
	end
	ActivityService.record(player, "RelicDrop", 1)
	RemoteService.fireClient(Remotes.Events.Notice, player, { kind = "Relic", stage = data.stage, relic = item, dust = dust })
	changed(player)
end

---------------------------------------------------------------- actions

local function salvage(data: PlayerData, item: RelicItem): number
	local dust = Formulas.relicSalvageDust(item)
	data.relics.dust += dust
	data.relics.items[item.id] = nil
	return dust
end

local function isEquipped(data: PlayerData, item: RelicItem): boolean
	return data.relics.equipped[item.slot] == item.id
end

local ACTIONS: { [string]: (player: Player, data: PlayerData, arg: any, extra: any) -> Result } = {
	Equip = function(_player, data, id)
		local item = data.relics.items[id]
		if item == nil then
			return { ok = false, reason = "NotFound" }
		end
		data.relics.equipped[item.slot] = item.id
		return { ok = true }
	end,
	Unequip = function(_player, data, slot)
		data.relics.equipped[slot] = nil
		return { ok = true }
	end,
	Upgrade = function(_player, data, id)
		local item = data.relics.items[id]
		if item == nil then
			return { ok = false, reason = "NotFound" }
		end
		if item.level >= RelicConfig.MAX_LEVEL then
			return { ok = false, reason = "MaxLevel" }
		end
		local cost = Formulas.relicUpgradeCost(item)
		if data.relics.dust < cost then
			return { ok = false, reason = "NoDust" }
		end
		data.relics.dust -= cost
		item.level += 1
		return { ok = true }
	end,
	Reroll = function(_player, data, id, lineIndex)
		local item = data.relics.items[id]
		local line = if item ~= nil then item.lines[lineIndex] else nil
		if item == nil or line == nil then
			return { ok = false, reason = "NotFound" }
		end
		local cost = Formulas.relicRerollCost(item)
		if data.relics.dust < cost then
			return { ok = false, reason = "NoDust" }
		end
		data.relics.dust -= cost
		-- A new stat (one the relic doesn't already have) and a new roll.
		item.lines[lineIndex] = { stat = freshStat(item, line.stat), roll = rollValue(item.rarity) }
		return { ok = true }
	end,
	Salvage = function(player, data, id)
		local item = data.relics.items[id]
		if item == nil then
			return { ok = false, reason = "NotFound" }
		end
		if item.locked or isEquipped(data, item) then
			return { ok = false, reason = "Protected" }
		end
		local dust = salvage(data, item)
		ActivityService.record(player, "RelicSalvage", 1)
		return { ok = true, dust = dust, count = 1 }
	end,
	SalvageBelow = function(player, data, order)
		local dust, n = 0, 0
		for _, item in table.clone(data.relics.items) do
			if not item.locked and not isEquipped(data, item) and RelicConfig.RARITIES[item.rarity].order <= order then
				dust += salvage(data, item)
				n += 1
			end
		end
		if n == 0 then
			return { ok = false, reason = "NothingToSalvage" }
		end
		ActivityService.record(player, "RelicSalvage", n)
		return { ok = true, dust = dust, count = n }
	end,
	Lock = function(_player, data, id)
		local item = data.relics.items[id]
		if item == nil then
			return { ok = false, reason = "NotFound" }
		end
		item.locked = not item.locked
		return { ok = true }
	end,
}

local function validate(action: unknown, arg: unknown, extra: unknown): { action: string, arg: any, extra: any }?
	if typeof(action) ~= "string" or ACTIONS[action :: string] == nil then
		return nil
	end
	if action == "Unequip" then
		if typeof(arg) ~= "string" or table.find(RelicConfig.SLOTS, arg :: string) == nil then
			return nil
		end
	elseif action == "SalvageBelow" then
		if typeof(arg) ~= "number" or arg ~= math.floor(arg :: number) or (arg :: number) < 1 or (arg :: number) > #RelicConfig.RARITY_ORDER then
			return nil
		end
	elseif typeof(arg) ~= "string" or #(arg :: string) > 12 then
		return nil
	end
	if action == "Reroll" and (typeof(extra) ~= "number" or extra ~= math.floor(extra :: number) or (extra :: number) < 1 or (extra :: number) > 4) then
		return nil
	end
	return { action = action :: string, arg = arg, extra = extra }
end

local function handle(player: Player, request: { action: string, arg: any, extra: any }): Result
	local data = DataService.get(player)
	if data == nil then
		return { ok = false, reason = "NotLoaded" }
	end
	local result = ACTIONS[request.action](player, data, request.arg, request.extra)
	if result.ok then
		changed(player)
	end
	return result
end

-- Legacy: every relic becomes Dust (the Dust is kept).
function RelicService.onLegacy(player: Player, data: PlayerData)
	for _, item in table.clone(data.relics.items) do
		salvage(data, item)
	end
	data.relics.equipped = {}
	changed(player)
end

function RelicService.push(player: Player)
	local data = DataService.get(player)
	if data ~= nil and SyncService.isReady(player) then
		RemoteService.fireClient(Remotes.Events.RelicSync, player, data.relics)
	end
end

function RelicService.start()
	-- Drops.
	StageService.BossDefeated:Connect(function(player: Player)
		local data = DataService.get(player)
		if data ~= nil and random:NextNumber() < RelicConfig.DROP_CHANCE then
			RelicService.drop(player, data)
		end
	end)
	StageService.RaidFinished:Connect(function(player: Player)
		local data = DataService.get(player)
		if data ~= nil and random:NextNumber() < RelicConfig.RAID_DROP_CHANCE then
			RelicService.drop(player, data)
		end
	end)
	ActivityService.Recorded:Connect(function(player: Player, activity: string)
		local data = DataService.get(player)
		if activity == "Legacy" and data ~= nil then
			RelicService.onLegacy(player, data)
		end
	end)

	-- Bonuses of the equipped relics (damage to bosses only in boss fights and raids).
	ModifierService.register(function(player: Player): ModifierService.PartialModifiers?
		local data = DataService.get(player)
		if data == nil then
			return nil
		end
		local bonuses = Formulas.relicBonuses(data.relics)
		local damage = bonuses.damage
		local encounter = StageService.getEncounter(player)
		if encounter ~= nil and encounter.kind ~= "Normal" then
			damage *= bonuses.bossDamageDealt
		end
		return { damage = damage, armyHp = bonuses.armyHp, gold = bonuses.gold, tap = bonuses.tap, bossDamage = bonuses.bossDamage }
	end)

	SyncService.addSnapshotFields(function(_player: Player, data: PlayerData): { [string]: any }
		return { relicDust = data.relics.dust }
	end)
	SyncService.ClientReady:Connect(function(player: Player)
		RelicService.push(player)
	end)
	-- Send the inventory when it changed (at most a few times a second).
	task.spawn(function()
		while true do
			task.wait(0.3)
			for player in dirty do
				dirty[player] = nil
				RelicService.push(player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		dirty[player] = nil
	end)

	RemoteService.onInvoke(
		Remotes.Functions.RelicRequest,
		RateLimiter.new(RelicConfig.REQUESTS_BURST, RelicConfig.REQUESTS_PER_SECOND),
		validate,
		handle,
		{ ok = false, reason = "Rejected" } :: Result
	)
end

return RelicService
