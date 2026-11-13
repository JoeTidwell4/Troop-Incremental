--!strict
-- Every DataStore, MemoryStore and MessagingService name goes through here.
--
-- Studio shares Roblox's storage with the live game (when "Studio Access to API
-- Services" is on). Studio also runs the test-mode timings (3-minute days, 10-minute
-- weeks) and the test panel, which must never touch real players' saves, clans or
-- leaderboards. So in Studio every name gets a "Studio_" prefix: Studio gets its own
-- separate saves, clans, wars and leaderboards, and the live game never sees them.

local RunService = game:GetService("RunService")

local PREFIX = if RunService:IsStudio() then "Studio_" else ""

local StoreNames = {}

function StoreNames.of(name: string): string
	return PREFIX .. name
end

function StoreNames.isStudio(): boolean
	return PREFIX ~= ""
end

return StoreNames
