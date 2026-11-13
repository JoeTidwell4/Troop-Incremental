--!strict
-- One place that hears "the player did something": killed enemies, beat a boss, used an
-- ability, trained troops, upgraded gear, opened a pack, earned war points, raided,
-- donated. It keeps lifetime counters in the save (for achievements) and fires
-- `Recorded` (for daily quests).
--
-- Other services call ActivityService.record(player, activity, amount); kills and boss
-- wins are picked up from StageService's signals.
--
-- Activities: "Kill", "BossWin", "Ability", "TroopBuy", "GearUpgrade", "PackOpen",
-- "WarPoints", "RaidAttack", "Donate".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local DataService = require(Services.DataService)
local StageService = require(Services.StageService)

local ActivityService = {
	-- Fires after every recorded activity: (player, activity, amount).
	Recorded = Signal.new() :: Signal.Signal<Player, string, number>,
}

function ActivityService.record(player: Player, activity: string, amount: number)
	if amount <= 0 then
		return
	end
	local data = DataService.get(player)
	if data == nil then
		return
	end
	data.lifetime[activity] = (data.lifetime[activity] or 0) + amount
	ActivityService.Recorded:Fire(player, activity, amount)
end

function ActivityService.start()
	StageService.Killed:Connect(function(player: Player, _stage: number, kills: number, _wasBoss: boolean)
		ActivityService.record(player, "Kill", kills)
	end)
	StageService.GoldenKilled:Connect(function(player: Player)
		ActivityService.record(player, "GoldenKill", 1)
	end)
	StageService.BossDefeated:Connect(function(player: Player, _stage: number, _firstClear: boolean)
		ActivityService.record(player, "BossWin", 1)
	end)
end

return ActivityService
