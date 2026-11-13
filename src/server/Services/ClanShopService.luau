--!strict
-- Clan Tokens and the clan shop (Phase 11d D). Tokens are a personal currency in your
-- own save (kept on Ascend), earned from Clan War placement, MVP, head-to-head wins and
-- clan quests (ClanWarService calls addTokens). Spending them is a "BuyClanShop" clan
-- action: commander gear (once each, via CommanderService.grant), Hero Chests, packs.
-- Everything is in the player's session-locked save, so nothing here needs cross-server
-- care.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local ClanConfig = require(Shared:WaitForChild("Config"):WaitForChild("ClanConfig"))
local DataService = require(Services.DataService)
local ClanService = require(Services.ClanService)
local CommanderService = require(Services.CommanderService)

type PlayerData = Types.PlayerData
type ClanResult = Types.ClanResult

local ClanShopService = {}

local function shopItem(itemId: string)
	for _, item in ClanConfig.SHOP do
		if item.id == itemId then
			return item
		end
	end
	return nil
end

function ClanShopService.addTokens(player: Player, amount: number)
	local data = DataService.get(player)
	if data ~= nil and amount > 0 then
		data.clanTokens += math.floor(amount)
		DataService.markChanged(player)
	end
end

local function buy(player: Player, data: PlayerData, itemId: string): ClanResult
	local item = shopItem(itemId)
	if item == nil then
		return { ok = false, reason = "Rejected" }
	end
	if item.kind == "gear" and data.commander.owned[item.id] then
		return { ok = false, reason = "AlreadyOwned" }
	end
	if data.clanTokens < item.cost then
		return { ok = false, reason = "NotEnoughTokens" }
	end
	data.clanTokens -= item.cost
	if item.kind == "gear" then
		CommanderService.grant(player, item.id)
	elseif item.kind == "heroChests" then
		data.packs.hero += item.amount or 1
	elseif item.kind == "packs" then
		data.packs.free += item.amount or 1
	end
	DataService.markChanged(player)
	return { ok = true }
end

function ClanShopService.start()
	ClanService.registerAction("BuyClanShop", function(arg: unknown): (boolean, any)
		return typeof(arg) == "string" and shopItem(arg :: string) ~= nil, arg
	end, buy)
end

return ClanShopService
