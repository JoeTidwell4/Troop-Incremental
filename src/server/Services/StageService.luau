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
--
-- Raid attacks (clan raid, see RaidService): a timed fight against the clan raid boss.
-- Normal progress pauses, the boss doesn't hit back, no gold or kills; damage is totalled
-- and handed to RaidService through RaidFinished. Then the normal fight resumes.
--
-- Tower floors (TowerService): a boss fight (kind "Boss", `tower` = the floor) on top of
-- the run, like a raid: the saved stage doesn't move, no gold, no kills counted, no
-- weakening. Its HP, timer and laws come from Formulas.towerFloor. The result goes out on
-- TowerFinished and the normal fight resumes.

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
local TowerConfig = require(Config:WaitForChild("TowerConfig"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local RateLimiter = require(Server.Util.RateLimiter)
local Validate = require(Server.Util.Validate)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local CombatService = require(Services.CombatService)
local ModifierService = require(Services.ModifierService)
local Areas = require(Shared:WaitForChild("Areas"))

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
	raidDamage: BigNum, -- raid attacks only: damage dealt so far
	-- Boss moves (see BossConfig / AreaConfig.bossMoves):
	moves: { [string]: boolean },
	enraged: boolean,
	shieldUntil: number, -- server time; troops can't hurt the boss until then
	nextShieldAt: number,
	minionHp: BigNum, -- summoned minions soak damage before the boss takes any
	minionMaxHp: BigNum,
	summoned: boolean,
	introUntil: number, -- bosses: no damage either way until then (entrance)
	weakened: number, -- bosses: HP taken off for failed attempts (0..WEAKEN_MAX)
	raidBoss: string, -- raids: which RaidConfig.BOSSES boss ("" otherwise)
	golden: boolean, -- normal stages: the current enemy is a golden one (StageConfig.GOLDEN_*)
	tower: number, -- Tower fights: the floor (0 otherwise)
}

local encounters: { [Player]: Encounter } = {}
local random = Random.new()

local StageService = {
	-- Fires when a boss is beaten: (player, bossStage, firstClear).
	-- firstClear is true the first time the player ever beats that boss stage.
	BossDefeated = Signal.new() :: Signal.Signal<Player, number, boolean>,
	-- Fires whenever enemies die: (player, stage, kills, wasBoss). Used for war points.
	Killed = Signal.new() :: Signal.Signal<Player, number, number, boolean>,
	-- Fires when a boss fight begins: (player, bossStage). Used for analytics.
	BossStarted = Signal.new() :: Signal.Signal<Player, number>,
	-- Fires when a boss fight is lost: (player, bossStage, "OutOfTime" | "ArmyDefeated").
	BossFailed = Signal.new() :: Signal.Signal<Player, number, string>,
	-- Fires when a golden enemy dies (quests, achievements, sounds).
	GoldenKilled = Signal.new() :: Signal.Signal<Player>,
	-- Fires when a raid attack ends (time up, cap reached, or leaving): (player, damage).
	RaidFinished = Signal.new() :: Signal.Signal<Player, BigNum>,
	-- Fires when a Tower fight ends: (player, floor, won, reason "" | "OutOfTime" |
	-- "ArmyDefeated" | "Left").
	TowerFinished = Signal.new() :: Signal.Signal<Player, number, boolean, string>,
}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function noMoves(): { [string]: boolean }
	return {}
end

-- How much HP a boss has lost to the player's failed attempts in a row on it.
local function weakenFor(data: PlayerData?, stage: number): number
	if data == nil or data.bossWeaken.stage ~= stage then
		return 0
	end
	return math.min(data.bossWeaken.fails * BossConfig.WEAKEN_PER_FAIL, BossConfig.WEAKEN_MAX)
end

local function newEncounter(stage: number, data: PlayerData?): Encounter
	if Formulas.isBossStage(stage) then
		local weakened = weakenFor(data, stage)
		-- Challenge rules (Tyrants: every move + more HP; Against the Clock: less time).
		local rules = Formulas.challengeRules(if data ~= nil then data.challenge.active else nil)
		local hp = BigNum.round(BigNum.mulNumber(Formulas.bossHp(stage), (1 - weakened) * (rules.bossHpScale or 1)))
		local moves: { [string]: boolean } = {}
		for _, move in Areas.forStage(stage).theme.bossMoves do
			moves[move] = true
		end
		if rules.allBossMoves then
			moves.Enrage = true
			moves.Shield = true
			moves.Summon = true
		end
		local bossTime = BossConfig.BOSS_TIME_LIMIT
		if data ~= nil then
			local ranks, generals, relics = Formulas.fightBuild(data.challenge.active, data.skills.ranks, data.generals, data.relics)
			bossTime += Formulas.extras(ranks, generals, relics).bossTime + Formulas.challengeBonuses(data.challenge.tiers).bossTime
		end
		bossTime *= rules.bossTimeScale or 1
		local introUntil = now() + BossConfig.INTRO_SECONDS
		return {
			moves = moves,
			enraged = false,
			shieldUntil = 0,
			nextShieldAt = if moves.Shield then introUntil + BossConfig.SHIELD_EVERY else math.huge,
			introUntil = introUntil,
			weakened = weakened,
			raidBoss = "",
			minionHp = BigNum.ZERO,
			minionMaxHp = BigNum.ZERO,
			summoned = false,
			golden = false,
			tower = 0,
			kind = "Boss",
			enemyHp = hp,
			enemyMaxHp = hp,
			goldPerKill = Formulas.bossGold(stage),
			bossEndsAt = introUntil + bossTime,
			bossDps = Formulas.bossDps(stage),
			armyDamageTaken = BigNum.ZERO,
			raidDamage = BigNum.ZERO,
		}
	end
	local hp = Formulas.enemyHp(stage)
	return {
		moves = noMoves(),
		enraged = false,
		shieldUntil = 0,
		nextShieldAt = math.huge,
		introUntil = 0,
		weakened = 0,
		raidBoss = "",
		minionHp = BigNum.ZERO,
		minionMaxHp = BigNum.ZERO,
		summoned = false,
		golden = false,
		tower = 0,
		kind = "Normal",
		enemyHp = hp,
		enemyMaxHp = hp,
		goldPerKill = Formulas.goldPerKill(stage),
		bossEndsAt = 0,
		bossDps = BigNum.ZERO,
		armyDamageTaken = BigNum.ZERO,
		raidDamage = BigNum.ZERO,
	}
end

local function notify(player: Player, notice: Notice)
	RemoteService.fireClient(Remotes.Events.Notice, player, notice)
end

-- Read-only view for SyncService.
function StageService.getEncounter(player: Player): Encounter?
	return encounters[player]
end

-- Damage per second the current boss deals to the army: its stage damage kept between
-- ARMY_DAMAGE_MIN/MAX_FRACTION of the army's max HP, then doubled if enraged.
function StageService.getBossHitRate(player: Player): BigNum
	local encounter = encounters[player]
	if encounter == nil or encounter.kind ~= "Boss" then
		return BigNum.ZERO
	end
	local maxHp = CombatService.getMaxHp(player)
	local low = BigNum.mulNumber(maxHp, BossConfig.ARMY_DAMAGE_MIN_FRACTION)
	local high = BigNum.mulNumber(maxHp, BossConfig.ARMY_DAMAGE_MAX_FRACTION)
	local rate = BigNum.min(BigNum.max(encounter.bossDps, low), high)
	if encounter.enraged then
		rate = BigNum.mulNumber(rate, BossConfig.ENRAGE_MULTIPLIER)
	end
	if encounter.tower > 0 then
		rate = BigNum.mulNumber(rate, Formulas.towerFloor(encounter.tower).effects.bossDamage) -- Frenzied
	end
	return BigNum.mulNumber(rate, ModifierService.get(player).bossDamage) -- Shield Wall
end

-- Fortify: heals the army by `fraction` of its max HP. Boss fights only; false otherwise.
function StageService.healArmy(player: Player, fraction: number): boolean
	local encounter = encounters[player]
	if encounter == nil or encounter.kind ~= "Boss" then
		return false
	end
	local heal = BigNum.mulNumber(CombatService.getMaxHp(player), fraction)
	encounter.armyDamageTaken = BigNum.max(BigNum.sub(encounter.armyDamageTaken, heal), BigNum.ZERO)
	DataService.markChanged(player)
	return true
end

-- Bounty: AbilityService sets this. Given the kills about to be paid, returns how many
-- extra kills' worth of gold to add (and uses up bounty charges).
StageService.bountyHook = nil :: ((player: Player, kills: number) -> number)?

-- Current army HP (only drops during boss fights).
function StageService.getArmyHp(player: Player): BigNum
	local maxHp = CombatService.getMaxHp(player)
	local encounter = encounters[player]
	if encounter == nil then
		return maxHp
	end
	return BigNum.sub(maxHp, encounter.armyDamageTaken)
end

-- Sets the player's current fight and tells CombatService what it's up against (area
-- traits and boss-vs-normal troop bonuses depend on it).
local function setEncounter(player: Player, data: PlayerData, encounter: Encounter)
	encounters[player] = encounter
	CombatService.setFightContext(player, data.stage, encounter.kind ~= "Normal", encounter.tower)
	if encounter.kind == "Boss" and encounter.tower == 0 then
		StageService.BossStarted:Fire(player, data.stage)
	end
end

local function goToStage(player: Player, data: PlayerData, stage: number)
	data.stage = math.max(1, stage)
	data.killsInStage = 0
	data.highestStage = math.max(data.highestStage, data.stage)
	data.bestStage = math.max(data.bestStage, data.highestStage)
	setEncounter(player, data, newEncounter(data.stage, data))
end

-- Ends a raid attack: reports the damage and goes back to the normal fight.
local function finishRaid(player: Player, data: PlayerData)
	local encounter = encounters[player]
	if encounter == nil or encounter.kind ~= "Raid" then
		return
	end
	setEncounter(player, data, newEncounter(data.stage, data))
	StageService.RaidFinished:Fire(player, encounter.raidDamage)
end

-- Ends a Tower fight (if one is on): back to the normal fight, then reports the result.
local function finishTower(player: Player, data: PlayerData, won: boolean, reason: string)
	local encounter = encounters[player]
	if encounter == nil or encounter.tower == 0 then
		return
	end
	local floor = encounter.tower
	setEncounter(player, data, newEncounter(data.stage, data))
	StageService.TowerFinished:Fire(player, floor, won, reason)
end

-- Starts the fight against Tower floor `floor`. Only from a normal stage.
function StageService.startTower(player: Player, floor: number): boolean
	local encounter = encounters[player]
	local data = DataService.get(player)
	if encounter == nil or data == nil or encounter.kind ~= "Normal" then
		return false
	end
	local info = Formulas.towerFloor(floor)
	local hp = Formulas.towerHp(floor)
	local moves: { [string]: boolean } = {}
	if info.guardian then
		moves.Enrage = true
		moves.Shield = true
		moves.Summon = true
	end
	local ranks, generals, relics = Formulas.fightBuild(data.challenge.active, data.skills.ranks, data.generals, data.relics)
	local seconds = (TowerConfig.TIME_LIMIT + Formulas.extras(ranks, generals, relics).bossTime + Formulas.challengeBonuses(data.challenge.tiers).bossTime)
		* info.effects.timeScale
	local introUntil = now() + TowerConfig.INTRO_SECONDS
	setEncounter(player, data, {
		moves = moves,
		enraged = false,
		shieldUntil = 0,
		nextShieldAt = if moves.Shield then introUntil + BossConfig.SHIELD_EVERY else math.huge,
		introUntil = introUntil,
		weakened = 0,
		raidBoss = "",
		minionHp = BigNum.ZERO,
		minionMaxHp = BigNum.ZERO,
		summoned = false,
		golden = false,
		tower = floor,
		kind = "Boss",
		enemyHp = hp,
		enemyMaxHp = hp,
		goldPerKill = BigNum.ZERO,
		bossEndsAt = introUntil + seconds,
		bossDps = Formulas.towerDps(floor),
		armyDamageTaken = BigNum.ZERO,
		raidDamage = BigNum.ZERO,
	})
	DataService.markChanged(player)
	return true
end

-- Walks out of a Tower fight (counts as a loss with reason "Left"). False if not in one.
function StageService.leaveTower(player: Player): boolean
	local encounter = encounters[player]
	local data = DataService.get(player)
	if encounter == nil or data == nil or encounter.tower == 0 then
		return false
	end
	finishTower(player, data, false, "Left")
	DataService.markChanged(player)
	return true
end

-- Starts a raid attack lasting `seconds`. The HP bar is sized so emptying it means you hit
-- the per-attack unit cap (`maxDamage`), which also ends the attack early.
function StageService.startRaid(player: Player, seconds: number, maxDamage: BigNum, bossId: string): boolean
	local encounter = encounters[player]
	local data = DataService.get(player)
	if encounter == nil or data == nil or encounter.kind ~= "Normal" then
		return false
	end
	setEncounter(player, data, {
		moves = noMoves(),
		enraged = false,
		shieldUntil = 0,
		nextShieldAt = math.huge,
		introUntil = 0,
		weakened = 0,
		raidBoss = bossId,
		minionHp = BigNum.ZERO,
		minionMaxHp = BigNum.ZERO,
		summoned = false,
		golden = false,
		tower = 0,
		kind = "Raid",
		enemyHp = maxDamage,
		enemyMaxHp = maxDamage,
		goldPerKill = BigNum.ZERO,
		bossEndsAt = now() + seconds,
		bossDps = BigNum.ZERO,
		armyDamageTaken = BigNum.ZERO,
		raidDamage = BigNum.ZERO,
	})
	DataService.markChanged(player)
	return true
end

-- Starts a fresh fight from the player's current saved stage (used after Ascending).
function StageService.restart(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	finishRaid(player, data) -- an Ascend mid-raid still counts the damage dealt
	finishTower(player, data, false, "Left") -- a Tower fight is simply abandoned
	CombatService.refreshArmy(player)
	setEncounter(player, data, newEncounter(data.stage, data))
	DataService.markChanged(player)
end

local function failBoss(player: Player, data: PlayerData, reason: "OutOfTime" | "ArmyDefeated")
	local current = encounters[player]
	if current ~= nil and current.tower > 0 then
		finishTower(player, data, false, reason) -- no penalty: just back to the run
		return
	end
	local bossStage = data.stage
	-- Failing again on the same boss weakens it for the next try.
	if data.bossWeaken.stage == bossStage then
		data.bossWeaken.fails += 1
	else
		data.bossWeaken.stage = bossStage
		data.bossWeaken.fails = 1
	end
	data.autoAdvance = false
	goToStage(player, data, bossStage - 1)
	notify(player, { kind = "BossFailed", stage = bossStage, reason = reason })
	StageService.BossFailed:Fire(player, bossStage, reason)
end

local function onStageCleared(player: Player, data: PlayerData, encounter: Encounter)
	if encounter.kind == "Boss" then
		local bossStage = data.stage
		if data.bossWeaken.stage == bossStage then
			data.bossWeaken.fails = 0
		end
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
	if encounter.kind == "Raid" then
		-- Raid: no kills or gold, just total the damage. Hitting the cap ends the attack.
		local counted = BigNum.min(damage, encounter.enemyHp)
		encounter.raidDamage = BigNum.add(encounter.raidDamage, counted)
		encounter.enemyHp = BigNum.sub(encounter.enemyHp, counted)
		if BigNum.isZero(encounter.enemyHp) then
			finishRaid(player, data)
		end
		return true
	end
	local goldMultiplier = ModifierService.get(player).gold
	local ranks, generals, relics = Formulas.fightBuild(data.challenge.active, data.skills.ranks, data.generals, data.relics)
	local skills = Formulas.skillEffects(ranks)
	if encounter.kind == "Boss" then
		goldMultiplier *= 1 + skills.bossGold -- War Profits
	end
	local enemiesThisStage = if encounter.kind == "Boss" then 1 else StageConfig.ENEMIES_PER_STAGE

	-- Summoned minions take the hits until they're all down.
	if not BigNum.isZero(encounter.minionHp) then
		if BigNum.lt(damage, encounter.minionHp) then
			encounter.minionHp = BigNum.sub(encounter.minionHp, damage)
			return true
		end
		damage = BigNum.sub(damage, encounter.minionHp)
		encounter.minionHp = BigNum.ZERO
		if BigNum.isZero(damage) then
			return true
		end
	end

	if BigNum.lt(damage, encounter.enemyHp) then
		encounter.enemyHp = BigNum.sub(encounter.enemyHp, damage)
		-- Summon: once, when the boss drops below SUMMON_AT_FRACTION of its HP.
		local summonAt = BigNum.mulNumber(encounter.enemyMaxHp, BossConfig.SUMMON_AT_FRACTION)
		if encounter.moves.Summon and not encounter.summoned and BigNum.lt(encounter.enemyHp, summonAt) then
			encounter.summoned = true
			encounter.minionMaxHp = BigNum.mulNumber(encounter.enemyMaxHp, BossConfig.SUMMON_HP_FRACTION)
			encounter.minionHp = encounter.minionMaxHp
		end
		return true
	end

	if encounter.tower > 0 then
		-- A Tower floor falls: no gold or stage progress. (The kill is counted so the
		-- client plays the boss's death, not a retreat.)
		data.stats.totalKills += 1
		finishTower(player, data, true, "")
		return true
	end

	-- Current enemy dies. Leftover damage can kill more enemies on the same stage.
	damage = BigNum.sub(damage, encounter.enemyHp)
	local enemiesLeft = enemiesThisStage - data.killsInStage - 1
	local extraKills = 0
	if enemiesLeft > 0 then
		-- (the next enemies are normal ones, even if the one that just died was golden)
		local perEnemy = Formulas.enemyHp(data.stage)
		local fullKills = math.floor(BigNum.toNumber(BigNum.div(damage, perEnemy)))
		extraKills = math.min(fullKills, enemiesLeft)
		damage = BigNum.sub(damage, BigNum.mulNumber(perEnemy, extraKills))
	end

	local kills = 1 + extraKills
	local wasGolden = encounter.golden
	-- Gold is paid in "kills' worth": a golden enemy is worth GOLDEN_GOLD_KILLS on its own.
	local goldenKills = StageConfig.GOLDEN_GOLD_KILLS * (1 + skills.goldenGold) -- Midas
	local goldKills = kills + (if wasGolden then goldenKills - 1 else 0)
	local hook = StageService.bountyHook
	if hook ~= nil and encounter.kind == "Normal" then
		goldKills += hook(player, kills)
	end
	local gold = BigNum.mulNumber(encounter.goldPerKill, goldKills * goldMultiplier)
	data.gold = BigNum.add(data.gold, gold)
	data.stats.lifetimeGold = BigNum.add(data.stats.lifetimeGold, gold)
	data.stats.totalKills += kills
	data.killsInStage += kills
	StageService.Killed:Fire(player, data.stage, kills, encounter.kind == "Boss")
	if wasGolden then
		local pack = random:NextNumber() < StageConfig.GOLDEN_PACK_CHANCE
		if pack then
			data.packs.free += 1
		end
		notify(player, { kind = "Golden", stage = data.stage, gold = gold, packs = if pack then 1 else 0 })
		StageService.GoldenKilled:Fire(player)
	end

	if data.killsInStage >= enemiesThisStage then
		-- At most one stage clear per tick: leftover damage is discarded so a huge
		-- spike (e.g. Barrage) can't skip many stages at once.
		onStageCleared(player, data, encounter)
	else
		-- The next enemy: sometimes a golden one (tougher, much richer).
		local baseHp = Formulas.enemyHp(data.stage)
		local goldenChance = StageConfig.GOLDEN_CHANCE * (1 + Formulas.extras(ranks, generals, relics).goldenChance)
		encounter.golden = encounter.kind == "Normal" and random:NextNumber() < goldenChance
		encounter.enemyMaxHp = if encounter.golden then BigNum.mulNumber(baseHp, StageConfig.GOLDEN_HP_MULTIPLIER) else baseHp
		encounter.enemyHp = BigNum.max(BigNum.sub(encounter.enemyMaxHp, damage), BigNum.ONE)
	end
	return true
end

-- Boss attacks the army and the clock ticks. Returns true if anything changed.
local function updateBoss(player: Player, data: PlayerData, dt: number): boolean
	local encounter = encounters[player]
	if encounter ~= nil and encounter.kind == "Raid" then
		if now() >= encounter.bossEndsAt then
			finishRaid(player, data)
		end
		return true
	end
	if encounter == nil or encounter.kind ~= "Boss" then
		return false
	end
	local time = now()
	-- Shield: up for SHIELD_SECONDS every SHIELD_EVERY seconds.
	if encounter.moves.Shield and time >= encounter.nextShieldAt then
		encounter.shieldUntil = time + BossConfig.SHIELD_SECONDS
		encounter.nextShieldAt = time + BossConfig.SHIELD_EVERY
	end
	-- Enrage: hits harder once low on HP.
	local enrageAt = BigNum.mulNumber(encounter.enemyMaxHp, BossConfig.ENRAGE_HP_FRACTION)
	encounter.enraged = encounter.moves.Enrage == true and BigNum.lt(encounter.enemyHp, enrageAt)
	if time < encounter.introUntil then
		return true -- still making its entrance: no hits yet
	end
	-- Tower law Regenerating: the boss heals a share of its max HP every second.
	if encounter.tower > 0 then
		local regen = Formulas.towerFloor(encounter.tower).effects.regen
		if regen > 0 then
			local healed = BigNum.add(encounter.enemyHp, BigNum.mulNumber(encounter.enemyMaxHp, regen * dt))
			encounter.enemyHp = BigNum.min(healed, encounter.enemyMaxHp)
		end
	end
	encounter.armyDamageTaken = BigNum.add(encounter.armyDamageTaken, BigNum.mulNumber(StageService.getBossHitRate(player), dt))
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
			local current = encounters[player]
			local shielded = current ~= nil and current.kind == "Boss" and now() < current.shieldUntil
			local damage: BigNum
			if current ~= nil and current.kind == "Raid" then
				-- This week's raid boss changes how troops vs clicks/abilities count.
				local boss = Formulas.raidBossById(current.raidBoss)
				damage = CombatService.takeDamage(player, dt, false, boss.troopMultiplier, boss.queuedMultiplier)
			elseif current ~= nil and current.tower > 0 then
				-- Tower laws can change how troops vs clicks/abilities count (Thick Hide).
				local effects = Formulas.towerFloor(current.tower).effects
				damage = CombatService.takeDamage(player, dt, shielded, effects.troopMultiplier, effects.queuedMultiplier)
			else
				damage = CombatService.takeDamage(player, dt, shielded)
			end
			if current ~= nil and current.kind == "Boss" then
				if now() < current.introUntil then
					damage = BigNum.ZERO -- making its entrance
				else
					-- Bosses lose at most MAX_DAMAGE_PER_SECOND_FRACTION of their HP per second
					-- (Tower floors have their own, higher limit).
					local fraction = if current.tower > 0
						then TowerConfig.MAX_DAMAGE_PER_SECOND_FRACTION
						else BossConfig.MAX_DAMAGE_PER_SECOND_FRACTION
					damage = BigNum.min(damage, BigNum.mulNumber(current.enemyMaxHp, fraction * dt))
				end
			end
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
	setEncounter(player, data, newEncounter(data.stage, data))
	if Formulas.isBossStage(data.stage) then
		data.killsInStage = 0
	end
	DataService.markChanged(player)
end

-- "Fight Boss" button: only valid when the very next stage is a boss.
local function fightBoss(player: Player)
	local data = DataService.get(player)
	local encounter = encounters[player]
	if data == nil or encounter == nil or encounter.kind ~= "Normal" then
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

---------------------------------------------------------------- Studio test panel (DebugService only)

-- Kills the current enemy (or boss, minions included) right now, ignoring the boss
-- damage cap and the entrance.
function StageService.debugKill(player: Player)
	local data = DataService.get(player)
	local encounter = encounters[player]
	if data == nil or encounter == nil then
		return
	end
	encounter.introUntil = 0
	applyDamage(player, data, BigNum.add(encounter.enemyHp, encounter.minionHp))
	DataService.markChanged(player)
end

-- Turns the current normal enemy into a golden one.
function StageService.debugGolden(player: Player): boolean
	local data = DataService.get(player)
	local encounter = encounters[player]
	if data == nil or encounter == nil or encounter.kind ~= "Normal" then
		return false
	end
	encounter.golden = true
	encounter.enemyMaxHp = BigNum.mulNumber(Formulas.enemyHp(data.stage), StageConfig.GOLDEN_HP_MULTIPLIER)
	encounter.enemyHp = encounter.enemyMaxHp
	DataService.markChanged(player)
	return true
end

-- Loses the current boss fight as if the timer ran out.
function StageService.debugFailBoss(player: Player): boolean
	local data = DataService.get(player)
	local encounter = encounters[player]
	if data == nil or encounter == nil or encounter.kind ~= "Boss" then
		return false
	end
	failBoss(player, data, "OutOfTime")
	return true
end

function StageService.start()
	DataService.ProfileLoaded:Connect(onProfileLoaded)
	DataService.ProfileReleasing:Connect(function(player: Player)
		-- Leaving mid-raid still counts the damage dealt so far.
		local data = DataService.get(player)
		if data ~= nil then
			finishRaid(player, data)
		end
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
