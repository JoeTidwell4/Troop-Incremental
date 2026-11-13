--!strict
-- Client side of the login calendar, daily quests and achievements: keeps the latest
-- view from the server (ProgressSync) and sends claim/reroll requests.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

type ProgressView = Types.ProgressView
type Result = { ok: boolean, reason: string? }

local requestRemote: RemoteFunction? = nil
local view: ProgressView? = nil
local receivedAt = 0

local ProgressController = {
	Changed = Signal.new() :: Signal.Signal<ProgressView>,
}

function ProgressController.get(): ProgressView?
	return view
end

-- Seconds until the next daily reset, counted down locally.
function ProgressController.secondsToNextDay(): number
	local current = view
	if current == nil then
		return 0
	end
	return math.max(0, current.secondsToNextDay - (os.clock() - receivedAt))
end

-- True if anything can be claimed right now (for the red dot).
function ProgressController.hasClaimable(): boolean
	local current = view
	if current == nil then
		return false
	end
	if current.login.canClaim then
		return true
	end
	local allClaimed = #current.quests > 0
	for _, quest in current.quests do
		if not quest.claimed then
			allClaimed = false
			if quest.progress >= quest.target then
				return true
			end
		end
	end
	if allClaimed and not current.bonusClaimed then
		return true
	end
	for _, entry in current.achievements do
		if entry.status == "unlocked" then
			return true
		end
	end
	return false
end

-- Yields until the server answers. Never throws.
function ProgressController.request(action: string, arg: any?): Result
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
	return result :: Result
end

function ProgressController.start()
	requestRemote = Remotes.waitForFunction(Remotes.Functions.ProgressRequest)
	Remotes.waitForEvent(Remotes.Events.ProgressSync).OnClientEvent:Connect(function(newView: ProgressView)
		view = newView
		receivedAt = os.clock()
		ProgressController.Changed:Fire(newView)
	end)
end

return ProgressController
