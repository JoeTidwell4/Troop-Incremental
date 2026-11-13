--!strict
-- Save-data settings. Server only.

local DataConfig = {
	-- Changing this starts everyone with fresh data (the old store is kept, just not used).
	STORE_NAME = "PlayerData_v1",

	-- Saved key for each player is KEY_PREFIX .. UserId.
	KEY_PREFIX = "Player_",

	KICK_MESSAGE_LOAD_FAILED = "Your data couldn't be loaded. Please rejoin in a minute.",
	KICK_MESSAGE_SESSION_ENDED = "Your data was opened on another server. Please rejoin.",
}

return table.freeze(DataConfig)
