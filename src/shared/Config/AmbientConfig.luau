--!strict
-- Background life around the battlefield (client only, cosmetic; Client/Visuals/Ambient).
-- Safe to tweak.
--
-- Positions are offsets from the plot centre (the camera sits at (0, 22, -38) looking
-- toward +Z, so +X is the LEFT of the screen). Everything here is far behind or beside
-- the arena, outside the camp signs (CampConfig) and on screen from 4:3 to 2.16:1. How
-- many of each show depends on the graphics profile (GraphicsConfig ambient*).
-- Environment keeps scenery out of the skirmish spots and off the road.

local AmbientConfig = {
	UNIT_SCALE = 1.3, -- far away, so a bit bigger than the arena units to read well

	-- Small fights: a few of your troops vs the area's creatures. In order: Low graphics
	-- shows only the first ones.
	SKIRMISHES = {
		Vector3.new(62, 0, 80),
		Vector3.new(-58, 0, 74),
		Vector3.new(-36, 0, 108),
	},
	SKIRMISH_SIZE = 3, -- per side
	SKIRMISH_GAP = 3.5, -- between units on the same side
	SKIRMISH_WIDTH = 4, -- each side stands this far from the middle
	FALL_EVERY = NumberRange.new(4, 8), -- seconds between someone falling (per skirmish)
	RESPAWN_DISTANCE = 16, -- replacements walk in from this far behind their side
	CLEAR_RADIUS = 16, -- no scenery this close to a skirmish

	-- A column of your troops marching along a road behind the arena.
	ROAD_Z = 58,
	ROAD_HALF_LENGTH = 170, -- marchers wrap around past the screen edge (wide phones too)
	ROAD_WIDTH = 6,
	MARCH_SPEED = 5, -- studs per second
	MARCH_GAP = 4.5,

	-- Creatures wandering on both flanks (min/max corners).
	ROAM_AREAS = {
		{ min = Vector3.new(50, 0, 28), max = Vector3.new(95, 0, 65) },
		{ min = Vector3.new(-95, 0, 30), max = Vector3.new(-52, 0, 65) },
	},
	ROAM_SPEED = 4,
	ROAM_PAUSE = NumberRange.new(1, 3.5),

	WALK_SPEED = 6, -- skirmish replacements
}

return table.freeze(AmbientConfig)
