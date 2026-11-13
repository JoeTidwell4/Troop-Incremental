--!strict
-- Where each player's battlefield ("plot") is in the world. Every player gets their own
-- plot far from everyone else's, so you only ever see your own fight and avatar.
-- Plot N's center = PLOT_BASE + (N - 1) * PLOT_SPACING along X.

local WorldConfig = {
	PLOT_BASE = Vector3.new(0, 200, 0),
	PLOT_SPACING = 400,

	-- Where your avatar (the commander) stands, relative to the plot center, and the
	-- point it faces (the enemy).
	COMMANDER_OFFSET = Vector3.new(-15, 0, -2),
	COMMANDER_LOOK_AT = Vector3.new(0, 0, 13),
}

return table.freeze(WorldConfig)
