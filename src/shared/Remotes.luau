--!strict
-- Every RemoteEvent / RemoteFunction name in one place. The server creates them
-- (see RemoteService); the client looks them up with the helpers below.
--
-- Tap         client -> server   (tapCount: number)
-- ClientReady client -> server   ()  "my scripts are loaded, send me my state"
-- StateSync   server -> client   (snapshot: Types.Snapshot)
-- BuyTroop    client -> server, returns Types.BuyResult   (troopId: string, mode: Types.BuyMode)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {
	FOLDER_NAME = "Remotes",

	Events = table.freeze({
		Tap = "Tap",
		ClientReady = "ClientReady",
		StateSync = "StateSync",
	}),

	Functions = table.freeze({
		BuyTroop = "BuyTroop",
	}),
}

local WAIT_TIMEOUT = 30

local function getFolder(): Instance
	local folder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME, WAIT_TIMEOUT)
	if folder == nil then
		error("Remotes folder never appeared. Is the server script running?", 3)
	end
	return folder
end

-- Client helper: waits for a RemoteEvent the server created.
function Remotes.waitForEvent(name: string): RemoteEvent
	local remote = getFolder():WaitForChild(name, WAIT_TIMEOUT)
	if remote == nil or not remote:IsA("RemoteEvent") then
		error(`RemoteEvent "{name}" not found`, 2)
	end
	return remote :: RemoteEvent
end

-- Client helper: waits for a RemoteFunction the server created.
function Remotes.waitForFunction(name: string): RemoteFunction
	local remote = getFolder():WaitForChild(name, WAIT_TIMEOUT)
	if remote == nil or not remote:IsA("RemoteFunction") then
		error(`RemoteFunction "{name}" not found`, 2)
	end
	return remote :: RemoteFunction
end

return table.freeze(Remotes)
