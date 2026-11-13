--!strict
-- Client-side visuals only. Nothing here affects gameplay.

local VisualConfig = {
	-- Cosmetic troop models shown per type, no matter how many you own.
	MAX_VISIBLE_PER_TYPE = 8,

	-- Camera position relative to your plot's center (see WorldConfig / Plots).
	CAMERA_OFFSET = Vector3.new(0, 22, -38),
	CAMERA_LOOK_OFFSET = Vector3.new(0, 2, 4),
}

return table.freeze(VisualConfig)
