--!strict
-- Client side of stage controls: the Fight Boss button and the auto-advance toggle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local fightBossRemote: RemoteEvent? = nil
local autoAdvanceRemote: RemoteEvent? = nil

local BattleController = {}

function BattleController.start()
	fightBossRemote = Remotes.waitForEvent(Remotes.Events.FightBoss)
	autoAdvanceRemote = Remotes.waitForEvent(Remotes.Events.SetAutoAdvance)
end

function BattleController.fightBoss()
	if fightBossRemote ~= nil then
		fightBossRemote:FireServer()
	end
end

function BattleController.setAutoAdvance(enabled: boolean)
	if autoAdvanceRemote ~= nil then
		autoAdvanceRemote:FireServer(enabled)
	end
end

return BattleController
