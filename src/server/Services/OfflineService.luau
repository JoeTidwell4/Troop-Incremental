--!strict
-- Offline earnings. While a player is away their army keeps farming the highest normal
-- stage they cleared this run, at reduced efficiency, up to a time cap.
--
-- "Last seen" is written by the server every SAVE_INTERVAL seconds and when the player
-- leaves, using server time (os.time), so clients can't fake how long they were gone.
-- The gold is added on join; the client just gets a "welcome back" message about it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local OfflineConfig = require(Shared:WaitForChild("Config"):WaitForChild("OfflineConfig"))
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local CombatService = require(Services.CombatService)
local ModifierService = require(Services.ModifierService)
local HonorService = require(Services.HonorService)
local SyncService = require(Services.SyncService)

type Notice = Types.Notice
type PlayerData = Types.PlayerData

-- Welcome-back messages waiting for the client to finish loading.
local pending: { [Player]: Notice } = {}

local OfflineService = {}

local function award(player: Player, data: PlayerData)
	local now = os.time()
	local lastSeen = data.lastSeen
	data.lastSeen = now
	if lastSeen <= 0 then
		return -- first ever session
	end

	local away = now - lastSeen
	if away < OfflineConfig.MIN_SECONDS then
		return
	end

	local bonusHours, bonusEfficiency = HonorService.getOfflineBonus(player)
	local skills = Formulas.skillEffects(data.skills.ranks) -- Field Camp, Supply Lines
	bonusHours += skills.offlineHours
	bonusEfficiency += skills.offlineEfficiency
	local capSeconds = (OfflineConfig.CAP_HOURS + bonusHours) * 3600
	local seconds = math.min(away, capSeconds)
	local efficiency = OfflineConfig.EFFICIENCY + bonusEfficiency

	-- Abilities are never active right after joining, so this is the permanent-bonus DPS.
	local dps = CombatService.getDps(player)
	local stage = Formulas.offlineStage(data.highestStage)
	local gold = Formulas.offlineGold(dps, ModifierService.get(player).gold, stage, seconds, efficiency)
	if BigNum.isZero(gold) then
		return
	end

	data.gold = BigNum.add(data.gold, gold)
	data.stats.lifetimeGold = BigNum.add(data.stats.lifetimeGold, gold)
	DataService.markChanged(player)
	local notice: Notice = {
		kind = "OfflineEarnings",
		stage = stage,
		seconds = seconds,
		awaySeconds = away,
		gold = gold,
	}
	-- The client may already be loaded (fast DataStore) or not yet (slow DataStore).
	if SyncService.isReady(player) then
		RemoteService.fireClient(Remotes.Events.Notice, player, notice)
	else
		pending[player] = notice
	end
end

function OfflineService.start()
	DataService.ProfileLoaded:Connect(function(player: Player, data: PlayerData)
		-- StageService builds the army on load; let it run first.
		task.defer(function()
			if DataService.get(player) ~= nil then
				award(player, data)
			end
		end)
	end)

	SyncService.ClientReady:Connect(function(player: Player)
		local notice = pending[player]
		if notice ~= nil then
			pending[player] = nil
			RemoteService.fireClient(Remotes.Events.Notice, player, notice)
		end
	end)

	DataService.ProfileReleasing:Connect(function(player: Player)
		local data = DataService.get(player)
		if data ~= nil then
			data.lastSeen = os.time()
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		pending[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(OfflineConfig.SAVE_INTERVAL)
			local now = os.time()
			for _, player in Players:GetPlayers() do
				local data = DataService.get(player)
				if data ~= nil then
					data.lastSeen = now
				end
			end
		end
	end)
end

return OfflineService
