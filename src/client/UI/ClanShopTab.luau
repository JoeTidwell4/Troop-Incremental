--!strict
-- Clan window tab: the clan shop. Spend your own Clan Tokens (earned from clan quests,
-- Clan War placement, MVP and head-to-head wins) on clan-only commander gear, Hero
-- Chests and gear packs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local GearInfo = require(Shared:WaitForChild("GearInfo"))
local Config = Shared:WaitForChild("Config")
local ClanConfig = require(Config:WaitForChild("ClanConfig"))
local CommanderConfig = require(Config:WaitForChild("CommanderConfig"))
local UIKit = require(script.Parent.UIKit)
local ClanTypes = require(script.Parent.ClanTypes)

type ClanView = Types.ClanView

local Theme = UIKit.Theme
local TOKEN_COLOR = Color3.fromRGB(120, 200, 255)

local ClanShopTab = {}

function ClanShopTab.build(parent: Instance, context: ClanTypes.Context): ClanTypes.Tab
	local frame = UIKit.create("Frame", {
		Name = "Shop",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = parent,
	}) :: Frame
	local tokensLabel = UIKit.label({ Text = "", Font = Theme.FontBold, TextSize = 16, TextColor3 = TOKEN_COLOR, Size = UDim2.new(1, 0, 0, 20), Parent = frame })
	UIKit.label({
		Text = "Earn Clan Tokens from clan quests, Clan War placement, being MVP and winning head-to-head wars.",
		TextColor3 = Theme.Muted,
		TextSize = 11,
		Position = UDim2.new(0, 0, 0, 20),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = frame,
	})
	local list = UIKit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = frame,
	}, {
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		UIKit.create("UIPadding", { PaddingRight = UDim.new(0, 10) }),
	}) :: ScrollingFrame

	type Row = { button: TextButton, item: any }
	local rows: { Row } = {}
	for order, item in ClanConfig.SHOP do
		local gear = if item.kind == "gear" then CommanderConfig.ITEMS[item.id] else nil
		local name = if gear ~= nil then gear.displayName else item.displayName or item.id
		local detail = if gear ~= nil
			then `{gear.slot}: +{math.floor(((gear.multiplier or 1) - 1) * 100 + 0.5)}% {CommanderConfig.STAT_NAMES[CommanderConfig.SLOT_STATS[gear.slot]]}`
			else "Buy as often as you like"
		local row = UIKit.create("Frame", {
			LayoutOrder = order,
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 44),
			Parent = list,
		}, { UIKit.corner(8) }) :: Frame
		UIKit.label({
			Text = name,
			Font = Theme.FontBold,
			TextSize = 14,
			TextColor3 = if gear ~= nil then GearInfo.rarity(gear.rarity).color else Theme.Text,
			Position = UDim2.new(0, 10, 0, 4),
			Size = UDim2.new(1, -140, 0, 18),
			Parent = row,
		})
		UIKit.label({ Text = detail, TextColor3 = Theme.Muted, TextSize = 11, Position = UDim2.new(0, 10, 0, 23), Size = UDim2.new(1, -140, 0, 16), Parent = row })
		local button = UIKit.button({
			Text = "",
			TextSize = 13,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.new(0, 120, 1, -10),
			Parent = row,
		})
		button.Activated:Connect(function()
			task.spawn(function()
				local result = context.request("BuyClanShop", item.id)
				if result.ok then
					context.showStatus(`Bought {name}!`)
				end
			end)
		end)
		table.insert(rows, { button = button, item = item })
	end

	local function render(_view: ClanView, snapshot: Types.Snapshot?)
		local tokens = if snapshot ~= nil then snapshot.clanTokens else 0
		tokensLabel.Text = `Clan Tokens: {tokens}`
		for _, row in rows do
			local owned = row.item.kind == "gear" and snapshot ~= nil and snapshot.commander.owned[row.item.id] == true
			local affordable = not owned and tokens >= row.item.cost
			row.button.Text = if owned then "Owned" else `{row.item.cost} tokens`
			row.button.BackgroundColor3 = if affordable then Theme.Good else Theme.Disabled
			row.button.AutoButtonColor = affordable
		end
	end

	return { title = "Shop", frame = frame, render = render }
end

return ClanShopTab
