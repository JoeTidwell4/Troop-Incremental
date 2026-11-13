--!strict
-- Client side of buying troops: asks the server and returns its answer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))

type BuyMode = Types.BuyMode
type BuyResult = Types.BuyResult

local buyRemote: RemoteFunction? = nil

local TroopController = {}

function TroopController.start()
	buyRemote = Remotes.waitForFunction(Remotes.Functions.BuyTroop)
end

-- Yields until the server answers. Never throws.
function TroopController.buy(troopId: string, mode: BuyMode): BuyResult
	local remote = buyRemote
	if remote == nil then
		return { ok = false, bought = 0, reason = "NotReady" }
	end
	local ok, result = pcall(function(): any
		return remote:InvokeServer(troopId, mode)
	end)
	if not ok or typeof(result) ~= "table" then
		return { ok = false, bought = 0, reason = "NoResponse" }
	end
	return result :: BuyResult
end

return TroopController
