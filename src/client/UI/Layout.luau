--!strict
-- Where the always-on-screen UI sits, in one place so nothing overlaps.
-- Two layouts, picked once when the game starts:
--
-- DESKTOP (big screens, mouse): designed for about 1000x620, scaled down a little on
-- smaller windows.
--   Right column: gold panel -> "ASCEND READY" (when ready) -> Settings | Store
--                 -> War | Clan | Top -> Quests
--   Bottom centre: shop panel, ability bar in a row just above it.
--
-- COMPACT (phones, tablets, small windows): designed for a 410-tall screen so buttons
-- stay big enough for thumbs.
--   Right column: small gold panel -> 2x3 grid of menu buttons -> "ASCEND READY"
--   Left edge: ability buttons stacked vertically.
--   Bottom, between the two: the shop as a drawer that can be hidden to see the fight.
--
-- The column sits on the right (owner's choice), so HudUI hides Roblox's player list,
-- which would otherwise cover it. Rankings are in the TOP window instead.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

-- Below this usable screen height (after the Roblox top bar) we use the compact layout.
local COMPACT_BELOW_HEIGHT = 560

-- The camera's ViewportSize can be (1, 1) for a moment while the game starts.
local function viewportSize(): Vector2
	local deadline = os.clock() + 3
	while os.clock() < deadline do
		local camera = workspace.CurrentCamera
		if camera ~= nil and camera.ViewportSize.Y > 1 then
			return camera.ViewportSize
		end
		task.wait()
	end
	return Vector2.new(1000, 620)
end

local function detectCompact(): boolean
	local usable = viewportSize().Y - GuiService:GetGuiInset().Y
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	return touchOnly or usable < COMPACT_BELOW_HEIGHT
end

local compact = detectCompact()

export type Slot = { top: number, index: number, count: number }

local Layout = {
	compact = compact,

	-- UIKit scales every ScreenGui so this many design pixels fit the screen height.
	DESIGN_WIDTH = 1000,
	DESIGN_HEIGHT = if compact then 410 else 620,
	-- Compact measures the height below the Roblox top bar; desktop uses the whole window.
	SCALE_USES_INSET = compact,

	MARGIN = if compact then 10 else 12, -- gap between the column and the right screen edge
	COLUMN_WIDTH = if compact then 200 else 250,
	GAP = 6,

	ECONOMY_TOP = if compact then 8 else 12,
	ECONOMY_HEIGHT = if compact then 112 else 170,

	ROW_HEIGHT = if compact then 42 else 40,
	MENU_TEXT_SIZE = if compact then 14 else 17,
	-- Desktop: Ascend sits between the gold panel and the menu rows (188).
	-- Compact: it sits under the menu grid (318).
	ASCEND_TOP = if compact then 318 else 188,
	ASCEND_HEIGHT = 40,

	-- Shop panel (ShopUI).
	SHOP_BOTTOM_MARGIN = if compact then 8 else 12,
	SHOP_HEADER_HEIGHT = if compact then 40 else 30,
	SHOP_TAB_WIDTH = 66,
	SHOP_MODE_WIDTH = 52,
	-- Content area: 3 troop rows on desktop; compact shows ~2.7 and scrolls.
	SHOP_CONTENT_HEIGHT = if compact then 156 else 180,
	-- Compact: space kept free on each side of the shop (ability column / menu column).
	SHOP_LEFT = 10 + 64 + 10,
	SHOP_RIGHT = 10 + 200 + 10,

	ABILITY_SIZE = if compact then 64 else 62,
	ABILITY_EDGE = 10, -- compact: gap between the ability column and the left screen edge

	-- Close (X) button on popup windows.
	CLOSE_SIZE = if compact then 42 else 32,

	SHOP_HEIGHT = 0, -- filled in below
}

-- Total shop panel height (8px padding top and bottom, header, gap, content).
Layout.SHOP_HEIGHT = 16 + Layout.SHOP_HEADER_HEIGHT + 6 + Layout.SHOP_CONTENT_HEIGHT

-- Menu buttons in the right column, by name.
local DESKTOP_MENU: { [string]: Slot } = {
	Settings = { top = 234, index = 1, count = 2 },
	Store = { top = 234, index = 2, count = 2 },
	War = { top = 280, index = 1, count = 3 },
	Clan = { top = 280, index = 2, count = 3 },
	Top = { top = 280, index = 3, count = 3 },
	Quests = { top = 326, index = 1, count = 2 },
	Wardrobe = { top = 326, index = 2, count = 2 },
}
local COMPACT_MENU: { [string]: Slot } = {
	Quests = { top = 126, index = 1, count = 2 },
	Store = { top = 126, index = 2, count = 2 },
	War = { top = 174, index = 1, count = 2 },
	Clan = { top = 174, index = 2, count = 2 },
	Top = { top = 222, index = 1, count = 2 },
	Settings = { top = 222, index = 2, count = 2 },
	Wardrobe = { top = 270, index = 1, count = 1 },
}

-- Position of something in the right column: `x` pixels from the column's left edge,
-- `top` pixels from the top of the screen.
function Layout.columnPosition(x: number, top: number): UDim2
	return UDim2.new(1, -(Layout.MARGIN + Layout.COLUMN_WIDTH) + x, 0, top)
end

-- (Position, Size) of a menu button: "Settings", "Store", "War", "Clan", "Top", "Quests"
-- or "Wardrobe".
function Layout.menuSlot(name: string): (UDim2, UDim2)
	local slot = (if compact then COMPACT_MENU else DESKTOP_MENU)[name]
	assert(slot ~= nil, `Unknown menu button {name}`)
	local width = (Layout.COLUMN_WIDTH - Layout.GAP * (slot.count - 1)) / slot.count
	local x = (slot.index - 1) * (width + Layout.GAP)
	return Layout.columnPosition(x, slot.top), UDim2.new(0, width, 0, Layout.ROW_HEIGHT)
end

-- Size of a big popup window. Desktop uses the given fraction of the screen; compact
-- uses almost the whole screen, since phone screens are short.
function Layout.windowSize(widthScale: number, heightScale: number): UDim2
	if compact then
		return UDim2.new(math.max(widthScale, 0.94), 0, 0.95, 0)
	end
	return UDim2.new(widthScale, 0, heightScale, 0)
end

return table.freeze(Layout)
