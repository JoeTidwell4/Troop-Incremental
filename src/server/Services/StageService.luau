--!strict
-- Runs the fight: what you're up against (normal enemies or a boss), applying the army's
-- damage every tick, kills, gold, stage progress, boss timers, and boss fail/retreat.
--
-- One loop handles every player TICK_RATE times per second.
--
-- Boss rules:
--   * Every BOSS_EVERY-th stage is one boss with a time limit.
--   * The boss damages your army's total HP each second.
--   * Win: big gold reward and you move on to the next area.
--   * Lose (time runs out or army HP hits 0): back one stage, auto-advance turns off.
--     The player farms there until they press Fight Boss or turn auto-advance back on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = Shared:WaitForChild("Config")
local StageConfig = require(Config:WaitForChild("StageConfig"))
local CombatConfig = require(Config:WaitForChild("CombatConfig"))
local BossConfig = require(Config:WaitForChild("BossConfig"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local RateLimiter = require(Server.Util.RateLimiter)
local Validate = require(Server.Util.Validate)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local CombatService = require(Services.CombatService)
local ModifierService = require(Services.ModifierService)

type BigNum = BigNum.BigNum
type PlayerData = Types.PlayerData
type Notice = Types.Notice

-- Per-player fight state that is NOT saved (rebuilt from the saved stage on rejoin).
export type Encounter = {
	kind: Types.EncounterKind,
	enemyHp: BigNum,
	enemyMaxHp: BigNum,
	goldPerKill: BigNum, -- before gold multipliers
	bossEndsAt: number, -- server time; 0 for normal stages
	bossDps: BigNum,
	armyDamageTaken: BigNum, -- boss damage taken so far; army HP = max HP - this
}

local encounters: { [Player]: Encounter } = {}

local StageService = {
	-- Fires when a boss is beaten: (player, bossStage, firstClear).
	-- firstClear is true the first time the player ever beats that boss stage.
	BossDefeated = Signal.new() :: Signal.Signal<Player, number, boolean>,
	-- Fires whenever enemies die: (player, stage, kills, wasBoss). Used for war points.
	Killed = Signal.new() :: Signal.Signal<Player, number, number, boolean>,
}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function newEncounter(stage: number): Encounter
	if Formulas.isBossStage(stage) then
		local hp = Formulas.bossHp(stage)
		return {
			kind = "Boss",
			enemyHp = hp,
			enemyMaxHp = hp,
			goldPerKill = Formulas.bossGold(stage),
			bossEndsAt = now() + BossConfig.BOSS_TIME_LIMIT,
			bossDps = Formulas.bossDps(stage),
			armyDamageTaken = BigNum.ZERO,
		}
	end
	local hp = Formulas.enemyHp(stage)
	return {
		kind = "Normal",
		enemyHp = hp,
		enemyMaxHp = hp,
		goldPerKill = Formulas.goldPerKill(stage),
		bossEndsAt = 0,
		bossDps = BigNum.ZERO,
		armyDamageTaken = BigNum.ZERO,
	}
end

local function notify(player: Player, notice: Notice)
	RemoteService.fireClient(Remotes.Events.Notice, player, notice)
end

-- Read-only view for SyncService.
function StageService.getEncounter(player: Player): Encounter?
	return encounters[player]
end

-- Current army HP (only drops during boss fights).
function StageService.getArmyHp(player: Player): BigNum
	local maxHp = CombatService.getMaxHp(player)
	local encounter = encounters[player]
	if encounter == nil then
		return maxHp
	end
	return BigNum.sub(maxHp, encounter.armyDamageTaken)
end

local function goToStage(player: Player, data: PlayerData, stage: number)
	data.stage = math.max(1, stage)
	data.killsInStage = 0
	data.highestStage = math.max(data.highestStage, data.stage)
	data.bestStage = math.max(data.bestStage, data.highestStage)
	encounters[player] = newEncounter(data.stage)
end

-- Starts a fresh fight from the player's current saved stage (used after Ascending).
function StageService.restart(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	CombatService.refreshArmy(player)
	encounters[player] = newEncounter(data.stage)
	DataService.markChanged(player)
end

local function failBoss(player: Player, data: PlayerData, reason: "OutOfTime" | "ArmyDefeated")
	local bossStage = data.stage
	data.autoAdvance = false
	goToStage(player, data, bossStage - 1)
	notify(player, { kind = "BossFailed", stage = bossStage, reason = reason })
end

local function onStageCleared(player: Player, data: PlayerData, encounter: Encounter)
	if encounter.kind == "Boss" then
		local bossStage = data.stage
		local firstClear = bossStage > data.highestBossDefeated
		data.stats.bossesDefeated += 1
		data.highestBossDefeated = math.max(data.highestBossDefeated, bossStage)
		notify(player, { kind = "BossDefeated", stage = bossStage, firstClear = firstClear })
		StageService.BossDefeated:Fire(player, bossStage, firstClear)
		goToStage(player, data, bossStage + 1)
	elseif data.autoAdvance then
		goToStage(player, data, data.stage + 1)
	else
		-- Auto-advance is off: replay the same stage (farming).
		goToStage(player, data, data.stage)
	end
end

-- Applies `damage` to the current enemy. Returns true if anything changed.
local function applyDamage(player: Player, data: PlayerData, damage: BigNum): boolean
	if BigNum.isZero(damage) then
		return false
	end
	local encounter = encounters[player]
	local goldMultiplier = ModifierService.get(player).gold
	local enemiesThisStage = if encounter.kind == "Boss" then 1 else StageConfig.ENEMIES_PER_STAGE

	if BigNum.lt(damage, encounter.enemyHp) then
		encounter.enemyHp = BigNum.sub(encounter.enemyHp, damage)
		return true
	end

	-- Current enemy dies. Leftover damage can kill more enemies on the same stage.
	damage = BigNum.sub(damage, encounter.enemyHp)
	local enemiesLeft = enemiesThisStage - data.killsInStage - 1
	local extraKills = 0
	if enemiesLeft > 0 then
		local fullKills = math.floor(BigNum.toNumber(BigNum.div(damage, encounter.enemyMaxHp)))
		extraKills = math.min(fullKills, enemiesLeft)
		damage = BigNum.sub(damage, BigNum.mulNumber(encounter.enemyMaxHp, extraKills))
	end

	local kills = 1 + extraKills
	local gold = BigNum.mulNumber(encounter.goldPerKill, kills * goldMultiplier)
	data.gold = BigNum.add(data.gold, gold)
	data.stats.lifetimeGold = BigNum.add(data.stats.lifetimeGold, gold)
	data.stats.totalKills += kills
	data.killsInStage += kills
	StageService.Killed:Fire(player, data.stage, kills, encounter.kind == "Boss")

	if data.killsInStage >= enemiesThisStage then
		-- At most one stage clear per tick: leftover damage is discarded so a huge
		-- spike (e.g. Barrage) can't skip many stages at once.
		onStageCleared(player, data, encounter)
	else
		encounter.enemyHp = BigNum.sub(encounter.enemyMaxHp, damage)
	end
	return true
end

-- Boss attacks the army and the clock ticks. Returns true if anything changed.
local function updateBoss(player: Player, data: PlayerData, dt: number): boolean
	local encounter = encounters[player]
	if encounter == nil or encounter.kind ~= "Boss" then
		return false
	end
	encounter.armyDamageTaken = BigNum.add(encounter.armyDamageTaken, BigNum.mulNumber(encounter.bossDps, dt))
	if BigNum.gte(encounter.armyDamageTaken, CombatService.getMaxHp(player)) then
		failBoss(player, data, "ArmyDefeated")
	elseif now() >= encounter.bossEndsAt then
		failBoss(player, data, "OutOfTime")
	end
	return true
end

local function tick(dt: number)
	for player in encounters do
		local data = DataService.get(player)
		if data ~= nil then
			local damage = CombatService.takeDamage(player, dt)
			local changed = applyDamage(player, data, damage)
			-- Checked after damage so a kill on the last moment counts as a win.
			changed = updateBoss(player, data, dt) or changed
			if changed then
				DataService.markChanged(player)
			end
		end
	end
end

local function onProfileLoaded(player: Player, data: PlayerData)
	-- Saved kill count can't be past the end of a stage (e.g. if ENEMIES_PER_STAGE was lowered).
	data.killsInStage = math.clamp(data.killsInStage, 0, StageConfig.ENEMIES_PER_STAGE - 1)
	-- Any boss below your highest stage must have been beaten (also fills this in for
	-- saves from before highestBossDefeated existed).
	local lastBossBelow = ((data.highestStage - 1) // BossConfig.BOSS_EVERY) * BossConfig.BOSS_EVERY
	data.highestBossDefeated = math.max(data.highestBossDefeated, lastBossBelow)
	CombatService.refreshArmy(player)
	encounters[player] = newEncounter(data.stage)
	if Formulas.isBossStage(data.stage) then
		data.killsInStage = 0
	end
	DataService.markChanged(player)
end

-- "Fight Boss" button: only valid when the very next stage is a boss.
local function fightBoss(player: Player)
	local data = DataService.get(player)
	local encounter = encounters[player]
	if data == nil or encounter == nil or encounter.kind == "Boss" then
		return
	end
	if not Formulas.isBossStage(data.stage + 1) then
		return
	end
	data.autoAdvance = true
	goToStage(player, data, data.stage + 1)
	DataService.markChanged(player)
end

local function setAutoAdvance(player: Player, enabled: boolean)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	data.autoAdvance = enabled
	DataService.markChanged(player)
end

function StageService.start()
	DataService.ProfileLoaded:Connect(onProfileLoaded)
	DataService.ProfileReleasing:Connect(function(player: Player)
		encounters[player] = nil
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		encounters[player] = nil
	end)

	RemoteService.onEvent(Remotes.Events.FightBoss, RateLimiter.new(3, 1), function(): boolean?
		return true -- takes no arguments
	end, function(player: Player, _payload: boolean)
		fightBoss(player)
	end)

	RemoteService.onEvent(Remotes.Events.SetAutoAdvance, RateLimiter.new(4, 2), function(enabled: unknown): boolean?
		return Validate.boolean(enabled)
	end, setAutoAdvance)

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

return StageService
