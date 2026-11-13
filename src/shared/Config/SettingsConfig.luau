--!strict
-- Player settings saved in their profile (so a phone player picks Low graphics once,
-- not every session). Each setting has a fixed list of allowed values; the server
-- rejects anything else.
--
-- graphics: "Auto" picks Low on phones/tablets and small windows, High otherwise.
-- sound:    "All" | "SfxOnly" (music off) | "Off".

local SettingsConfig = {
	OPTIONS = {
		graphics = { "Auto", "Low", "High" },
		sound = { "All", "SfxOnly", "Off" },
	} :: { [string]: { string } },

	DEFAULTS = {
		graphics = "Auto",
		sound = "All",
	} :: { [string]: string },

	-- SetSetting remote limit (taps on a settings button).
	REQUESTS_BURST = 6,
	REQUESTS_PER_SECOND = 2,
}

return table.freeze(SettingsConfig)
