--!strict
-- Sends each player their own up-to-date state so the client can draw the screen.
-- Only players whose state changed get a message, at most once per SYNC_INTERVAL.
-- The client waits until its scripts are loaded, then fires ClientReady.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = Shared:WaitForChild("Config")
local CombatConfig = require(Config:WaitForChild("CombatConfig"))
local StageConfig = require(Config:WaitForChild("StageConfig"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local RateLimiter = require(Server.Util.RateLimiter)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local CombatService = require(Services.CombatService)
local StageService = require(Services.StageService)
local AbilityService = require(Services.AbilityService)
local ModifierService = require(Services.ModifierService)

type Snapshot = Types.Snapshot

local ready: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}

local SyncService = {
	-- Fires once a player's client has loaded its scripts and can receive messages.
	ClientReady = Signal.new() :: Signal.Signal<Player>,
}

function SyncService.isReady(player: Player): boolean
	return ready[player] == true
end

-- Extra snapshot fields from services that themselves depend on SyncService (faction/war).
-- They register here instead of SyncService requiring them, which would be a require loop.
type ExtraFields = (player: Player, data: Types.PlayerData) -> { [string]: any }
local extraProviders: { ExtraFields } = {}

function SyncService.addSnapshotFields(provider: ExtraFields)
	table.insert(extraProviders, provider)
end

local function buildSnapshot(player: Player): Snapshot?
	local data = DataService.get(player)
	local encounter = StageService.getEncounter(player)
	if data == nil or encounter == nil then
		return nil
	end
	local modifiers = ModifierService.get(player)
	local snapshot: Snapshot = {
		gold = data.gold,
		stage = data.stage,
		highestStage = data.highestStage,
		bestStage = data.bestStage,
		killsInStage = data.killsInStage,
		enemiesPerStage = if encounter.kind == "Normal" then StageConfig.ENEMIES_PER_STAGE else 1,
		autoAdvance = data.autoAdvance,

		encounter = encounter.kind,
		enemyHp = encounter.enemyHp,
		enemyMaxHp = encounter.enemyMaxHp,
		goldPerKill = BigNum.mulNumber(encounter.goldPerKill, modifiers.gold),
		bossEndsAt = encounter.bossEndsAt,
		bossDps = StageService.getBossHitRate(player),
		bossIntroUntil = encounter.introUntil,
		bossWeakened = encounter.weakened,
		bossEnraged = encounter.enraged,
		bossShieldUntil = encounter.shieldUntil,
		minionHp = encounter.minionHp,
		minionMaxHp = encounter.minionMaxHp,
		enemyGolden = encounter.golden,

		armyDps = CombatService.getDps(player),
		tapDamage = CombatService.getTapDamage(player),
		armyHp = StageService.getArmyHp(player),
		armyMaxHp = CombatService.getMaxHp(player),
		damageMultiplier = modifiers.damage,
		goldMultiplier = modifiers.gold,

		troops = table.clone(data.troops),
		gear = data.gear,
		packs = data.packs,
		packPrice = Formulas.packPrice(data.highestStage),
		abilities = AbilityService.getTimers(player),
		abilityLoadout = table.clone(data.abilityLoadout),
		bountyLeft = AbilityService.getBountyLeft(player),
		totalKills = data.stats.totalKills,

		honor = data.honor,
		honorUpgrades = data.honorUpgrades,
		abilityUpgrades = data.abilityUpgrades,
		ascendHonor = Formulas.ascendHonor(data.highestStage, data.legacy.upgrades),
		ascensions = data.stats.ascensions,

		-- Filled in by FactionService below; defaults keep the shape complete.
		faction = data.faction,
		factionSwitchIn = 0,
		warPoints = 0,
		warDayPoints = 0,
		warActive = false,
		warBonusActive = false,
		raidAttacksLeft = 0,
		raidUnitsWeek = 0,
		raidUnitsLive = 0,
		raidBossId = encounter.raidBoss,
		passToggles = table.clone(data.passToggles),
		settings = {}, -- filled in by SettingsService
		commander = { owned = {}, equipped = {}, pity = {} }, -- filled in by CommanderService
		clanTokens = data.clanTokens,
	}
	for _, provider in extraProviders do
		for key, value in provider(player, data) do
			(snapshot :: any)[key] = value
		end
	end
	return snapshot
end

local function flush()
	for player in dirty do
		if ready[player] then
			local snapshot = buildSnapshot(player)
			if snapshot ~= nil then
				RemoteService.fireClient(Remotes.Events.StateSync, player, snapshot)
				dirty[player] = nil
			end
		end
	end
end

function SyncService.start()
	DataService.Changed:Connect(function(player: Player)
		dirty[player] = true
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		ready[player] = nil
		dirty[player] = nil
	end)

	local readyLimiter = RateLimiter.new(3, 1)
	RemoteService.onEvent(Remotes.Events.ClientReady, readyLimiter, function(): boolean?
		return true -- takes no arguments
	end, function(player: Player, _payload: boolean)
		local firstTime = not ready[player]
		ready[player] = true
		dirty[player] = true -- send a full snapshot right away
		if firstTime then
			SyncService.ClientReady:Fire(player)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(CombatConfig.SYNC_INTERVAL)
			flush()
		end
	end)
end

return SyncService
