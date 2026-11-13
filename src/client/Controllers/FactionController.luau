--!strict
-- Client side of factions: asks the server to join/switch, and keeps the latest shared
-- war standings (WarSync). Display only; the server decides everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

type WarState = Types.WarState

local chooseRemote: RemoteFunction? = nil
local state: WarState? = nil
local receivedAt = 0

local FactionController = {
	-- Fires when new war standings arrive.
	WarChanged = Signal.new() :: Signal.Signal<WarState>,
}

function FactionController.getWar(): WarState?
	return state
end

-- Seconds left in the war, counted down locally since the last update.
function FactionController.warSecondsLeft(): number
	local current = state
	if current == nil then
		return 0
	end
	return math.max(0, current.secondsLeft - (os.clock() - receivedAt))
end

function FactionController.choose(factionId: string): Types.FactionResult
	local remote = chooseRemote
	if remote == nil then
		return { ok = false, reason = "NotReady" }
	end
	local ok, result = pcall(function(): any
		return remote:InvokeServer(factionId)
	end)
	if not ok or typeof(result) ~= "table" then
		return { ok = false, reason = "NoResponse" }
	end
	return result :: Types.FactionResult
end

function FactionController.start()
	chooseRemote = Remotes.waitForFunction(Remotes.Functions.ChooseFaction)
	Remotes.waitForEvent(Remotes.Events.WarSync).OnClientEvent:Connect(function(war: WarState)
		state = war
		receivedAt = os.clock()
		FactionController.WarChanged:Fire(war)
	end)
end

return FactionController
