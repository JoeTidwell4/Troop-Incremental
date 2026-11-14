--!strict
-- The Endless Tower (server TowerService): climb, leave, claim the daily Tribute. The
-- state (floor being fought, best floor, Tribute ready) comes in the snapshot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local TowerController = {}

local requestRemote: RemoteFunction? = nil

-- "Climb" | "Leave" | "Tribute". Yields until the server answers. Never throws.
function TowerController.request(action: string): Types.TowerResult
	local remote = requestRemote
	if remote == nil then
		return { ok = false, reason = "NotReady" }
	end
	local ok, result = pcall(function(): any
		return remote:InvokeServer(action)
	end)
	if ok and typeof(result) == "table" then
		return result
	end
	return { ok = false, reason = "NoResponse" }
end

function TowerController.start()
	requestRemote = Remotes.waitForFunction(Remotes.Functions.TowerRequest)
end

return TowerController
