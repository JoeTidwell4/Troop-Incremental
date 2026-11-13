--!strict
-- Commander gear (CommanderConfig): what your avatar wears and the small bonuses it gives.
-- Items are unlocked by playing (best stage, Ascends, login streak; Clan War and the clan
-- shop grant theirs through CommanderService.grant). Robux pass items are looks-only
-- and owned while you own the pass. The equipped items' bonuses go into ModifierService.
-- Everything here is kept on Ascend.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local CommanderConfig = require(Shared:WaitForChild("Config"):WaitForChild("CommanderConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local Validate = require(Server.Util.Validate)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)
local ModifierService = require(Services.ModifierService)
local MonetizationService = require(Services.MonetizationService)

type PlayerData = Types.PlayerData
type ItemDef = Types.CommanderItemDef
type EquipRequest = { slot: string, itemId: string }

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

-- Gives an item (no-op if already owned) and tells the player.
function CommanderService.grant(player: Player, itemId: string)
	local data = DataService.get(player)
	local def = CommanderConfig.ITEMS[itemId]
	if data == nil or def == nil or data.commander.owned[itemId] then
		return
	end
	data.commander.owned[itemId] = true
	-- Nothing in that slot yet: put it on right away.
	if (data.commander.equipped[def.slot] or "") == "" then
		data.commander.equipped[def.slot] = itemId
	end
	DataService.markChanged(player)
	RemoteService.fireClient(Remotes.Events.Notice, player, { kind = "CommanderItem", stage = 0, itemName = def.displayName })
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
		return { commander = { owned = owned, equipped = table.clone(data.commander.equipped) } }
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
