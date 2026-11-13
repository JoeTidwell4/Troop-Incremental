--!strict
-- Commander gear (CommanderConfig): what your avatar wears and the small bonuses it gives.
-- Items are unlocked by playing (best stage, Ascends, login streak; Clan War and the clan
-- shop grant theirs through CommanderService.grant). Robux pass items are looks-only
-- and owned while you own the pass. The equipped items' bonuses go into ModifierService.
-- Everything here is kept on Ascend.
--
-- Wardrobe Chests (CommanderConfig.CHESTS): gold only, priced at your all-time best stage,
-- rolled here with Random.new(). Pity per chest kind in data.commander.pity.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local CommanderConfig = require(Shared:WaitForChild("Config"):WaitForChild("CommanderConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local Validate = require(Server.Util.Validate)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)
local ModifierService = require(Services.ModifierService)
local MonetizationService = require(Services.MonetizationService)
local ActivityService = require(Services.ActivityService)

type PlayerData = Types.PlayerData
type ItemDef = Types.CommanderItemDef
type EquipRequest = { slot: string, itemId: string }
type ChestResult = Types.ChestResult

local LEGENDARY = 5
local REJECTED: ChestResult = { ok = false, reason = "Rejected" }
local rng = Random.new()

local dirty: { [Player]: boolean } = {}

local CommanderService = {}

local function isOwned(player: Player, data: PlayerData, def: ItemDef): boolean
	local unlock = def.unlock
	if unlock.kind == "default" then
		return true
	elseif unlock.kind == "pass" then
		return unlock.pass ~= nil and MonetizationService.owns(player, unlock.pass)
	end
	return data.commander.owned[def.id] == true
end

-- Adds an item to the save; wears it if that slot is empty.
local function addItem(data: PlayerData, def: ItemDef)
	data.commander.owned[def.id] = true
	if (data.commander.equipped[def.slot] or "") == "" then
		data.commander.equipped[def.slot] = def.id
	end
end

-- Gives an item (no-op if already owned) and tells the player.
function CommanderService.grant(player: Player, itemId: string)
	local data = DataService.get(player)
	local def = CommanderConfig.ITEMS[itemId]
	if data == nil or def == nil or data.commander.owned[itemId] then
		return
	end
	addItem(data, def) -- also wears it if that slot is empty
	DataService.markChanged(player)
	RemoteService.fireClient(Remotes.Events.Notice, player, { kind = "CommanderItem", stage = 0, itemName = def.displayName })
end

local function rollChestRarity(forceLegendary: boolean): number
	if forceLegendary then
		return LEGENDARY
	end
	local total = 0
	for _, entry in CommanderConfig.CHEST_ODDS do
		total += entry.chance
	end
	local roll = rng:NextNumber() * total
	for _, entry in CommanderConfig.CHEST_ODDS do
		roll -= entry.chance
		if roll < 0 then
			return entry.rarity
		end
	end
	return LEGENDARY
end

local function openChest(player: Player, chestId: string): ChestResult
	local data = DataService.get(player)
	if data == nil then
		return { ok = false, reason = "NotLoaded" }
	end
	if data.bestStage < CommanderConfig.CHEST_UNLOCK_STAGE then
		return { ok = false, reason = "TooEarly" }
	end
	local price = Formulas.wardrobeChestPrice(data.bestStage)
	if BigNum.lt(data.gold, price) then
		return { ok = false, reason = "CantAfford" }
	end
	data.gold = BigNum.sub(data.gold, price)

	local sinceLegendary = (data.commander.pity[chestId] or 0) + 1
	local rarity = rollChestRarity(sinceLegendary >= CommanderConfig.CHEST_PITY_EVERY)
	data.commander.pity[chestId] = if rarity >= LEGENDARY then 0 else sinceLegendary

	local options: { ItemDef } = {}
	for _, def in CommanderConfig.ITEMS do
		if def.unlock.kind == "chest" and def.unlock.chest == chestId and def.rarity == rarity then
			table.insert(options, def)
		end
	end
	local def = options[rng:NextInteger(1, math.max(1, #options))]
	ActivityService.record(player, "PackOpen", 1)
	if def == nil then
		-- Misconfigured chest: give the gold back rather than eat it.
		data.gold = BigNum.add(data.gold, price)
		DataService.markChanged(player)
		return { ok = false, reason = "Rejected" }
	end
	if data.commander.owned[def.id] then
		local refund = BigNum.round(BigNum.mulNumber(price, CommanderConfig.CHEST_DUPLICATE_REFUND))
		data.gold = BigNum.add(data.gold, refund)
		DataService.markChanged(player)
		return { ok = true, itemId = def.id, duplicate = true, refund = refund }
	end
	addItem(data, def)
	DataService.markChanged(player)
	return { ok = true, itemId = def.id, duplicate = false }
end

-- Clan War results (ClanWarService): items for finishing in the top N.
function CommanderService.grantForClanWar(player: Player, rank: number)
	for itemId, def in CommanderConfig.ITEMS do
		if def.unlock.kind == "clanWar" and rank <= (def.unlock.value or 0) then
			CommanderService.grant(player, itemId)
		end
	end
end

-- Grants anything the player has earned by playing.
local function checkUnlocks(player: Player, data: PlayerData)
	for itemId, def in CommanderConfig.ITEMS do
		if not data.commander.owned[itemId] then
			local unlock = def.unlock
			local value = unlock.value or math.huge
			local earned = (unlock.kind == "stage" and data.bestStage >= value)
				or (unlock.kind == "ascensions" and data.stats.ascensions >= value)
				or (unlock.kind == "loginStreak" and data.daily.streak >= value)
			if earned then
				CommanderService.grant(player, itemId)
			end
		end
	end
end

-- Old or edited saves: drop anything that isn't a real item in the right slot.
local function clean(data: PlayerData)
	for itemId, value in data.commander.owned do
		if value ~= true or CommanderConfig.ITEMS[itemId] == nil then
			data.commander.owned[itemId] = nil
		end
	end
	for chestId, count in data.commander.pity do
		if CommanderConfig.CHESTS[chestId] == nil or typeof(count) ~= "number" or count ~= count then
			data.commander.pity[chestId] = nil
		else
			data.commander.pity[chestId] = math.clamp(math.floor(count), 0, CommanderConfig.CHEST_PITY_EVERY)
		end
	end
	for _, slot in CommanderConfig.SLOTS do
		local itemId = data.commander.equipped[slot]
		local def = if typeof(itemId) == "string" then CommanderConfig.ITEMS[itemId] else nil
		if def == nil or def.slot ~= slot then
			data.commander.equipped[slot] = ""
		end
	end
end

local function equip(player: Player, request: EquipRequest)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	if request.itemId == "" then
		data.commander.equipped[request.slot] = ""
	else
		local def = CommanderConfig.ITEMS[request.itemId]
		if def == nil or def.slot ~= request.slot or not isOwned(player, data, def) then
			return
		end
		data.commander.equipped[request.slot] = request.itemId
	end
	DataService.markChanged(player)
end

function CommanderService.start()
	SyncService.addSnapshotFields(function(player: Player, data: PlayerData): { [string]: any }
		local owned: { [string]: boolean } = {}
		for itemId, def in CommanderConfig.ITEMS do
			if isOwned(player, data, def) then
				owned[itemId] = true
			end
		end
		return {
			commander = {
				owned = owned,
				equipped = table.clone(data.commander.equipped),
				pity = table.clone(data.commander.pity),
			},
		}
	end)

	-- Equipped items' bonuses. An item stops counting if you lose it (e.g. a pass refund).
	ModifierService.register(function(player: Player): ModifierService.PartialModifiers?
		local data = DataService.get(player)
		if data == nil then
			return nil
		end
		local result = { damage = 1, gold = 1, armyHp = 1, tap = 1 }
		for slot, itemId in data.commander.equipped do
			local def = CommanderConfig.ITEMS[itemId]
			if def ~= nil and def.multiplier ~= nil and isOwned(player, data, def) then
				local stat = CommanderConfig.SLOT_STATS[slot]
				local current = (result :: any)[stat]
				if current ~= nil then
					(result :: any)[stat] = current * def.multiplier
				end
			end
		end
		return result
	end)

	RemoteService.onEvent(
		Remotes.Events.EquipCommander,
		RateLimiter.new(CommanderConfig.EQUIP_REQUESTS_BURST, CommanderConfig.EQUIP_REQUESTS_PER_SECOND),
		function(slot: unknown, itemId: unknown): EquipRequest?
			local validSlot = Validate.oneOf(slot, CommanderConfig.SLOTS)
			if validSlot == nil or typeof(itemId) ~= "string" then
				return nil
			end
			if itemId ~= "" and CommanderConfig.ITEMS[itemId :: string] == nil then
				return nil
			end
			return { slot = validSlot, itemId = itemId :: string }
		end,
		equip
	)

	RemoteService.onInvoke(
		Remotes.Functions.OpenWardrobeChest,
		RateLimiter.new(CommanderConfig.CHEST_REQUESTS_BURST, CommanderConfig.CHEST_REQUESTS_PER_SECOND),
		function(chestId: unknown): string?
			return Validate.keyOf(chestId, CommanderConfig.CHESTS)
		end,
		openChest,
		REJECTED
	)

	DataService.ProfileLoaded:Connect(function(player: Player, data: PlayerData)
		clean(data)
		dirty[player] = true
	end)
	DataService.Changed:Connect(function(player: Player)
		dirty[player] = true
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			for player in dirty do
				dirty[player] = nil
				local data = DataService.get(player)
				if data ~= nil then
					checkUnlocks(player, data)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		dirty[player] = nil
	end)
end

return CommanderService
