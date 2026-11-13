--!strict
-- Picking and switching factions. The first pick is free; after that there's a
-- cooldown, and switching is locked near the end of each war so nobody can jump to the
-- winning side at the last minute. The faction's troop bonus is applied by
-- CombatService (via Formulas.factionTroopMultipliers), so changing faction refreshes
-- the army.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local FactionConfig = require(Shared:WaitForChild("Config"):WaitForChild("FactionConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local Validate = require(Server.Util.Validate)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local CombatService = require(Services.CombatService)
local WarService = require(Services.WarService)
local SyncService = require(Services.SyncService)
local Formulas = require(Shared:WaitForChild("Formulas"))

type FactionResult = Types.FactionResult
type PlayerData = Types.PlayerData

local REJECTED: FactionResult = { ok = false, reason = "Rejected" }

local FactionService = {}

-- Seconds until this player may switch faction (0 = allowed now). First pick is always 0.
function FactionService.switchAvailableIn(data: PlayerData): number
	if data.faction == "" then
		return 0
	end
	local cooldownLeft = data.factionChangedAt + FactionConfig.SWITCH_COOLDOWN - os.time()
	local lockLeft = if WarService.isSwitchLocked() then WarService.secondsLeft() else 0
	return math.max(0, cooldownLeft, lockLeft)
end

local function choose(player: Player, factionId: string): FactionResult
	local data = DataService.get(player)
	if data == nil then
		return { ok = false, reason = "NotLoaded" }
	end
	if data.faction == factionId then
		return { ok = false, reason = "AlreadyInFaction" }
	end
	if FactionService.switchAvailableIn(data) > 0 then
		return { ok = false, reason = if WarService.isSwitchLocked() then "WarLocked" else "OnCooldown" }
	end

	data.faction = factionId
	data.factionChangedAt = os.time()
	WarService.onFactionChanged(player)
	CombatService.refreshArmy(player)
	DataService.markChanged(player)
	return { ok = true }
end

function FactionService.start()
	SyncService.addSnapshotFields(function(_player: Player, data: PlayerData): { [string]: any }
		local current = data.war.weekId == Formulas.warWeek(os.time())
		local today = current and data.war.dayId == Formulas.warDay(os.time())
		return {
			faction = data.faction,
			factionSwitchIn = FactionService.switchAvailableIn(data),
			warPoints = if current then data.war.points else 0,
			warDayPoints = if today then data.war.dayPoints else 0,
			warActive = current and data.war.active,
			warBonusActive = WarService.hasWinnerBonus(data),
		}
	end)

	local limiter = RateLimiter.new(FactionConfig.REQUESTS_BURST, FactionConfig.REQUESTS_PER_SECOND)
	RemoteService.onInvoke(Remotes.Functions.ChooseFaction, limiter, function(factionId: unknown): string?
		return Validate.keyOf(factionId, FactionConfig.FACTIONS)
	end, choose, REJECTED)
end

return FactionService
