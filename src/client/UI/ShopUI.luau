--!strict
-- Bottom shop panel with tabs: Troops | Gear | Packs | Honor.
-- The header holds the tab buttons, a short status message, and the buy-mode buttons
-- (x1 / x10 / Max) for tabs that use them. Each tab lives in its own module.

local Players = game:GetService("Players")

local Client = script.Parent.Parent
local UIKit = require(script.Parent.UIKit)
local ShopTypes = require(script.Parent.ShopTypes)
local TroopTab = require(script.Parent.TroopTab)
local GearTab = require(script.Parent.GearTab)
local PackTab = require(script.Parent.PackTab)
local HonorTab = require(script.Parent.HonorTab)
local StateController = require(Client.Controllers.StateController)

type Tab = ShopTypes.Tab

local Theme = UIKit.Theme

local ROW_HEIGHT = 56
local ROWS = 3
local HEADER_HEIGHT = 30
local TAB_WIDTH = 66
local TAB_COUNT = 4 -- Troops, Gear, Packs, Honor (leaves room for the status message)
local MODE_WIDTH = 52
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

	local contentHeight = ROWS * ROW_HEIGHT + (ROWS - 1) * 6
	local panelHeight = 16 + HEADER_HEIGHT + 6 + contentHeight
	local panel = UIKit.panel({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(0.96, 0, 0, panelHeight),
		Parent = gui,
	})
	UIKit.create("UISizeConstraint", { MaxSize = Vector2.new(780, panelHeight), Parent = panel })

	local content = UIKit.create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, HEADER_HEIGHT + 6),
		Size = UDim2.new(1, 0, 0, contentHeight),
		Parent = panel,
	}) :: Frame

	-- Header: status message (between tabs and mode buttons).
	local statusLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.HpFill,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, TAB_COUNT * (TAB_WIDTH + 6), 0, 0),
		Size = UDim2.new(1, -TAB_COUNT * (TAB_WIDTH + 6) - 3 * (MODE_WIDTH + 6), 0, HEADER_HEIGHT),
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
			render()
		end)
		tabButtons[tab] = button
	end

	for index, mode in ALL_MODES do
		local button = UIKit.button({
			Name = mode,
			Text = MODE_LABELS[mode],
			TextSize = 14,
			BackgroundColor3 = Theme.PanelLight,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(#ALL_MODES - index) * (MODE_WIDTH + 6), 0, 1),
			Size = UDim2.new(0, MODE_WIDTH, 0, HEADER_HEIGHT - 2),
			Parent = panel,
		})
		button.Activated:Connect(function()
			selectedMode = mode
			render()
		end)
		modeButtons[mode] = button
	end

	openTabByTitle = function(title: string)
		for _, tab in tabs do
			if tab.title == title then
				activeTab = tab
				render()
			end
		end
	end

	StateController.Changed:Connect(render)
	render()

	gui.Parent = playerGui
end

return ShopUI
