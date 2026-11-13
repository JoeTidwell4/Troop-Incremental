--!strict
-- Bottom shop panel with tabs: Troops | Gear | Packs | Honor.
-- The header holds the tab buttons, a short status message, and the buy-mode buttons
-- (x1 / x10 / Max) for tabs that use them. Each tab lives in its own module.
-- On phones (Layout.compact) the shop sits between the left column and the ability
-- column and works as a drawer: HIDE shrinks it to just the header so you can see the
-- fight; tapping any tab (or SHOW) opens it again.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local UIKit = require(script.Parent.UIKit)
local ShopTypes = require(script.Parent.ShopTypes)
local TroopTab = require(script.Parent.TroopTab)
local GearTab = require(script.Parent.GearTab)
local PackTab = require(script.Parent.PackTab)
local HonorTab = require(script.Parent.HonorTab)
local StateController = require(Client.Controllers.StateController)
local Layout = require(script.Parent.Layout)
local Spotlight = require(script.Parent.Spotlight)

type Tab = ShopTypes.Tab

local Theme = UIKit.Theme

local COMPACT = Layout.compact
local HEADER_HEIGHT = Layout.SHOP_HEADER_HEIGHT
local TAB_WIDTH = Layout.SHOP_TAB_WIDTH
local TAB_COUNT = 4 -- Troops, Gear, Packs, Honor (leaves room for the status message)
local MODE_WIDTH = Layout.SHOP_MODE_WIDTH
local TOGGLE_WIDTH = 60 -- compact only: the HIDE / SHOW button
local STATUS_SECONDS = 2

local ALL_MODES = { "One", "Ten", "Max" }
local MODE_LABELS: { [string]: string } = { One = "x1", Ten = "x10", Max = "Max" }
local FAIL_MESSAGES: { [string]: string } = {
	CantAfford = "Not enough gold",
	MaxReached = "Already maxed",
	NoFreePacks = "No free packs left",
	NoHeroChests = "No Hero Chests left",
	CantAffordHonor = "Not enough Honor",
	TooEarly = "Reach the required stage first",
	InRaid = "Finish your raid attack first",
	Locked = "Unlock this troop first",
	Rejected = "Slow down a little!",
}

-- Set once the shop is built; lets other UI (e.g. the HUD Ascend button) switch tabs.
local openTabByTitle: ((title: string) -> ())? = nil

local ShopUI = {}

function ShopUI.openTab(title: string)
	if openTabByTitle ~= nil then
		openTabByTitle(title)
	end
end

function ShopUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = UIKit.create("ScreenGui", {
		Name = "Shop",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	local contentHeight = Layout.SHOP_CONTENT_HEIGHT
	local panelHeight = Layout.SHOP_HEIGHT
	local collapsedHeight = 16 + HEADER_HEIGHT
	local panel = UIKit.panel({
		Name = "Panel",
		AnchorPoint = if COMPACT then Vector2.new(0, 1) else Vector2.new(0.5, 1),
		Position = if COMPACT
			then UDim2.new(0, Layout.SHOP_LEFT, 1, -Layout.SHOP_BOTTOM_MARGIN)
			else UDim2.new(0.5, 0, 1, -Layout.SHOP_BOTTOM_MARGIN),
		Size = if COMPACT
			then UDim2.new(1, -(Layout.SHOP_LEFT + Layout.SHOP_RIGHT), 0, panelHeight)
			else UDim2.new(0.96, 0, 0, panelHeight),
		Parent = gui,
	})
	if not COMPACT then
		UIKit.create("UISizeConstraint", { MaxSize = Vector2.new(780, panelHeight), Parent = panel })
	end

	local content = UIKit.create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, HEADER_HEIGHT + 6),
		Size = UDim2.new(1, 0, 0, contentHeight),
		Parent = panel,
	}) :: Frame

	-- Status message: in the header between tabs and mode buttons on desktop; floating
	-- just above the panel on phones (the header is full there).
	local modeSpace = 3 * (MODE_WIDTH + 6) + (if COMPACT then TOGGLE_WIDTH + 6 else 0)
	local statusLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.HpFill,
		Font = if COMPACT then Theme.FontBold else Theme.Font,
		TextSize = if COMPACT then 16 else 14,
		TextStrokeTransparency = if COMPACT then 0.3 else 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = if COMPACT then UDim2.new(0, 0, 0, -36) else UDim2.new(0, TAB_COUNT * (TAB_WIDTH + 6), 0, 0),
		Size = if COMPACT
			then UDim2.new(1, 0, 0, 22)
			else UDim2.new(1, -TAB_COUNT * (TAB_WIDTH + 6) - modeSpace, 0, HEADER_HEIGHT),
		Parent = panel,
	})
	local statusToken = 0
	local function showStatus(text: string)
		statusToken += 1
		local token = statusToken
		statusLabel.Text = text
		task.delay(STATUS_SECONDS, function()
			if statusToken == token then
				statusLabel.Text = ""
			end
		end)
	end

	local selectedMode = "One"
	local context: ShopTypes.Context = {
		getMode = function(): string
			return selectedMode
		end,
		showStatus = showStatus,
		failMessage = function(reason: string?): string
			return FAIL_MESSAGES[reason or ""] or "Still loading, try again"
		end,
	}

	local tabs: { Tab } = {
		TroopTab.build(content, context),
		GearTab.build(content, context),
		PackTab.build(content, context),
		HonorTab.build(content, context),
	}
	local activeTab = tabs[1]
	local tabButtons: { [Tab]: TextButton } = {}
	local modeButtons: { [string]: TextButton } = {}

	-- Compact drawer: open (full height) or hidden (header only).
	local open = true
	local toggleButton: TextButton? = nil
	local function setOpen(value: boolean)
		if value == open then
			return
		end
		open = value
		content.Visible = open
		local height = if open then panelHeight else collapsedHeight
		TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(panel.Size.X.Scale, panel.Size.X.Offset, 0, height),
		}):Play()
		if toggleButton ~= nil then
			toggleButton.Text = if open then "HIDE" else "SHOW"
		end
	end

	local function render()
		local snapshot = StateController.get()
		for tab, button in tabButtons do
			local active = tab == activeTab
			tab.frame.Visible = active
			button.BackgroundColor3 = if active then Theme.Accent else Theme.PanelLight
		end
		-- Only show the mode buttons this tab uses; fall back to x1 if the mode isn't allowed.
		if #activeTab.modes > 0 and table.find(activeTab.modes, selectedMode) == nil then
			selectedMode = "One"
		end
		for mode, button in modeButtons do
			button.Visible = table.find(activeTab.modes, mode) ~= nil
			button.BackgroundColor3 = if mode == selectedMode then Theme.Accent else Theme.PanelLight
		end
		if snapshot ~= nil then
			activeTab.render(snapshot)
		end
	end

	for index, tab in tabs do
		local button = UIKit.button({
			Name = tab.title,
			Text = tab.title,
			TextSize = 14,
			BackgroundColor3 = Theme.PanelLight,
			Position = UDim2.new(0, (index - 1) * (TAB_WIDTH + 6), 0, 1),
			Size = UDim2.new(0, TAB_WIDTH, 0, HEADER_HEIGHT - 2),
			Parent = panel,
		})
		button.Activated:Connect(function()
			activeTab = tab
			setOpen(true)
			render()
		end)
		tabButtons[tab] = button
		Spotlight.register(`Tab:{tab.title}`, button)
	end

	for index, mode in ALL_MODES do
		local button = UIKit.button({
			Name = mode,
			Text = MODE_LABELS[mode],
			TextSize = 14,
			BackgroundColor3 = Theme.PanelLight,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(
				1,
				-(#ALL_MODES - index) * (MODE_WIDTH + 6) - (if COMPACT then TOGGLE_WIDTH + 6 else 0),
				0,
				1
			),
			Size = UDim2.new(0, MODE_WIDTH, 0, HEADER_HEIGHT - 2),
			Parent = panel,
		})
		button.Activated:Connect(function()
			selectedMode = mode
			render()
		end)
		modeButtons[mode] = button
	end

	if COMPACT then
		local button = UIKit.button({
			Name = "Toggle",
			Text = "HIDE",
			TextSize = 14,
			BackgroundColor3 = Theme.PanelLight,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 1),
			Size = UDim2.new(0, TOGGLE_WIDTH, 0, HEADER_HEIGHT - 2),
			Parent = panel,
		})
		button.Activated:Connect(function()
			setOpen(not open)
		end)
		toggleButton = button
	end

	openTabByTitle = function(title: string)
		for _, tab in tabs do
			if tab.title == title then
				activeTab = tab
				setOpen(true)
				render()
			end
		end
	end

	StateController.Changed:Connect(render)
	render()

	gui.Parent = playerGui
end

return ShopUI
