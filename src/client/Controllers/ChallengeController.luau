--!strict
-- Challenge runs (server ChallengeService): start one, leave it. The state itself
-- (which challenge you're in, tiers cleared) comes in the snapshot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ChallengeController = {}

local requestRemote: RemoteFunction? = nil

-- "Start" (challengeId) or "Leave". Yields until the server answers. Never throws.
function ChallengeController.request(action: string, challengeId: string?): Types.ChallengeResult
	local remote = requestRemote
	if remote == nil then
		return { ok = false, reason = "NotReady" }
	end
	local ok, result = pcall(function(): any
		return remote:InvokeServer(action, challengeId)
	end)
	if ok and typeof(result) == "table" then
		return result
	end
	return { ok = false, reason = "NoResponse" }
end

function ChallengeController.start()
	requestRemote = Remotes.waitForFunction(Remotes.Functions.ChallengeRequest)
end

return ChallengeController
