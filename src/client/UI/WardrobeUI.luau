--!strict
-- "WARDROBE" menu button and window: commander gear (CommanderConfig). Pick a slot
-- (Helmet / Cape / Weapon / Back), then wear or take off items. Locked items show how to
-- earn them. The top line adds up the bonuses of everything you're wearing.
-- The Chests tab opens Wardrobe Chests (gold only) for chest-exclusive items.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local GearInfo = require(Shared:WaitForChild("GearInfo"))
local BigNum = require(Shared:WaitForChild("BigNum"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local CommanderConfig = require(Shared:WaitForChild("Config"):WaitForChild("CommanderConfig"))
local UIKit = require(script.Parent.UIKit)
local Spotlight = require(script.Parent.Spotlight)
local Layout = require(script.Parent.Layout)
local StateController = require(Client.Controllers.StateController)
local CommanderController = require(Client.Controllers.CommanderController)
local ChestRevealUI = require(script.Parent.ChestRevealUI)

type Snapshot = Types.Snapshot
type ItemDef = Types.CommanderItemDef

local Theme = UIKit.Theme
local ROW_HEIGHT = if Layout.compact then 50 else 44

local WardrobeUI = {}

local openTo: ((tab: string?) -> ())? = nil

-- Opens the Wardrobe, optionally on a tab ("Helmet", "Cape", "Weapon", "Back", "Chests").
function WardrobeUI.open(tab: string?)
	if openTo ~= nil then
		openTo(tab)
	end
end

local function percent(multiplier: number): string
	return `+{math.floor((multiplier - 1) * 100 + 0.5)}%`
end

-- How to get a locked item.
local function howToGet(def: ItemDef): string
	local unlock = def.unlock
	local value = unlock.value or 0
	if unlock.kind == "stage" then
		return `Reach stage {value}`
	elseif unlock.kind == "ascensions" then
		return if value == 1 then "Ascend once" else `Ascend {value} times`
	elseif unlock.kind == "loginStreak" then
		return `Log in {value} days in a row`
	elseif unlock.kind == "clanWar" then
		return if value == 1 then "Your clan wins the Clan War" else `Your clan places top {value} in Clan War`
	elseif unlock.kind == "pass" then
		return "Robux pass in the Store (looks only)"
	elseif unlock.kind == "clanShop" then
		return "Buy in the clan shop"
	elseif unlock.kind == "chest" then
		local chest = CommanderConfig.CHESTS[unlock.chest or ""]
		return `From the {if chest ~= nil then chest.displayName else "chest"}`
	end
	return ""
end

local function statText(def: ItemDef): string
	if def.multiplier == nil then
		return "Looks only"
	end
	local stat = CommanderConfig.STAT_NAMES[CommanderConfig.SLOT_STATS[def.slot]] or ""
	return `{percent(def.multiplier)} {stat}`
end

function WardrobeUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = UIKit.create("ScreenGui", {
		Name = "Wardrobe",
		ResetOnSpawn = false,
		DisplayOrder = 19,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	local menuPosition, menuSize = Layout.menuSlot("Wardrobe")
	local menuButton = UIKit.button({
		Name = "WardrobeButton",
		Text = "WARDROBE",
		TextSize = Layout.MENU_TEXT_SIZE,
		BackgroundColor3 = Color3.fromRGB(60, 140, 130),
		Position = menuPosition,
		Size = menuSize,
		Parent = gui,
	})

	local overlay = UIKit.create("Frame", {
		Name = "Overlay",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Active = true,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = gui,
	}) :: Frame
	local window = UIKit.create("Frame", {
		Name = "Window",
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = Layout.windowSize(0.9, 0.85),
		Parent = overlay,
	}, {
		UIKit.corner(14),
		UIKit.padding(14),
		UIKit.create("UISizeConstraint", { MaxSize = Vector2.new(600, 420) }),
	}) :: Frame
	UIKit.label({
		Text = "Wardrobe",
		Font = Theme.FontBold,
		TextSize = 22,
		TextColor3 = Theme.Gold,
		Size = UDim2.new(1, -50, 0, 26),
		Parent = window,
	})
	local bonusLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 12,
		Position = UDim2.new(0, 0, 0, 26),
		Size = UDim2.new(1, -50, 0, 16),
		Parent = window,
	})
	local closeButton = UIKit.button({
		Text = "X",
		TextSize = 16,
		BackgroundColor3 = Theme.PanelLight,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(Layout.CLOSE_SIZE, Layout.CLOSE_SIZE),
		Parent = window,
	})

	-- Slot tabs, plus "Chests".
	local selectedSlot = "Helmet"
	local slotButtons: { [string]: TextButton } = {}
	local tabNames = table.clone(CommanderConfig.SLOTS)
	table.insert(tabNames, "Chests")
	local tabWidth = 1 / #tabNames
	for index, slot in tabNames do
		local button = UIKit.button({
			Text = slot,
			TextSize = 14,
			BackgroundColor3 = Theme.PanelLight,
			Position = UDim2.new((index - 1) * tabWidth, if index == 1 then 0 else 3, 0, 48),
			Size = UDim2.new(tabWidth, -6, 0, 32),
			Parent = window,
		})
		slotButtons[slot] = button
	end

	local list = UIKit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 88),
		Size = UDim2.new(1, 0, 1, -88),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = window,
	}, {
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		UIKit.create("UIPadding", { PaddingRight = UDim.new(0, 10) }),
	}) :: ScrollingFrame

	---------------------------------------------------------------- chests
	local chestPanel = UIKit.create("Frame", {
		Name = "Chests",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 88),
		Size = UDim2.new(1, 0, 1, -88),
		Visible = false,
		Parent = window,
	}) :: Frame
	local oddsParts: { string } = {}
	for _, entry in CommanderConfig.CHEST_ODDS do
		table.insert(oddsParts, `{GearInfo.rarity(entry.rarity).name} {entry.chance}%`)
	end
	local oddsText = table.concat(oddsParts, "  ")
	type ChestCard = { button: TextButton, pity: TextLabel }
	local chestCards: { [string]: ChestCard } = {}
	local opening = false

	local MESSAGES: { [string]: string } = {
		CantAfford = "Not enough gold",
		TooEarly = `Reach stage {CommanderConfig.CHEST_UNLOCK_STAGE} first`,
	}
	for index, chestId in CommanderConfig.CHEST_ORDER do
		local chest = CommanderConfig.CHESTS[chestId]
		local card = UIKit.create("Frame", {
			Name = chestId,
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Position = UDim2.new((index - 1) * 0.5, if index == 1 then 0 else 4, 0, 0),
			Size = UDim2.new(0.5, -4, 1, 0),
			Parent = chestPanel,
		}, { UIKit.corner(10), UIKit.padding(10) }) :: Frame
		UIKit.label({ Text = chest.displayName, Font = Theme.FontBold, TextSize = 18, TextColor3 = Theme.Gold, Size = UDim2.new(1, 0, 0, 22), Parent = card })
		UIKit.label({ Text = chest.description, TextColor3 = Theme.Muted, TextSize = 13, Position = UDim2.new(0, 0, 0, 24), Size = UDim2.new(1, 0, 0, 16), Parent = card })
		UIKit.label({
			Text = oddsText,
			TextSize = 11,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			Position = UDim2.new(0, 0, 0, 44),
			Size = UDim2.new(1, 0, 0, 30),
			Parent = card,
		})
		local pity = UIKit.label({
			Text = "",
			TextColor3 = GearInfo.rarity(5).color,
			TextSize = 12,
			Position = UDim2.new(0, 0, 0, 76),
			Size = UDim2.new(1, 0, 0, 16),
			Parent = card,
		})
		UIKit.label({
			Text = `Duplicates give back {math.floor(CommanderConfig.CHEST_DUPLICATE_REFUND * 100)}% of the price.`,
			TextColor3 = Theme.Muted,
			TextSize = 11,
			Position = UDim2.new(0, 0, 0, 94),
			Size = UDim2.new(1, 0, 0, 14),
			Parent = card,
		})
		local button = UIKit.button({
			Text = "",
			TextSize = 14,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 48),
			Parent = card,
		})
		button.Activated:Connect(function()
			if opening or ChestRevealUI.isPlaying() then
				return
			end
			opening = true
			task.spawn(function()
				local result = CommanderController.openChest(chestId)
				opening = false
				local def = if result.itemId ~= nil then CommanderConfig.ITEMS[result.itemId] else nil
				if result.ok and def ~= nil then
					ChestRevealUI.play(chest.displayName, def, result)
				else
					bonusLabel.Text = MESSAGES[result.reason or ""] or "Couldn't open that, try again."
				end
			end)
		end)
		chestCards[chestId] = { button = button, pity = pity }
	end

	type Row = { frame: Frame, status: TextLabel, button: TextButton, def: ItemDef }
	local rows: { Row } = {}
	for order, itemId in CommanderConfig.ORDER do
		local def = CommanderConfig.ITEMS[itemId]
		local rarity = GearInfo.rarity(def.rarity)
		local frame = UIKit.create("Frame", {
			Name = itemId,
			LayoutOrder = order,
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			Visible = false,
			Parent = list,
		}, { UIKit.corner(8) }) :: Frame
		UIKit.create("Frame", {
			BackgroundColor3 = def.color,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 8, 0, 8),
			Size = UDim2.new(0, ROW_HEIGHT - 16, 0, ROW_HEIGHT - 16),
			Parent = frame,
		}, { UIKit.corner(6) })
		UIKit.label({
			Text = def.displayName,
			Font = Theme.FontBold,
			TextSize = 15,
			TextColor3 = rarity.color,
			Position = UDim2.new(0, ROW_HEIGHT, 0, 4),
			Size = UDim2.new(1, -ROW_HEIGHT - 120, 0, 20),
			Parent = frame,
		})
		local status = UIKit.label({
			Text = "",
			TextColor3 = Theme.Muted,
			TextSize = 12,
			Position = UDim2.new(0, ROW_HEIGHT, 0, 24),
			Size = UDim2.new(1, -ROW_HEIGHT - 120, 0, 16),
			Parent = frame,
		})
		local button = UIKit.button({
			Text = "",
			TextSize = 13,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.new(0, 104, 1, -12),
			Parent = frame,
		})
		table.insert(rows, { frame = frame, status = status, button = button, def = def })
	end

	local function render(snapshot: Snapshot)
		local view = snapshot.commander
		for slot, button in slotButtons do
			button.BackgroundColor3 = if slot == selectedSlot then Theme.Accent else Theme.PanelLight
		end
		local showChests = selectedSlot == "Chests"
		chestPanel.Visible = showChests
		list.Visible = not showChests
		local unlocked = snapshot.bestStage >= CommanderConfig.CHEST_UNLOCK_STAGE
		local price = Formulas.wardrobeChestPrice(snapshot.bestStage)
		for chestId, card in chestCards do
			local left = math.max(1, CommanderConfig.CHEST_PITY_EVERY - (view.pity[chestId] or 0))
			card.pity.Text = `Legendary guaranteed within {left} chest{if left == 1 then "" else "s"}`
			local affordable = unlocked and BigNum.gte(snapshot.gold, price)
			card.button.Text = if unlocked
				then `Open: {NumberFormat.big(price)} gold`
				else `Reach stage {CommanderConfig.CHEST_UNLOCK_STAGE}`
			card.button.BackgroundColor3 = if affordable then Theme.Good else Theme.Disabled
			card.button.AutoButtonColor = affordable
		end
		-- Bonuses from everything worn.
		local parts: { string } = {}
		for _, slot in CommanderConfig.SLOTS do
			local def = CommanderConfig.ITEMS[view.equipped[slot] or ""]
			if def ~= nil and def.multiplier ~= nil and view.owned[def.id] then
				table.insert(parts, `{percent(def.multiplier)} {CommanderConfig.STAT_NAMES[CommanderConfig.SLOT_STATS[slot]]}`)
			end
		end
		bonusLabel.Text = if #parts > 0 then `Wearing: {table.concat(parts, ", ")}` else "Wear gear for bonuses. Earn more by playing."
		for _, row in rows do
			local def = row.def
			row.frame.Visible = def.slot == selectedSlot
			local owned = view.owned[def.id] == true
			local worn = view.equipped[def.slot] == def.id
			if not owned then
				row.status.Text = `{statText(def)}  |  {howToGet(def)}`
				row.button.Text = "Locked"
				row.button.BackgroundColor3 = Theme.Disabled
				row.button.AutoButtonColor = false
			elseif worn then
				row.status.Text = `{statText(def)}  |  Wearing`
				row.button.Text = "Take off"
				row.button.BackgroundColor3 = Theme.PanelLight
				row.button.AutoButtonColor = true
			else
				row.status.Text = statText(def)
				row.button.Text = "Wear"
				row.button.BackgroundColor3 = Theme.Good
				row.button.AutoButtonColor = true
			end
		end
	end

	for _, row in rows do
		row.button.Activated:Connect(function()
			local snapshot = StateController.get()
			if snapshot == nil or not snapshot.commander.owned[row.def.id] then
				return
			end
			local worn = snapshot.commander.equipped[row.def.slot] == row.def.id
			CommanderController.equip(row.def.slot, if worn then "" else row.def.id)
		end)
	end
	for slot, button in slotButtons do
		button.Activated:Connect(function()
			selectedSlot = slot
			local snapshot = StateController.get()
			if snapshot ~= nil then
				render(snapshot)
			end
		end)
	end

	openTo = function(tab: string?)
		if tab ~= nil and slotButtons[tab] ~= nil then
			selectedSlot = tab
		end
		local snapshot = StateController.get()
		if snapshot ~= nil then
			render(snapshot)
		end
		UIKit.openModal(overlay, window)
	end
	menuButton.Activated:Connect(function()
		WardrobeUI.open(nil)
	end)
	Spotlight.register("Menu:Wardrobe", menuButton)
	Spotlight.registerOpener("Menu:Wardrobe", function()
		WardrobeUI.open(nil)
	end)
	closeButton.Activated:Connect(function()
		overlay.Visible = false
	end)
	StateController.Changed:Connect(function(snapshot: Snapshot)
		if overlay.Visible then
			render(snapshot)
		end
	end)

	gui.Parent = playerGui
end

return WardrobeUI
