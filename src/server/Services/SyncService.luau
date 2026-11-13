--!strict
-- Sends each player their own up-to-date state so the client can draw the screen.
-- Only players whose state changed get a message, at most once per SYNC_INTERVAL.
-- The client waits until its scripts are loaded, then fires ClientReady.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = Shared:WaitForChild("Config")
local CombatConfig = require(Config:WaitForChild("CombatConfig"))
local StageConfig = require(Config:WaitForChild("StageConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local CombatService = require(Services.CombatService)

type Snapshot = Types.Snapshot

local ready: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}

local SyncService = {}

local function buildSnapshot(player: Player): Snapshot?
	local data = DataService.get(player)
	local combat = CombatService.getState(player)
	if data == nil or combat == nil then
		return nil
	end
	return {
		gold = data.gold,
		stage = data.stage,
		highestStage = data.highestStage,
		killsInStage = data.killsInStage,
		enemiesPerStage = StageConfig.ENEMIES_PER_STAGE,
		enemyHp = combat.enemyHp,
		enemyMaxHp = combat.enemyMaxHp,
		goldPerKill = combat.goldPerKill,
		armyDps = combat.armyDps,
		tapDamage = combat.tapDamage,
		troops = table.clone(data.troops),
		totalKills = data.stats.totalKills,
	}
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
		ready[player] = true
		dirty[player] = true -- send a full snapshot right away
	end)

	task.spawn(function()
		while true do
			task.wait(CombatConfig.SYNC_INTERVAL)
			flush()
		end
	end)
end

return SyncService
