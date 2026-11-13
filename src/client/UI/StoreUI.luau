--!strict
-- Robux store window ("STORE" button on the left). Lists the game passes and gold
-- products that have been set up (id > 0 in MonetizationConfig); anything not set up is
-- hidden. Prices are read live from Roblox.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared:WaitForChild("Formulas"))
local BigNum = require(Shared:WaitForChild("BigNum"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local MonetizationConfig = require(Shared:WaitForChild("Config"):WaitForChild("MonetizationConfig"))
local UIKit = require(script.Parent.UIKit)
local Spotlight = require(script.Parent.Spotlight)
local Layout = require(script.Parent.Layout)
local StateController = require(Client.Controllers.StateController)
local MonetizationController = require(Client.Controllers.MonetizationController)

local Theme = UIKit.Theme
local ROBUX_GREEN = Color3.fromRGB(0, 176, 111)

type Row = { refresh: () -> () }

local StoreUI = {}

function StoreUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = UIKit.create("ScreenGui", {
		Name = "Store",
		ResetOnSpawn = false,
		DisplayOrder = 17,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	-- Left column, first menu row (Sound | Store).
	local storePosition, storeSize = Layout.menuSlot("Store")
	local storeButton = UIKit.button({
		Name = "StoreButton",
		Text = "STORE",
		TextSize = Layout.MENU_TEXT_SIZE,
		BackgroundColor3 = ROBUX_GREEN,
		Position = storePosition,
		Size = storeSize,
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
		Position = UDim2.new(0.5, 0, 0.48, 0),
		Size = Layout.windowSize(0.9, 0.82),
		Parent = overlay,
	}, {
		UIKit.corner(14),
		UIKit.padding(14),
		UIKit.create("UISizeConstraint", { MaxSize = Vector2.new(520, 400) }),
	}) :: Frame
	UIKit.label({
		Text = "Store",
		Font = Theme.FontBold,
		TextSize = 22,
		TextColor3 = ROBUX_GREEN,
		Size = UDim2.new(1, -40, 0, 26),
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
	local list = UIKit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 36),
		Size = UDim2.new(1, 0, 1, -36),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = window,
	}, {
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	}) :: ScrollingFrame

	local rows: { Row } = {}
	local order = 0

	local function heading(text: string)
		order += 1
		UIKit.label({
			Text = text,
			Font = Theme.FontBold,
			TextSize = 15,
			TextColor3 = Theme.Muted,
			LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, 20),
			Parent = list,
		})
	end

	-- One store item: name, description, extra line, and a button on the right.
	local function itemRow(title: string, description: string): (TextLabel, TextButton)
		order += 1
		local row = UIKit.create("Frame", {
			LayoutOrder = order,
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -8, 0, 62),
			Parent = list,
		}, { UIKit.corner(8) }) :: Frame
		UIKit.label({
			Text = title,
			Font = Theme.FontBold,
			TextSize = 15,
			Position = UDim2.new(0, 10, 0, 6),
			Size = UDim2.new(1, -130, 0, 18),
			Parent = row,
		})
		UIKit.label({
			Text = description,
			TextColor3 = Theme.Muted,
			TextSize = 12,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.new(0, 10, 0, 26),
			Size = UDim2.new(1, -130, 0, 16),
			Parent = row,
		})
		local extra = UIKit.label({
			Text = "",
			TextColor3 = Theme.Gold,
			TextSize = 12,
			Position = UDim2.new(0, 10, 0, 42),
			Size = UDim2.new(1, -130, 0, 16),
			Parent = row,
		})
		local button = UIKit.button({
			Text = "",
			TextSize = 13,
			BackgroundColor3 = ROBUX_GREEN,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0, 110, 0, 44),
			Parent = row,
		})
		return extra, button
	end

	local anyItems = false

	heading("Game passes (yours forever)")
	for _, passKey in MonetizationConfig.PASS_ORDER do
		local def = MonetizationConfig.PASSES[passKey]
		if def.id > 0 then
			anyItems = true
			local extra, button = itemRow(def.displayName, def.description)
			local function refresh()
				local ownsIt = MonetizationController.owns(passKey)
				if ownsIt and def.toggleable then
					local on = MonetizationController.isOn(passKey)
					extra.Text = "Owned"
					button.Text = if on then "ON" else "OFF"
					button.BackgroundColor3 = if on then Theme.Good else Theme.Disabled
				elseif ownsIt then
					extra.Text = "Owned"
					button.Text = "Owned"
					button.BackgroundColor3 = Theme.Disabled
				else
					local price = MonetizationController.getPrice("Pass", def.id)
					extra.Text = ""
					button.Text = if price ~= nil then `R$ {price}` else "Buy"
					button.BackgroundColor3 = ROBUX_GREEN
				end
			end
			button.Activated:Connect(function()
				if MonetizationController.owns(passKey) then
					if def.toggleable then
						MonetizationController.setToggle(passKey, not MonetizationController.isOn(passKey))
					end
					return
				end
				MonetizationController.promptPass(passKey)
			end)
			table.insert(rows, { refresh = refresh })
		end
	end

	heading("Gold and items (buy any time)")
	for _, productKey in MonetizationConfig.PRODUCT_ORDER do
		local def = MonetizationConfig.PRODUCTS[productKey]
		if def.id > 0 then
			anyItems = true
			local extra, button = itemRow(def.displayName, def.description)
			local function refresh()
				local snapshot = StateController.get()
				if snapshot ~= nil and def.goldMinutes ~= nil then
					-- Same math as the server, for a preview (the server decides the real amount).
					local gold = Formulas.offlineGold(
						snapshot.armyDps,
						snapshot.goldMultiplier,
						Formulas.offlineStage(snapshot.highestStage),
						def.goldMinutes * 60,
						1
					)
					gold = BigNum.max(gold, BigNum.fromNumber(MonetizationConfig.GOLD_PRODUCT_MINIMUM))
					extra.Text = `About {NumberFormat.big(gold)} gold right now`
				elseif snapshot ~= nil and def.forgeTokens ~= nil then
					extra.Text = `You have {snapshot.packs.forge} unused (use them in Shop > Packs)`
				end
				local price = MonetizationController.getPrice("Product", def.id)
				button.Text = if price ~= nil then `R$ {price}` else "Buy"
			end
			button.Activated:Connect(function()
				MonetizationController.promptProduct(productKey)
			end)
			table.insert(rows, { refresh = refresh })
		end
	end

	if not anyItems then
		order += 1
		UIKit.label({
			Text = "The store isn't open yet. Check back soon!",
			TextColor3 = Theme.Muted,
			TextSize = 14,
			LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, 30),
			Parent = list,
		})
	end

	local function refreshAll()
		for _, row in rows do
			task.spawn(row.refresh) -- price lookups yield the first time
		end
	end

	local function openStore()
		UIKit.openModal(overlay, window)
		refreshAll()
	end
	storeButton.Activated:Connect(openStore)
	Spotlight.register("Menu:Store", storeButton)
	Spotlight.registerOpener("Menu:Store", openStore)
	closeButton.Activated:Connect(function()
		overlay.Visible = false
	end)
	StateController.Changed:Connect(function()
		if overlay.Visible then
			refreshAll()
		end
	end)
	Players.LocalPlayer.AttributeChanged:Connect(function()
		if overlay.Visible then
			refreshAll()
		end
	end)

	gui.Parent = playerGui
end

return StoreUI
