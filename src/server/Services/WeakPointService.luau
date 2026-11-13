--!strict
-- Weak points (WeakPointConfig): during boss fights and raid attacks the server spawns a
-- target every few seconds and tells the client (WeakPoint remote). Tapping it in time
-- (HitWeakPoint) queues a burst of damage through CombatService, the same way clicks
-- and abilities do, so it also gets through a boss shield and counts toward raid damage.
-- Missing one resets the streak. Nothing here is saved.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeakPointConfig = require(Shared:WaitForChild("Config"):WaitForChild("WeakPointConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local Validate = require(Server.Util.Validate)
local RemoteService = require(Services.RemoteService)
local CombatService = require(Services.CombatService)
local StageService = require(Services.StageService)
local ActivityService = require(Services.ActivityService)

type WeakPointResult = Types.WeakPointResult

type Active = { id: number, expiresAt: number }
type State = {
	encounter: any, -- the StageService encounter this schedule belongs to
	nextAt: number,
	active: Active?,
	nextId: number,
	streak: number,
}

local REJECTED: WeakPointResult = { ok = false, reason = "Rejected" }

local states: { [Player]: State } = {}
local rng = Random.new()

local WeakPointService = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function fighting(encounter: any): boolean
	return encounter ~= nil and (encounter.kind == "Boss" or encounter.kind == "Raid")
end

local function update(player: Player)
	local encounter = StageService.getEncounter(player)
	local state = states[player]
	if not fighting(encounter) then
		if state ~= nil then
			states[player] = nil
			RemoteService.fireClient(Remotes.Events.WeakPoint, player, { kind = "Clear", id = 0, expiresAt = 0, x = 0, y = 0 })
		end
		return
	end

	local time = now()
	if state == nil or state.encounter ~= encounter then
		-- A new fight: start a fresh schedule (ids keep counting so old taps can't match).
		local newState: State = {
			encounter = encounter,
			nextAt = time + rng:NextNumber(WeakPointConfig.FIRST_DELAY_MIN, WeakPointConfig.FIRST_DELAY_MAX),
			active = nil,
			nextId = if state ~= nil then state.nextId else 0,
			streak = 0,
		}
		states[player] = newState
		state = newState
	end
	local current = state :: State

	local active = current.active
	if active ~= nil and time > active.expiresAt + WeakPointConfig.GRACE then
		current.active = nil -- missed
		current.streak = 0
	end
	if current.active == nil and time >= current.nextAt then
		current.nextId += 1
		local spawned: Active = { id = current.nextId, expiresAt = time + WeakPointConfig.WINDOW }
		current.active = spawned
		current.nextAt = time + rng:NextNumber(WeakPointConfig.INTERVAL_MIN, WeakPointConfig.INTERVAL_MAX)
		RemoteService.fireClient(Remotes.Events.WeakPoint, player, {
			kind = "Spawn",
			id = spawned.id,
			expiresAt = spawned.expiresAt,
			x = rng:NextNumber(-1, 1), -- where on the enemy it shows (client picks the exact spot)
			y = rng:NextNumber(0.3, 0.9),
		})
	end
end

local function hit(player: Player, id: number): WeakPointResult
	local state = states[player]
	local active = if state ~= nil then state.active else nil
	if state == nil or active == nil or active.id ~= id then
		return { ok = false, reason = "NoWeakPoint" }
	end
	state.active = nil
	if now() > active.expiresAt + WeakPointConfig.GRACE then
		state.streak = 0
		return { ok = false, reason = "TooLate" }
	end
	local bonus = math.min(state.streak * WeakPointConfig.STREAK_BONUS, WeakPointConfig.MAX_STREAK_BONUS)
	state.streak += 1
	local damage = BigNum.mulNumber(CombatService.getDps(player), WeakPointConfig.BURST_SECONDS * (1 + bonus))
	CombatService.queueDamage(player, damage)
	ActivityService.record(player, "WeakPoint", 1)
	return { ok = true, damage = damage, streak = state.streak }
end

function WeakPointService.start()
	RemoteService.onInvoke(
		Remotes.Functions.HitWeakPoint,
		RateLimiter.new(WeakPointConfig.REQUESTS_BURST, WeakPointConfig.REQUESTS_PER_SECOND),
		function(id: unknown): number?
			return Validate.integer(id, 1, 2 ^ 30)
		end,
		hit,
		REJECTED
	)

	task.spawn(function()
		while true do
			task.wait(WeakPointConfig.TICK)
			for _, player in Players:GetPlayers() do
				update(player)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)
end

return WeakPointService
