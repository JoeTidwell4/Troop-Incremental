--!strict
-- Bottom panel for training troops: one row per troop type, plus x1 / x10 / Max.
-- Prices shown here are calculated locally for display. The server re-checks
-- everything when you actually click Buy.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local TroopConfig = require(Shared:WaitForChild("Config"):WaitForChild("TroopConfig"))
local UIKit = require(script.Parent.UIKit)
local StateController = require(Client.Controllers.StateController)
local TroopController = require(Client.Controllers.TroopController)

type Snapshot = Types.Snapshot
type BuyMode = Types.BuyMode

local Theme = UIKit.Theme
local format = NumberFormat.big

local MODES: { BuyMode } = { "One", "Ten", "Max" }
local MODE_LABELS: { [string]: string } = { One = "x1", Ten = "x10", Max = "Max" }
local FAIL_MESSAGES: { [string]: string } = {
	CantAfford = "Not enough gold",
	MaxReached = "Max troops reached",
	Rejected = "Slow down a little!",
}
local ROW_HEIGHT = 56
local STATUS_SECONDS = 2

type Row = {
	owned: TextLabel,
	info: TextLabel,
	button: TextButton,
}

local selectedMode: BuyMode = "One"
local rows: { [string]: Row } = {}
local modeButtons: { [string]: TextButton } = {}
local pending: { [string]: boolean } = {}
local statusLabel: TextLabel
local statusToken = 0

local TroopShopUI = {}

-- Works out what the buy button for one troop should say, using the current mode.
local function previewPurchase(troopId: string, snapshot: Snapshot): (number, BigNum.BigNum, boolean)
	local owned = snapshot.troops[troopId] or 0
	local cap = math.min(TroopConfig.MAX_BUY_PER_REQUEST, TroopConfig.MAX_PER_TYPE - owned)
	if selectedMode == "Max" then
		local amount, cost = Formulas.maxAffordable(troopId, owned, snapshot.gold, cap)
		if amount > 0 then
			return amount, cost, true
		end
		-- Can't afford any: show the price of one so the player knows what to save for.
		return 1, Formulas.troopCost(troopId, owned, 1), false
	end
	local amount = if selectedMode == "Ten" then 10 else 1
	local cost = Formulas.troopCost(troopId, owned, amount)
	return amount, cost, amount <= cap and BigNum.gte(snapshot.gold, cost)
end

local function render()
	local snapshot = StateController.get()
	if snapshot == nil then
		return
	end
	for _, troopId in TroopConfig.ORDER do
		local row = rows[troopId]
		local owned = snapshot.troops[troopId] or 0
		local nextMilestone = Formulas.nextMilestone(owned)
		row.owned.Text = `Owned: {owned}`
		row.info.Text = `DPS {format(Formulas.troopDps(troopId, owned))}  |  HP {format(
			Formulas.troopHp(troopId, owned)
		)}  |  x{TroopConfig.MILESTONE_MULTIPLIER} at {nextMilestone}`

		local amount, cost, affordable = previewPurchase(troopId, snapshot)
		row.button.Text = `Buy x{amount}\n{format(cost)} gold`
		row.button.BackgroundColor3 = if affordable then Theme.Good else Theme.Disabled
		row.button.AutoButtonColor = affordable
	end
	for mode, button in modeButtons do
		button.BackgroundColor3 = if mode == selectedMode then Theme.Accent else Theme.PanelLight
	end
end

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

local function onBuyClicked(troopId: string)
	if pending[troopId] then
		return
	end
	pending[troopId] = true
	task.spawn(function()
		local result = TroopController.buy(troopId, selectedMode)
		pending[troopId] = nil
		if not result.ok then
			showStatus(FAIL_MESSAGES[result.reason or ""] or "Still loading, try again")
		end
	end)
end

local function buildRow(troopId: string, order: number, parent: Instance)
	local def = TroopConfig.TROOPS[troopId]

	local frame = UIKit.create("Frame", {
		Name = troopId,
		LayoutOrder = order,
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		Parent = parent,
	}, { UIKit.corner(8) }) :: Frame

	UIKit.create("Frame", {
		Name = "Swatch",
		BackgroundColor3 = def.color,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 8, 0, 8),
		Size = UDim2.new(0, 6, 1, -16),
		Parent = frame,
	}, { UIKit.corner(3) })

	UIKit.label({
		Text = def.displayName,
		Font = Theme.FontBold,
		TextSize = 17,
		Position = UDim2.new(0, 22, 0, 6),
		Size = UDim2.new(0.3, -22, 0, 20),
		Parent = frame,
	})
	local owned = UIKit.label({
		Text = "Owned: 0",
		TextColor3 = Theme.Gold,
		TextSize = 14,
		Position = UDim2.new(0.3, 0, 0, 6),
		Size = UDim2.new(0.7, -160, 0, 20),
		Parent = frame,
	})
	UIKit.label({
		Text = def.role,
		TextColor3 = Theme.Muted,
		TextSize = 12,
		Position = UDim2.new(0, 22, 0, 30),
		Size = UDim2.new(0.3, -22, 0, 18),
		Parent = frame,
	})
	local info = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 12,
		Position = UDim2.new(0.3, 0, 0, 30),
		Size = UDim2.new(0.7, -160, 0, 18),
		Parent = frame,
	})
	local button = UIKit.button({
		Name = "Buy",
		Text = "",
		TextSize = 14,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.new(0, 144, 1, -10),
		Parent = frame,
	})
	button.Activated:Connect(function()
		onBuyClicked(troopId)
	end)

	rows[troopId] = { owned = owned, info = info, button = button }
end

function TroopShopUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = UIKit.create("ScreenGui", {
		Name = "TroopShop",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	local rowCount = #TroopConfig.ORDER
	local panelHeight = 16 + 30 + 6 + rowCount * (ROW_HEIGHT + 6)
	local panel = UIKit.panel({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(0.96, 0, 0, panelHeight),
		Parent = gui,
	})
	UIKit.create("UISizeConstraint", { MaxSize = Vector2.new(760, panelHeight), Parent = panel })

	UIKit.label({
		Text = "Train Troops",
		Font = Theme.FontBold,
		TextSize = 18,
		Size = UDim2.new(0, 140, 0, 30),
		Parent = panel,
	})
	statusLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.HpFill,
		TextSize = 14,
		Position = UDim2.new(0, 146, 0, 0),
		Size = UDim2.new(1, -146 - 3 * 62, 0, 30),
		Parent = panel,
	})

	for index, mode in MODES do
		local button = UIKit.button({
			Name = mode,
			Text = MODE_LABELS[mode],
			BackgroundColor3 = Theme.PanelLight,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(#MODES - index) * 62, 0, 1),
			Size = UDim2.new(0, 56, 0, 28),
			Parent = panel,
		})
		button.Activated:Connect(function()
			selectedMode = mode
			render()
		end)
		modeButtons[mode] = button
	end

	local list = UIKit.create("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 36),
		Size = UDim2.new(1, 0, 1, -36),
		Parent = panel,
	}, {
		UIKit.create("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	for order, troopId in TroopConfig.ORDER do
		buildRow(troopId, order, list)
	end

	StateController.Changed:Connect(render)
	render()

	gui.Parent = playerGui
end

return TroopShopUI
