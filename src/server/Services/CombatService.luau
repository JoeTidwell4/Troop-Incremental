--!strict
-- Runs every player's fight on the server.
--
-- There are no physical troops: each tick we compute total damage (army DPS * time +
-- any queued tap damage), apply it to the current enemy, and resolve kills with math.
-- One loop handles every player, TICK_RATE times per second, so cost stays tiny.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Config = Shared:WaitForChild("Config")
local StageConfig = require(Config:WaitForChild("StageConfig"))
local CombatConfig = require(Config:WaitForChild("CombatConfig"))
local DataService = require(Services.DataService)

type BigNum = BigNum.BigNum
type PlayerData = Types.PlayerData

-- Per-player fight state that is NOT saved (it's rebuilt when they rejoin).
export type CombatState = {
	enemyHp: BigNum,
	enemyMaxHp: BigNum,
	goldPerKill: BigNum,
	armyDps: BigNum,
	tapDamage: BigNum,
	pendingDamage: BigNum, -- tap damage waiting for the next tick
}

local states: { [Player]: CombatState } = {}

local CombatService = {}

local function loadStage(state: CombatState, stage: number)
	state.enemyMaxHp = Formulas.enemyHp(stage)
	state.enemyHp = state.enemyMaxHp
	state.goldPerKill = Formulas.goldPerKill(stage)
end

-- Read-only view used by SyncService to build the client snapshot.
function CombatService.getState(player: Player): CombatState?
	return states[player]
end

-- Recalculate army damage. Call after anything that changes troops or multipliers.
function CombatService.refreshArmy(player: Player)
	local state = states[player]
	local data = DataService.get(player)
	if state == nil or data == nil then
		return
	end
	state.armyDps = Formulas.armyDps(data.troops)
	state.tapDamage = Formulas.tapDamage(state.armyDps)
end

-- Queue damage from taps that TapService already rate-limited.
function CombatService.applyTaps(player: Player, taps: number)
	local state = states[player]
	local data = DataService.get(player)
	if state == nil or data == nil or taps <= 0 then
		return
	end
	state.pendingDamage = BigNum.add(state.pendingDamage, BigNum.mulNumber(state.tapDamage, taps))
	data.stats.totalTaps += taps
end

local function awardKills(data: PlayerData, state: CombatState, kills: number)
	local gold = BigNum.mulNumber(state.goldPerKill, kills)
	data.gold = BigNum.add(data.gold, gold)
	data.stats.lifetimeGold = BigNum.add(data.stats.lifetimeGold, gold)
	data.stats.totalKills += kills
	data.killsInStage += kills
end

local function advanceStage(data: PlayerData, state: CombatState)
	data.stage += 1
	data.killsInStage = 0
	data.highestStage = math.max(data.highestStage, data.stage)
	loadStage(state, data.stage)
end

-- Applies `damage` to the player's fight. Returns true if anything changed.
local function applyDamage(data: PlayerData, state: CombatState, damage: BigNum): boolean
	if BigNum.isZero(damage) then
		return false
	end

	local enemiesPerStage = StageConfig.ENEMIES_PER_STAGE
	local stageClears = 0

	while not BigNum.isZero(damage) do
		if BigNum.lt(damage, state.enemyHp) then
			state.enemyHp = BigNum.sub(state.enemyHp, damage)
			return true
		end

		-- Current enemy dies. Leftover damage can kill more enemies on this stage.
		damage = BigNum.sub(damage, state.enemyHp)
		local enemiesLeft = enemiesPerStage - data.killsInStage - 1
		local extraKills = 0
		if enemiesLeft > 0 then
			local fullKills = math.floor(BigNum.toNumber(BigNum.div(damage, state.enemyMaxHp)))
			extraKills = math.min(fullKills, enemiesLeft)
			damage = BigNum.sub(damage, BigNum.mulNumber(state.enemyMaxHp, extraKills))
		end
		awardKills(data, state, 1 + extraKills)

		if data.killsInStage >= enemiesPerStage then
			advanceStage(data, state)
			stageClears += 1
			if stageClears >= StageConfig.MAX_STAGE_CLEARS_PER_TICK then
				return true -- leftover damage is discarded
			end
		else
			-- Partly damaged next enemy on the same stage.
			state.enemyHp = BigNum.sub(state.enemyMaxHp, damage)
			return true
		end
	end
	return true
end

local function tick(dt: number)
	for player, state in states do
		local data = DataService.get(player)
		if data ~= nil then
			local damage = BigNum.add(BigNum.mulNumber(state.armyDps, dt), state.pendingDamage)
			state.pendingDamage = BigNum.ZERO
			if applyDamage(data, state, damage) then
				DataService.markChanged(player)
			end
		end
	end
end

local function onProfileLoaded(player: Player, data: PlayerData)
	-- Saved kill count can't be past the end of a stage (e.g. if ENEMIES_PER_STAGE was lowered).
	data.killsInStage = math.clamp(data.killsInStage, 0, StageConfig.ENEMIES_PER_STAGE - 1)
	local state: CombatState = {
		enemyHp = BigNum.ZERO,
		enemyMaxHp = BigNum.ZERO,
		goldPerKill = BigNum.ZERO,
		armyDps = BigNum.ZERO,
		tapDamage = BigNum.ZERO,
		pendingDamage = BigNum.ZERO,
	}
	loadStage(state, data.stage)
	states[player] = state
	CombatService.refreshArmy(player)
	DataService.markChanged(player)
end

function CombatService.start()
	DataService.ProfileLoaded:Connect(onProfileLoaded)
	DataService.ProfileReleasing:Connect(function(player: Player)
		states[player] = nil
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)

	local interval = 1 / CombatConfig.TICK_RATE
	local elapsed = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		elapsed += deltaTime
		if elapsed >= interval then
			-- Cap dt so a server hiccup can't dump minutes of damage in one tick.
			local dt = math.min(elapsed, 1)
			elapsed = 0
			tick(dt)
		end
	end)
end

return CombatService
