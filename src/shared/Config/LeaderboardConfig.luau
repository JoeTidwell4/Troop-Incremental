--!strict
-- Global leaderboards and the Roblox player list stats. Safe to tweak.
-- OrderedDataStores only hold whole numbers, so Honor is stored as a whole number
-- (capped at MAX_STORED); best stage is already one.

local RunService = game:GetService("RunService")

local isStudio = RunService:IsStudio()

local LeaderboardConfig = {
	TOP_COUNT = 10,
	WRITE_INTERVAL = if isStudio then 30 else 300, -- seconds between saving changed scores
	READ_INTERVAL = if isStudio then 20 else 120, -- seconds between reading the top lists
	MAX_STORED = 2 ^ 52,
}

return table.freeze(LeaderboardConfig)
