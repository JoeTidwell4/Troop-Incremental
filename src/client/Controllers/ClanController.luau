--!strict
-- Client side of clans: sends requests (create, join, donate, ...) and keeps the latest
-- clan view the server sent (ClanSync). Display only; the server decides everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

type ClanView = Types.ClanView
type RaidView = Types.RaidView
type ClanResult = Types.ClanResult
type ClanWarView = Types.ClanWarView

local requestRemote: RemoteFunction? = nil
local view: ClanView? = nil
local raid: RaidView? = nil
local raidReceivedAt = 0
local war: ClanWarView? = nil
local warReceivedAt = 0

local ClanController = {
	Changed = Signal.new() :: Signal.Signal<ClanView>,
	RaidChanged = Signal.new() :: Signal.Signal<RaidView>,
	WarChanged = Signal.new() :: Signal.Signal<ClanWarView>,
}

-- This week's Clan War standings (ClanWarSync), or nil before the first update.
function ClanController.getWar(): ClanWarView?
	return war
end

-- Seconds left in the Clan War week, counted down locally since the last update.
function ClanController.warSecondsLeft(): number
	local current = war
	if current == nil then
		return 0
	end
	return math.max(0, current.secondsLeft - (os.clock() - warReceivedAt))
end

function ClanController.get(): ClanView?
	return view
end

function ClanController.getRaid(): RaidView?
	return raid
end

-- Seconds left in the raid week, counted down locally since the last update.
function ClanController.raidSecondsLeft(): number
	local current = raid
	if current == nil then
		return 0
	end
	return math.max(0, current.secondsLeft - (os.clock() - raidReceivedAt))
end

-- Yields until the server answers. Never throws.
function ClanController.request(action: string, arg: any?): ClanResult
	local remote = requestRemote
	if remote == nil then
		return { ok = false, reason = "NotReady" }
	end
	local ok, result = pcall(function(): any
		return remote:InvokeServer(action, arg)
	end)
	if not ok or typeof(result) ~= "table" then
		return { ok = false, reason = "NoResponse" }
	end
	return result :: ClanResult
end

function ClanController.start()
	requestRemote = Remotes.waitForFunction(Remotes.Functions.ClanRequest)
	Remotes.waitForEvent(Remotes.Events.ClanSync).OnClientEvent:Connect(function(newView: ClanView)
		view = newView
		ClanController.Changed:Fire(newView)
	end)
	Remotes.waitForEvent(Remotes.Events.ClanWarSync).OnClientEvent:Connect(function(newWar: ClanWarView)
		war = newWar
		warReceivedAt = os.clock()
		ClanController.WarChanged:Fire(newWar)
	end)
	Remotes.waitForEvent(Remotes.Events.RaidSync).OnClientEvent:Connect(function(newRaid: RaidView)
		raid = newRaid
		raidReceivedAt = os.clock()
		ClanController.RaidChanged:Fire(newRaid)
	end)
end

return ClanController
