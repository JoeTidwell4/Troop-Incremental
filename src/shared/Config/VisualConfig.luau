--!strict
-- Client-side visuals only. Nothing here affects gameplay.

local VisualConfig = {
	-- Where the battlefield is built (high up, away from the default Baseplate).
	BATTLEFIELD_ORIGIN = Vector3.new(0, 200, 0),

	-- Cosmetic troop models shown per type, no matter how many you own.
	MAX_VISIBLE_PER_TYPE = 8,

	-- Camera position relative to the battlefield origin.
	CAMERA_OFFSET = Vector3.new(0, 22, -38),
	CAMERA_LOOK_OFFSET = Vector3.new(0, 2, 4),
}

return table.freeze(VisualConfig)
