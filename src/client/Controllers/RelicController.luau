--!strict
-- Client side of relics: keeps the inventory the server sends on RelicSync (only when it
-- changes), sends RelicRequest actions, and shows drops (floating text; Legendary and
-- Mythic get the full reveal).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Controllers = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local RelicConfig = require(Shared:WaitForChild("Config"):WaitForChild("RelicConfig"))
local StateController = require(Controllers.StateController)

type RelicsData = Types.RelicsData
type RelicItem = Types.RelicItem

local relics: RelicsData? = nil
local requestRemote: RemoteFunction? = nil

local RelicController = {
	Changed = Signal.new() :: Signal.Signal<RelicsData>,
	-- A relic dropped: (item, dust) where dust is set if it went straight to Dust.
	Dropped = Signal.new() :: Signal.Signal<RelicItem, number?>,
}

function RelicController.get(): RelicsData?
	return relics
end

-- "Epic Inferno Ring".
function RelicController.nameOf(item: RelicItem): string
	return `{item.rarity} {RelicConfig.SETS[item.set].name} {item.slot}`
end

-- Yields until the server answers. Never throws.
function RelicController.request(action: string, arg: any, extra: any?): { ok: boolean, reason: string?, dust: number?, count: number? }
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

function RelicController.start()
	requestRemote = Remotes.waitForFunction(Remotes.Functions.RelicRequest)
	Remotes.waitForEvent(Remotes.Events.RelicSync).OnClientEvent:Connect(function(data: any)
		if typeof(data) == "table" then
			relics = data :: RelicsData
			RelicController.Changed:Fire(data)
		end
	end)
	StateController.Notice:Connect(function(notice: Types.Notice)
		if notice.kind == "Relic" and notice.relic ~= nil then
			RelicController.Dropped:Fire(notice.relic, notice.dust)
		end
	end)
end

return RelicController
