--!strict
-- Commander abilities (AbilityConfig). Unlocks use your all-time best stage, so they stay
-- unlocked after Ascending. Phase 13a: you equip LOADOUT_SLOTS of them (data.abilityLoadout)
-- and only equipped abilities can be used.
--
-- The server owns every cooldown. A client asking to use an ability that's locked, not
-- equipped or still cooling down is simply ignored. Cooldowns live only in server memory,
-- so they reset if you rejoin. That's fine: rejoining takes longer than any cooldown.
-- Timestamps use workspace:GetServerTimeNow(), which the client can read too, so the
-- UI can count down smoothly without asking the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local AbilityConfig = require(Shared:WaitForChild("Config"):WaitForChild("AbilityConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local Validate = require(Server.Util.Validate)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local CombatService = require(Services.CombatService)
local ModifierService = require(Services.ModifierService)
local ActivityService = require(Services.ActivityService)
local StageService = require(Services.StageService)

type AbilityTimers = Types.AbilityTimers
type PlayerData = Types.PlayerData

local timers: { [Player]: { [string]: AbilityTimers } } = {}
-- Bounty: kills left and the gold multiplier they get.
local bounties: { [Player]: { left: number, multiplier: number } } = {}

local AbilityService = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function getTimers(player: Player): { [string]: AbilityTimers }
	local playerTimers = timers[player]
	if playerTimers == nil then
		playerTimers = {}
		timers[player] = playerTimers
	end
	return playerTimers
end

-- Copy of the player's ability timers for the client snapshot.
function AbilityService.getTimers(player: Player): { [string]: AbilityTimers }
	local copy: { [string]: AbilityTimers } = {}
	for id, t in getTimers(player) do
		copy[id] = { readyAt = t.readyAt, activeUntil = t.activeUntil }
	end
	return copy
end

function AbilityService.getBountyLeft(player: Player): number
	local bounty = bounties[player]
	return if bounty ~= nil then bounty.left else 0
end

local function isActive(player: Player, abilityId: string): boolean
	local t = getTimers(player)[abilityId]
	return t ~= nil and now() < t.activeUntil
end

local function isEquipped(data: PlayerData, abilityId: string): boolean
	return table.find(data.abilityLoadout, abilityId) ~= nil
end

-- Stats of every ability active right now (for multipliers).
local function activeStats(player: Player): { Types.AbilityStats }
	local data = DataService.get(player)
	local list: { Types.AbilityStats } = {}
	for abilityId in AbilityConfig.ABILITIES do
		if isActive(player, abilityId) then
			table.insert(list, Formulas.abilityStats(abilityId, if data ~= nil then data.abilityUpgrades else nil, if data ~= nil then data.skills.ranks else nil))
		end
	end
	return list
end

-- War Drums: weak points come this much more often (1 = normal). Used by WeakPointService.
function AbilityService.weakPointGapScale(player: Player): number
	local scale = 1
	for _, stats in activeStats(player) do
		scale *= stats.weakPointGapScale or 1
	end
	return scale
end

local function useAbility(player: Player, abilityId: string)
	local data = DataService.get(player)
	local def = AbilityConfig.ABILITIES[abilityId]
	if data == nil or def == nil then
		return
	end
	if data.bestStage < def.unlockStage or not isEquipped(data, abilityId) then
		return -- locked or not equipped
	end

	local playerTimers = getTimers(player)
	local t = playerTimers[abilityId]
	local currentTime = now()
	if t ~= nil and currentTime < t.readyAt then
		return -- still on cooldown
	end

	local stats = Formulas.abilityStats(abilityId, data.abilityUpgrades, data.skills.ranks)
	local encounter = StageService.getEncounter(player)
	if def.bossOnly and (encounter == nil or encounter.kind ~= "Boss") then
		return -- would be wasted (the button says so)
	end

	-- Effects that happen right away.
	if stats.healFraction ~= nil and not StageService.healArmy(player, stats.healFraction) then
		return
	end
	if stats.burstDpsSeconds ~= nil then
		local seconds = stats.burstDpsSeconds
		if stats.executeThreshold ~= nil and encounter ~= nil and not BigNum.isZero(encounter.enemyMaxHp) then
			local fraction = BigNum.toNumber(BigNum.div(encounter.enemyHp, encounter.enemyMaxHp))
			if fraction < stats.executeThreshold then
				seconds *= stats.executeMultiplier or 1
			end
		end
		CombatService.queueDamage(player, BigNum.mulNumber(CombatService.getDps(player), seconds))
	end
	if stats.bountyKills ~= nil then
		bounties[player] = { left = math.floor(stats.bountyKills), multiplier = stats.bountyGoldMultiplier or 1 }
	end

	playerTimers[abilityId] = {
		readyAt = currentTime + stats.cooldown,
		activeUntil = if stats.duration ~= nil then currentTime + stats.duration else 0,
	}
	ActivityService.record(player, "Ability", 1)
	DataService.markChanged(player)
end

-- Equips `abilityId` in `slot`. If it's already in another slot the two swap places.
-- Only outside boss fights and raids, and a freshly equipped ability can't be used for
-- SWAP_COOLDOWN seconds, so you can't swap through the whole list before a boss.
local function setSlot(player: Player, request: { slot: number, abilityId: string })
	local data = DataService.get(player)
	local def = AbilityConfig.ABILITIES[request.abilityId]
	if data == nil or def == nil or data.bestStage < def.unlockStage then
		return
	end
	if request.slot > Formulas.loadoutSlots(data.skills.ranks) then
		return -- the 4th slot needs Grand Tactician
	end
	local encounter = StageService.getEncounter(player)
	if encounter ~= nil and encounter.kind ~= "Normal" then
		return
	end
	local loadout = data.abilityLoadout
	local current = loadout[request.slot]
	if current == request.abilityId then
		return
	end
	local otherSlot = table.find(loadout, request.abilityId)
	if otherSlot ~= nil then
		loadout[otherSlot] = current -- swap places; both were already equipped
	else
		local t = getTimers(player)[request.abilityId]
		local readyAt = now() + AbilityConfig.SWAP_COOLDOWN
		getTimers(player)[request.abilityId] = {
			readyAt = math.max(readyAt, if t ~= nil then t.readyAt else 0),
			activeUntil = if t ~= nil then t.activeUntil else 0,
		}
	end
	loadout[request.slot] = request.abilityId
	DataService.markChanged(player)
end

-- Makes every ability ready right now (active effects keep running). Used when a raid
-- attack starts, so every raid begins with your full kit.
function AbilityService.resetCooldowns(player: Player)
	for _, t in getTimers(player) do
		t.readyAt = 0
	end
	DataService.markChanged(player)
end

-- Uses an ability if it's unlocked, equipped and ready; does nothing otherwise.
-- (Used by the Auto Abilities pass. Same checks as a player pressing the button.)
function AbilityService.tryUse(player: Player, abilityId: string)
	useAbility(player, abilityId)
end

-- The equipped abilities, slot order (Auto Abilities uses this).
function AbilityService.getLoadout(player: Player): { string }
	local data = DataService.get(player)
	return if data ~= nil then table.clone(data.abilityLoadout) else {}
end

function AbilityService.start()
	-- Active timed abilities feed their multipliers into combat.
	ModifierService.register(function(player: Player): ModifierService.PartialModifiers?
		local damage, gold, tap, bossDamage = 1, 1, 1, 1
		for _, stats in activeStats(player) do
			damage *= stats.damageMultiplier or 1
			gold *= stats.goldMultiplier or 1
			tap *= stats.tapMultiplier or 1
			bossDamage *= stats.bossDamageTaken or 1
		end
		return { damage = damage, gold = gold, tap = tap, bossDamage = bossDamage }
	end)

	-- Bounty: extra gold on the next kills (StageService asks before paying them).
	StageService.bountyHook = function(player: Player, kills: number): number
		local bounty = bounties[player]
		if bounty == nil then
			return 0
		end
		local used = math.min(kills, bounty.left)
		bounty.left -= used
		if bounty.left <= 0 then
			bounties[player] = nil
		end
		return used * (bounty.multiplier - 1)
	end

	local limiter = RateLimiter.new(AbilityConfig.REQUESTS_BURST, AbilityConfig.REQUESTS_PER_SECOND)
	RemoteService.onEvent(Remotes.Events.UseAbility, limiter, function(abilityId: unknown): string?
		return Validate.keyOf(abilityId, AbilityConfig.ABILITIES)
	end, useAbility)
	RemoteService.onEvent(Remotes.Events.SetAbilitySlot, RateLimiter.new(6, 3), function(slot: unknown, abilityId: unknown): { slot: number, abilityId: string }?
		local id = Validate.keyOf(abilityId, AbilityConfig.ABILITIES)
		if id == nil or typeof(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > #AbilityConfig.SLOT_KEYS then
			return nil
		end
		return { slot = slot :: number, abilityId = id }
	end, setSlot)

	Players.PlayerRemoving:Connect(function(player: Player)
		timers[player] = nil
		bounties[player] = nil
	end)
end

return AbilityService
