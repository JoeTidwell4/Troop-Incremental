--!strict
-- Commander abilities (Rally, Barrage, Plunder). Unlocks use your all-time best stage, so
-- they stay unlocked after Ascending.
--
-- The server owns every cooldown. A client asking to use an ability that's locked or
-- still cooling down is simply ignored. Cooldowns live only in server memory, so they
-- reset if you rejoin. That's fine: rejoining takes longer than any cooldown.
-- Timestamps use workspace:GetServerTimeNow(), which the client can read too, so the
-- UI can count down smoothly without asking the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local AbilityConfig = require(Shared:WaitForChild("Config"):WaitForChild("AbilityConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local Validate = require(Server.Util.Validate)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local CombatService = require(Services.CombatService)
local ModifierService = require(Services.ModifierService)
local ActivityService = require(Services.ActivityService)

type AbilityTimers = Types.AbilityTimers

local timers: { [Player]: { [string]: AbilityTimers } } = {}

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

local function isActive(player: Player, abilityId: string): boolean
	local t = getTimers(player)[abilityId]
	return t ~= nil and now() < t.activeUntil
end

local function useAbility(player: Player, abilityId: string)
	local data = DataService.get(player)
	local def = AbilityConfig.ABILITIES[abilityId]
	if data == nil or def == nil then
		return
	end
	if data.bestStage < def.unlockStage then
		return -- locked
	end

	local playerTimers = getTimers(player)
	local t = playerTimers[abilityId]
	local currentTime = now()
	if t ~= nil and currentTime < t.readyAt then
		return -- still on cooldown
	end

	playerTimers[abilityId] = {
		readyAt = currentTime + def.cooldown,
		activeUntil = if def.duration ~= nil then currentTime + def.duration else 0,
	}

	if def.burstDpsSeconds ~= nil then
		local burst = BigNum.mulNumber(CombatService.getDps(player), def.burstDpsSeconds)
		CombatService.queueDamage(player, burst)
	end

	ActivityService.record(player, "Ability", 1)
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

-- Uses an ability if it's unlocked and ready; does nothing otherwise.
-- (Used by the Auto Abilities pass. Same checks as a player pressing the button.)
function AbilityService.tryUse(player: Player, abilityId: string)
	useAbility(player, abilityId)
end

function AbilityService.start()
	-- Active timed abilities feed their multipliers into combat.
	ModifierService.register(function(player: Player): ModifierService.PartialModifiers?
		local damage, gold = 1, 1
		for abilityId, def in AbilityConfig.ABILITIES do
			if isActive(player, abilityId) then
				damage *= def.damageMultiplier or 1
				gold *= def.goldMultiplier or 1
			end
		end
		return { damage = damage, gold = gold }
	end)

	local limiter = RateLimiter.new(AbilityConfig.REQUESTS_BURST, AbilityConfig.REQUESTS_PER_SECOND)
	RemoteService.onEvent(Remotes.Events.UseAbility, limiter, function(abilityId: unknown): string?
		return Validate.keyOf(abilityId, AbilityConfig.ABILITIES)
	end, useAbility)

	Players.PlayerRemoving:Connect(function(player: Player)
		timers[player] = nil
	end)
end

return AbilityService
