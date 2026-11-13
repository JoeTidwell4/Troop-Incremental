--!strict
-- Epic Forge picker: choose a troop's Weapon or Armor to turn Epic with one Epic Forge
-- token (Robux product). Opened from the Packs tab. The server checks everything again
-- (token owned, troop unlocked, slot below Epic) before changing anything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local GearInfo = require(Shared:WaitForChild("GearInfo"))
local Config = Shared:WaitForChild("Config")
local TroopConfig = require(Config:WaitForChild("TroopConfig"))
local GearConfig = require(Config:WaitForChild("GearConfig"))
local PackConfig = require(Config:WaitForChild("PackConfig"))
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)
local PackRevealUI = require(script.Parent.PackRevealUI)
local StateController = require(Client.Controllers.StateController)
local ShopController = require(Client.Controllers.ShopController)

type Snapshot = Types.Snapshot

local Theme = UIKit.Theme

local ROW_HEIGHT = if Layout.compact then 46 else 40

local MESSAGES: { [string]: string } = {
	NoForgeTokens = "You don't have an Epic Forge token.",
	AlreadyEpic = "That one is already Epic or better.",
	Locked = "Unlock this troop first.",
}

local ForgeUI = {}

local openWindow: (() -> ())? = nil

function ForgeUI.open()
	if openWindow ~= nil then
		openWindow()
	end
end

function ForgeUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = UIKit.create("ScreenGui", {
		Name = "Forge",
		ResetOnSpawn = false,
		DisplayOrder = 19,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

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
		UIKit.create("UISizeConstraint", { MaxSize = Vector2.new(520, 420) }),
	}) :: Frame
	UIKit.label({
		Text = "Epic Forge",
		Font = Theme.FontBold,
		TextSize = 22,
		TextColor3 = GearInfo.rarity(PackConfig.FORGE_RARITY).color,
		Size = UDim2.new(1, -50, 0, 26),
		Parent = window,
	})
	local subtitle = UIKit.label({
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
	local list = UIKit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 50),
		Size = UDim2.new(1, 0, 1, -50),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = window,
	}, {
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		UIKit.create("UIPadding", { PaddingRight = UDim.new(0, 10) }),
	}) :: ScrollingFrame

	local busy = false
	local rows: { [string]: { frame: Frame, buttons: { [string]: TextButton } } } = {}

	local function forge(troopId: string, slot: string)
		if busy then
			return
		end
		busy = true
		task.spawn(function()
			local result = ShopController.useForge(troopId, slot)
			busy = false
			if result.ok then
				overlay.Visible = false
				PackRevealUI.show(result)
			else
				subtitle.Text = MESSAGES[result.reason or ""] or "Couldn't forge that, try again."
			end
		end)
	end

	for order, troopId in TroopConfig.ORDER do
		local def = TroopConfig.TROOPS[troopId]
		local row = UIKit.create("Frame", {
			Name = troopId,
			LayoutOrder = order,
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			Parent = list,
		}, { UIKit.corner(8) }) :: Frame
		UIKit.label({
			Text = def.displayName,
			Font = Theme.FontBold,
			TextSize = 15,
			Position = UDim2.new(0, 10, 0, 0),
			Size = UDim2.new(0.3, -10, 1, 0),
			Parent = row,
		})
		local buttons: { [string]: TextButton } = {}
		for index, slot in GearConfig.SLOTS do
			local button = UIKit.button({
				Text = "",
				TextSize = 12,
				Position = UDim2.new(0.3 + (index - 1) * 0.35, 4, 0, 4),
				Size = UDim2.new(0.35, -8, 1, -8),
				Parent = row,
			})
			button.Activated:Connect(function()
				forge(troopId, slot)
			end)
			buttons[slot] = button
		end
		rows[troopId] = { frame = row, buttons = buttons }
	end

	local function render(snapshot: Snapshot)
		local tokens = snapshot.packs.forge
		subtitle.Text = `Tokens: {tokens}. Pick a slot to make it Epic. Gear resets when you Ascend.`
		for troopId, row in rows do
			row.frame.Visible = Formulas.troopUnlocked(troopId, snapshot.bestStage)
			for slot, button in row.buttons do
				local troopGear = snapshot.gear[troopId]
				local state: Types.GearSlotState = if troopGear == nil
					then { level = 0, rarity = 1 }
					elseif slot == "weapon" then troopGear.weapon
					else troopGear.armor
				local rarity = GearInfo.rarity(state.rarity)
				local canForge = tokens > 0 and state.rarity < PackConfig.FORGE_RARITY
				button.Text = `{GearConfig.SLOT_INFO[slot].displayName}\n{rarity.name}`
				button.BackgroundColor3 = if canForge then Theme.Accent else Theme.Disabled
				button.AutoButtonColor = canForge
			end
		end
	end

	openWindow = function()
		local snapshot = StateController.get()
		if snapshot ~= nil then
			render(snapshot)
		end
		UIKit.openModal(overlay, window)
	end
	StateController.Changed:Connect(function(snapshot: Snapshot)
		if overlay.Visible then
			render(snapshot)
		end
	end)
	closeButton.Activated:Connect(function()
		overlay.Visible = false
	end)

	gui.Parent = playerGui
end

return ForgeUI
