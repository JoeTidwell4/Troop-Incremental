--!strict
-- The ADVENTURE hub (menu button): one window for the game modes outside the main run.
-- Tabs: Challenges (13e), Tower (13f), Expeditions (13g). Each tab shows its own
-- "locked until..." message. Red dot on the button when the Tower Tribute is ready or a team is back.
--
-- While you're in a challenge a banner takes the Ascend button's place in the menu
-- column (a challenge run can't be Ascended, so that spot is free): the challenge, its
-- rule and the next goal. Clicking it opens the Challenges tab (where Leave is).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local ChallengeConfig = require(Shared:WaitForChild("Config"):WaitForChild("ChallengeConfig"))
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)
local Spotlight = require(script.Parent.Spotlight)
local ChallengesTab = require(script.Parent.ChallengesTab)
local TowerTab = require(script.Parent.TowerTab)
local ExpeditionsTab = require(script.Parent.ExpeditionsTab)
local ExpeditionController = require(Client.Controllers.ExpeditionController)
local StateController = require(Client.Controllers.StateController)

type Snapshot = Types.Snapshot
type Tab = { title: string, frame: Frame, render: (snapshot: Snapshot) -> () }

local Theme = UIKit.Theme

local AdventureUI = {}

local openWindow: ((tabTitle: string?) -> ())? = nil

-- Opens the ADVENTURE window, optionally on a tab ("Challenges").
function AdventureUI.open(tabTitle: string?)
	if openWindow ~= nil then
		openWindow(tabTitle)
	end
end

function AdventureUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = UIKit.create("ScreenGui", {
		Name = "Adventure",
		ResetOnSpawn = false,
		DisplayOrder = 15,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	local menuPosition, menuSize = Layout.menuSlot("Adventure")
	local menuButton = UIKit.button({
		Name = "AdventureButton",
		Text = "ADVENTURE",
		TextSize = Layout.MENU_TEXT_SIZE,
		BackgroundColor3 = Color3.fromRGB(200, 110, 50),
		Position = menuPosition,
		Size = menuSize,
		Parent = gui,
	})
	Spotlight.register("Menu:Adventure", menuButton)
	-- Red dot: the daily Tower Tribute is waiting.
	local dot = UIKit.create("Frame", {
		Name = "Dot",
		BackgroundColor3 = Color3.fromRGB(230, 60, 60),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(14, 14),
		Visible = false,
		ZIndex = 5,
		Parent = menuButton,
	}, { UIKit.corner(7) }) :: Frame

	-- In-challenge banner (in the Ascend button's spot).
	local banner = UIKit.button({
		Name = "ChallengeBanner",
		Text = "",
		TextSize = if Layout.compact then 12 else 13,
		BackgroundColor3 = Theme.PanelLight,
		Position = Layout.columnPosition(0, Layout.ASCEND_TOP),
		Size = UDim2.new(0, Layout.COLUMN_WIDTH, 0, Layout.ASCEND_HEIGHT),
		Visible = false,
		Parent = gui,
	})
	banner.TextWrapped = true
	local bannerStroke = banner:FindFirstChildOfClass("UIStroke") :: UIStroke -- UIKit buttons come with one
	bannerStroke.Thickness = 2
	bannerStroke.Transparency = 0
	Spotlight.register("ChallengeBanner", banner)

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
		Size = Layout.windowSize(0.7, 0.85),
		Parent = overlay,
	}, {
		UIKit.corner(14),
		UIKit.padding(14),
		UIKit.create("UISizeConstraint", { MaxSize = Vector2.new(680, 500) }),
	}) :: Frame
	UIKit.label({ Text = "ADVENTURE", Font = Theme.FontBold, TextSize = 24, TextColor3 = Theme.Gold, Size = UDim2.new(1, -50, 0, 28), Parent = window })
	local closeButton = UIKit.button({
		Text = "X",
		TextSize = 16,
		BackgroundColor3 = Theme.PanelLight,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(Layout.CLOSE_SIZE, Layout.CLOSE_SIZE),
		Parent = window,
	})
	local content = UIKit.create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 72),
		Size = UDim2.new(1, 0, 1, -72),
		Parent = window,
	}) :: Frame

	local tabs: { Tab } = { ChallengesTab.build(content), TowerTab.build(content), ExpeditionsTab.build(content) }
	local activeTab = tabs[1]
	local tabButtons: { [Tab]: TextButton } = {}

	local function render()
		local snapshot = StateController.get()
		if snapshot == nil or not overlay.Visible then
			return
		end
		for tab, button in tabButtons do
			tab.frame.Visible = tab == activeTab
			button.BackgroundColor3 = if tab == activeTab then Theme.Accent else Theme.PanelLight
		end
		activeTab.render(snapshot)
	end

	for index, tab in tabs do
		local button = UIKit.button({
			Text = tab.title,
			TextSize = 14,
			BackgroundColor3 = Theme.PanelLight,
			Position = UDim2.new(0, (index - 1) * 116, 0, 34),
			Size = UDim2.new(0, 110, 0, 30),
			Parent = window,
		})
		button.Activated:Connect(function()
			activeTab = tab
			render()
		end)
		tabButtons[tab] = button
		Spotlight.register(`Adventure:{tab.title}`, button)
		Spotlight.registerOpener(`Adventure:{tab.title}`, function()
			AdventureUI.open(tab.title)
		end)
	end

	openWindow = function(tabTitle: string?)
		for _, tab in tabs do
			if tab.title == tabTitle then
				activeTab = tab
			end
		end
		UIKit.openModal(overlay, window)
		render()
	end
	menuButton.Activated:Connect(function()
		AdventureUI.open()
	end)
	banner.Activated:Connect(function()
		AdventureUI.open("Challenges")
	end)
	Spotlight.registerOpener("Menu:Adventure", function()
		AdventureUI.open()
	end)
	closeButton.Activated:Connect(function()
		overlay.Visible = false
	end)

	local wasActive = ""
	local wasInTower = false
	StateController.Changed:Connect(function(snapshot: Snapshot)
		dot.Visible = snapshot.towerTributeReady or ExpeditionController.readyCount(snapshot) > 0
		-- A Tower fight just started: show the fight.
		local inTower = snapshot.towerFloor > 0
		if inTower and not wasInTower then
			overlay.Visible = false
		end
		wasInTower = inTower
		local def = ChallengeConfig.CHALLENGES[snapshot.challengeActive]
		banner.Visible = def ~= nil
		if def ~= nil then
			local goal = Formulas.challengeGoal((snapshot.challengeTiers[def.id] or 0) + 1)
			local goalText = if goal ~= nil then `Goal: beat boss {goal}` else "All tiers cleared"
			banner.Text = `CHALLENGE: {def.name}\n{goalText}`
			banner.TextColor3 = def.color
			bannerStroke.Color = def.color
		end
		-- Starting or ending a challenge swaps the whole run: get the window out of the way.
		if snapshot.challengeActive ~= wasActive then
			wasActive = snapshot.challengeActive
			overlay.Visible = false
		end
		render()
	end)

	gui.Parent = playerGui
end

return AdventureUI
