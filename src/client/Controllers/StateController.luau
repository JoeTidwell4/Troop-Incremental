--!strict
-- Holds the latest state the server sent us. Everything on the client reads from here.
-- This is display data only. Changing it locally does nothing to the real game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

type Snapshot = Types.Snapshot

local current: Snapshot? = nil

local StateController = {
	-- Fires with (newSnapshot, previousSnapshot or nil).
	Changed = Signal.new() :: Signal.Signal<Snapshot, Snapshot?>,
}

function StateController.get(): Snapshot?
	return current
end

function StateController.start()
	Remotes.waitForEvent(Remotes.Events.StateSync).OnClientEvent:Connect(function(snapshot: Snapshot)
		local previous = current
		current = snapshot
		StateController.Changed:Fire(snapshot, previous)
	end)

	-- Tell the server we're listening, so it sends our first snapshot.
	Remotes.waitForEvent(Remotes.Events.ClientReady):FireServer()
end

return StateController
