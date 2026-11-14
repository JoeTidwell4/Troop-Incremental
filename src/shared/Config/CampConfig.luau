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
-- `hiddenInClan`: the model is hidden while you're in a clan (the Clan stand stands
-- where ClanBannerController puts your real banner; the label and click still work).
-- `onlyWhenMerchant`: the whole sign (model, label, click) only exists while the Mystery
-- Merchant is visiting. Wheel + Merchant spots (left side, where the screen is open) were
-- searched so their labels clear every other label on 4:3, 16:9 and 2.16:1 screens.
-- Signs without an old menu button get their "!" from `CampController.setBadge`.
-- Settings stays a small screen button; MENU (UI/MenuUI) lists every sign as a fallback.
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
		{ key = "Store", label = "STORE", menu = "Menu:Store", gui = "Store", kind = "Cart", offset = Vector3.new(29, 0.5, 16), color = Color3.fromRGB(0, 160, 110) },
		{ key = "Top", label = "TOP", menu = "Menu:Top", gui = "Leaderboards", kind = "Trophy", offset = Vector3.new(24, 0.5, 24), color = Color3.fromRGB(240, 195, 70) },
		{ key = "War", label = "WAR", menu = "Menu:War", gui = "FactionWar", kind = "Drum", offset = Vector3.new(-24, 0.5, 24), color = Color3.fromRGB(190, 60, 60) },
		{ key = "Clan", label = "CLAN", menu = "Menu:Clan", gui = "Clan", kind = "ClanStand", offset = Vector3.new(-30, 0.5, 10), color = Color3.fromRGB(200, 200, 205), hiddenInClan = true },
		{ key = "Wheel", label = "FORTUNE WHEEL", menu = "Menu:Wheel", gui = "Fortune", kind = "Wheel", offset = Vector3.new(37, 0.5, 17), color = Color3.fromRGB(200, 150, 60) },
		{ key = "Merchant", label = "MERCHANT", menu = "Menu:Merchant", gui = "Merchant", kind = "Merchant", offset = Vector3.new(20, 0.5, 0), color = Color3.fromRGB(110, 60, 160), onlyWhenMerchant = true },
		{ key = "Wardrobe", label = "WARDROBE", menu = "Menu:Wardrobe", gui = "Wardrobe", kind = "Rack", offset = Vector3.new(-28, 0.5, -8), color = Color3.fromRGB(170, 90, 200) },
	} :: { { key: string, label: string, menu: string, gui: string, kind: string, offset: Vector3, color: Color3, hiddenInClan: boolean?, onlyWhenMerchant: boolean? } },
}

return table.freeze(CampConfig)
