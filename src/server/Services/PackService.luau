--!strict
-- Gear packs: rolls happen here on the server, never on the client.
--
-- A pack picks a random troop, slot, and rarity (weighted by PackConfig.ODDS).
--   Better than the slot's current rarity -> slot upgrades to it (level is kept).
--   Same or worse                         -> refund DUPLICATE_REFUND of the pack price.
-- Bad-luck protection: after PITY_EVERY - 1 packs in a row without PITY_MIN_RARITY or
-- better, the next roll is forced to be at least that rarity.
-- Hero Chests (from the daily login calendar) always roll Epic or better.
-- Paid packs come in tiers (PackConfig.TIERS: Basic / Elite / Royal), each with its own
-- price and odds; Elite and Royal unlock at an all-time best stage.
-- Epic Forge tokens (Robux product) upgrade a slot the player picks to Epic: no roll.
-- Free packs: one per boss the first time it's beaten. Granted by comparing the highest
-- boss beaten with the highest boss already rewarded, so it can never double-grant.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = Shared:WaitForChild("Config")
local PackConfig = require(Config:WaitForChild("PackConfig"))
local GearConfig = require(Config:WaitForChild("GearConfig"))
local TroopConfig = require(Config:WaitForChild("TroopConfig"))
local BossConfig = require(Config:WaitForChild("BossConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local Validate = require(Server.Util.Validate)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local CombatService = require(Services.CombatService)
local StageService = require(Services.StageService)
local ActivityService = require(Services.ActivityService)

type PackResult = Types.PackResult
type PlayerData = Types.PlayerData
type GearSlot = Types.GearSlot

local REJECTED: PackResult = { ok = false, reason = "Rejected" }

local rng = Random.new()

local PackService = {}

-- Rolls a rarity index from `odds`. `minRarity` forces the result to be at least that (pity).
local function rollRarity(odds: { number }, minRarity: number): number
	local total = 0
	for index, weight in odds do
		if index >= minRarity then
			total += weight
		end
	end
	local roll = rng:NextNumber() * total
	for index, weight in odds do
		if index >= minRarity and weight > 0 then
			roll -= weight
			if roll < 0 then
				return index
			end
		end
	end
	return #odds -- only reachable through floating point edge cases
end

-- Grants any free packs owed for bosses beaten but not yet rewarded.
local function grantOwedPacks(player: Player, data: PlayerData)
	local owedBosses = (data.highestBossDefeated - data.packs.rewardedBossStage) // BossConfig.BOSS_EVERY
	if owedBosses > 0 then
		data.packs.free += owedBosses * PackConfig.FREE_PACKS_PER_NEW_BOSS
		data.packs.rewardedBossStage = data.highestBossDefeated
		DataService.markChanged(player)
	end
end

-- "Gold" is the Basic pack (its old name, kept so older clients still work).
type PackMode = "Gold" | "Elite" | "Royal" | "Free" | "Hero"
local PAID_TIERS: { [string]: string } = { Gold = "Basic", Elite = "Elite", Royal = "Royal" }

local function openPack(player: Player, mode: PackMode): PackResult
	local data = DataService.get(player)
	if data == nil then
		return { ok = false, reason = "NotLoaded" }
	end

	local tier = PackConfig.TIERS[PAID_TIERS[mode] or "Basic"]
	if data.bestStage < tier.unlockStage then
		return { ok = false, reason = "TooEarly" }
	end
	local price = Formulas.packPrice(data.highestStage, tier.id)
	if mode == "Hero" then
		if data.packs.hero <= 0 then
			return { ok = false, reason = "NoHeroChests" }
		end
		data.packs.hero -= 1
	elseif mode == "Free" then
		if data.packs.free <= 0 then
			return { ok = false, reason = "NoFreePacks" }
		end
		data.packs.free -= 1
	else
		if BigNum.lt(data.gold, price) then
			return { ok = false, reason = "CantAfford" }
		end
		data.gold = BigNum.sub(data.gold, price)
	end

	-- Pick what the pack contains.
	-- Only troops you've unlocked, so packs never roll gear you can't use yet.
	local unlocked: { string } = {}
	for _, id in TroopConfig.ORDER do
		if Formulas.troopUnlocked(id, data.bestStage) then
			table.insert(unlocked, id)
		end
	end
	local troopId = unlocked[rng:NextInteger(1, #unlocked)]
	local slot = GearConfig.SLOTS[rng:NextInteger(1, #GearConfig.SLOTS)]
	local pityDue = data.packs.sinceEpic + 1 >= PackConfig.PITY_EVERY
	local guaranteed = pityDue or mode == "Hero"
	local rarity = rollRarity(tier.odds, if guaranteed then PackConfig.PITY_MIN_RARITY else 1)

	data.packs.opened += 1
	if rarity >= PackConfig.PITY_MIN_RARITY then
		data.packs.sinceEpic = 0
	else
		data.packs.sinceEpic += 1
	end

	local troopGear = data.gear[troopId]
	local state: Types.GearSlotState = if slot == "weapon" then troopGear.weapon else troopGear.armor
	local result: PackResult = { ok = true, troopId = troopId, slot = slot, rarity = rarity }

	if rarity > state.rarity then
		state.rarity = rarity
		result.upgraded = true
		CombatService.refreshArmy(player)
	else
		local refund = BigNum.round(BigNum.mulNumber(price, PackConfig.DUPLICATE_REFUND))
		data.gold = BigNum.add(data.gold, refund)
		result.upgraded = false
		result.refund = refund
	end

	ActivityService.record(player, "PackOpen", 1)
	DataService.markChanged(player)
	return result
end

type ForgeRequest = { troopId: string, slot: GearSlot }

-- Spends an Epic Forge token: the chosen troop + slot becomes FORGE_RARITY (Epic).
-- Refused (token kept) if the troop is locked or the slot is already Epic or better.
local function useForge(player: Player, request: ForgeRequest): PackResult
	local data = DataService.get(player)
	if data == nil then
		return { ok = false, reason = "NotLoaded" }
	end
	if data.packs.forge <= 0 then
		return { ok = false, reason = "NoForgeTokens" }
	end
	if not Formulas.troopUnlocked(request.troopId, data.bestStage) then
		return { ok = false, reason = "Locked" }
	end
	local troopGear = data.gear[request.troopId]
	local state: Types.GearSlotState = if request.slot == "weapon" then troopGear.weapon else troopGear.armor
	if state.rarity >= PackConfig.FORGE_RARITY then
		return { ok = false, reason = "AlreadyEpic" }
	end
	data.packs.forge -= 1
	state.rarity = PackConfig.FORGE_RARITY
	CombatService.refreshArmy(player)
	DataService.markChanged(player)
	return { ok = true, troopId = request.troopId, slot = request.slot, rarity = state.rarity, upgraded = true }
end

function PackService.start()
	DataService.ProfileLoaded:Connect(function(player: Player, data: PlayerData)
		-- StageService fills in highestBossDefeated on load; let it run first.
		task.defer(function()
			if DataService.get(player) ~= nil then
				grantOwedPacks(player, data)
			end
		end)
	end)

	StageService.BossDefeated:Connect(function(player: Player, _bossStage: number, _firstClear: boolean)
		local data = DataService.get(player)
		if data ~= nil then
			grantOwedPacks(player, data)
		end
	end)

	local limiter = RateLimiter.new(PackConfig.REQUESTS_BURST, PackConfig.REQUESTS_PER_SECOND)
	RemoteService.onInvoke(Remotes.Functions.OpenPack, limiter, function(mode: unknown): PackMode?
		return Validate.oneOf(mode, { "Gold", "Elite", "Royal", "Free", "Hero" }) :: PackMode?
	end, openPack, REJECTED)

	RemoteService.onInvoke(Remotes.Functions.UseForge, limiter, function(troopId: unknown, slot: unknown): ForgeRequest?
		local validTroop = Validate.keyOf(troopId, TroopConfig.TROOPS)
		local validSlot = Validate.oneOf(slot, GearConfig.SLOTS)
		if validTroop == nil or validSlot == nil then
			return nil
		end
		return { troopId = validTroop, slot = validSlot :: GearSlot }
	end, useForge, REJECTED)
end

return PackService
