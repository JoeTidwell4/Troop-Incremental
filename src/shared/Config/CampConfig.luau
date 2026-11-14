--!strict
-- The camp: menus as things standing around the battlefield (UI overhaul, part 1).
-- Client-only visuals. Safe to tweak.
--
-- Each sign: `menu` = the Spotlight opener key of its window, `gui` / "Overlay" = the
-- ScreenGui whose Overlay frame is the open window (the camera flies back when it
-- closes), `offset` = where it stands relative to the plot centre (the arena is 70 x 36,
-- x = +-35; the camera looks from -Z, so +X is the LEFT of the screen), `kind` = the model
-- (Visuals/CampProps). Spots were checked to stay on screen from 4:3 tablets to wide
-- phones and clear of the troops, Generals (x = -21) and clan banner (-30, 10).
--
-- The old menu button of a converted window is hidden; its red dot (a child "Dot") is
-- shown as a "!" above the sign instead.

local CampConfig = {
	FOCUS_SECONDS = 0.45, -- camera glide to the sign (and back)
	FOCUS_DISTANCE = 15, -- how far in front of the sign the camera stops
	FOCUS_HEIGHT = 5,
	LABEL_COLOR = Color3.fromRGB(255, 225, 140),

	SIGNS = {
		{ key = "Quests", label = "QUESTS", menu = "Menu:Quests", gui = "Quests", kind = "Board", offset = Vector3.new(31, 0.5, 6), color = Color3.fromRGB(150, 105, 65) },
		{ key = "Army", label = "ARMY", menu = "Menu:Army", gui = "Army", kind = "Tent", offset = Vector3.new(29, 0.5, -6), color = Color3.fromRGB(70, 110, 200) },
		{ key = "Adventure", label = "ADVENTURE", menu = "Menu:Adventure", gui = "Adventure", kind = "Signpost", offset = Vector3.new(-31, 0.5, 2), color = Color3.fromRGB(200, 110, 50) },
		{ key = "Wardrobe", label = "WARDROBE", menu = "Menu:Wardrobe", gui = "Wardrobe", kind = "Rack", offset = Vector3.new(-28, 0.5, -8), color = Color3.fromRGB(170, 90, 200) },
	} :: { { key: string, label: string, menu: string, gui: string, kind: string, offset: Vector3, color: Color3 } },
}

return table.freeze(CampConfig)
