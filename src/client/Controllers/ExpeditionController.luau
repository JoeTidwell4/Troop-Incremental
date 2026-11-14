--!strict
-- Expeditions (server ExpeditionService): send, collect, reroll. The board and the teams
-- away come in the snapshot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ExpeditionController = {}

local requestRemote: RemoteFunction? = nil

-- ("Send", missionId, generalIds) | ("Collect", slot) | ("Reroll"). Yields. Never throws.
function ExpeditionController.request(action: string, arg: any?, extra: any?): Types.ExpeditionResult
	local remote = requestRemote
	if remote == nil then
		return { ok = false, reason = "NotReady" }
	end
	local ok, result = pcall(function(): any
		return remote:InvokeServer(action, arg, extra)
	end)
	if ok and typeof(result) == "table" then
		return result
	end
	return { ok = false, reason = "NoResponse" }
end

-- How many teams are back and waiting to be collected.
function ExpeditionController.readyCount(snapshot: Types.Snapshot): number
	local now = workspace:GetServerTimeNow()
	local count = 0
	for _, run in snapshot.expeditions.active do
		if now >= run.endsAt then
			count += 1
		end
	end
	return count
end

function ExpeditionController.start()
	requestRemote = Remotes.waitForFunction(Remotes.Functions.ExpeditionRequest)
end

return ExpeditionController
