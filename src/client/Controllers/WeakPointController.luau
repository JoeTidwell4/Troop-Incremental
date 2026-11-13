--!strict
-- Weak points (see WeakPointConfig / WeakPointService): forwards the server's spawn and
-- clear messages to the UI, and sends taps. The server decides whether a tap counts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

type WeakPointEvent = Types.WeakPointEvent
type WeakPointResult = Types.WeakPointResult

local hitRemote: RemoteFunction? = nil

local WeakPointController = {
	Spawned = Signal.new() :: Signal.Signal<WeakPointEvent>,
	Cleared = Signal.new() :: Signal.Signal<()>,
}

-- Tells the server this weak point was tapped. Yields for the answer.
function WeakPointController.hit(id: number): WeakPointResult
	local remote = hitRemote
	if remote == nil then
		return { ok = false, reason = "NotReady" }
	end
	local ok, result = pcall(function(): any
		return remote:InvokeServer(id)
	end)
	if ok and typeof(result) == "table" then
		return result :: WeakPointResult
	end
	return { ok = false, reason = "NoResponse" }
end

function WeakPointController.start()
	hitRemote = Remotes.waitForFunction(Remotes.Functions.HitWeakPoint)
	Remotes.waitForEvent(Remotes.Events.WeakPoint).OnClientEvent:Connect(function(event: WeakPointEvent)
		if event.kind == "Spawn" then
			WeakPointController.Spawned:Fire(event)
		else
			WeakPointController.Cleared:Fire()
		end
	end)
end

return WeakPointController
