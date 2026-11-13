--!strict
-- Where the always-on-screen buttons sit, in one place so they never overlap.
-- (The Roblox player list lives in the top-right corner, so nothing goes there.)
--
-- Left column, top to bottom:
--   gold panel  ->  "ASCEND READY" button (only when ready)  ->  Sound | Store  ->  War | Clan | Top
-- Bottom centre: ability bar, sitting just above the shop panel.

local Layout = {
	LEFT = 12,
	COLUMN_WIDTH = 210,

	ECONOMY_TOP = 12,
	ECONOMY_HEIGHT = 134,

	ASCEND_TOP = 12 + 134 + 6, -- 152
	ASCEND_HEIGHT = 34,

	ROW1_TOP = 152 + 34 + 6, -- 192: Sound | Store
	ROW2_TOP = 192 + 30 + 6, -- 228: War | Clan | Top
	ROW_HEIGHT = 30,
	GAP = 6,

	-- Shop panel (ShopUI) height plus its bottom margin; the ability bar sits above it.
	SHOP_HEIGHT = 232,
	SHOP_BOTTOM_MARGIN = 12,
	ABILITY_SIZE = 62,
}

-- Left-column button slot: `index` of `count` equal buttons in a row.
function Layout.rowSlot(top: number, index: number, count: number): (UDim2, UDim2)
	local width = (Layout.COLUMN_WIDTH - Layout.GAP * (count - 1)) / count
	local x = Layout.LEFT + (index - 1) * (width + Layout.GAP)
	return UDim2.new(0, x, 0, top), UDim2.new(0, width, 0, Layout.ROW_HEIGHT)
end

return table.freeze(Layout)
