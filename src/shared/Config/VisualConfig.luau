--!strict
-- Client-side visuals only. Nothing here affects gameplay.

local VisualConfig = {
	-- Cosmetic troop models shown per type, no matter how many you own.
	MAX_VISIBLE_PER_TYPE = 8,
	-- Troop looks (Visuals/TroopModels): owning this many of a type unlocks the next look
	-- (tier 2, 3, 4). Same counts as the first damage milestones.
	TROOP_TIERS = { 25, 100, 300 },

	-- Camera position relative to your plot's center (see WorldConfig / Plots).
	CAMERA_OFFSET = Vector3.new(0, 22, -38),
	CAMERA_LOOK_OFFSET = Vector3.new(0, 2, 4),
	-- Phones: tilted a bit further down, so the fight sits between the HUD and the shop drawer.
	CAMERA_LOOK_OFFSET_COMPACT = Vector3.new(0, -1, 4),
}

return table.freeze(VisualConfig)
