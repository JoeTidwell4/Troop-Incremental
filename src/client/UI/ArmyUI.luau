--!strict
-- The ARMY hub (menu button): one window for building your army's kit. Phase 13a has the
-- Abilities tab; Skills, Generals and Relics join it in later phases (ArmyTabs below).
--
-- Abilities tab: the 3 equipped slots (keys 1/2/3) and every ability, with buttons to
-- equip it in a slot. The server decides (unlocked, not mid-boss, swap cooldown).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local AbilityConfig = require(Shared:WaitForChild("Config"):WaitForChild("AbilityConfig"))
local GeneralConfig = require(Shared:WaitForChild("Config"):WaitForChild("GeneralConfig"))
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)
local Spotlight = require(script.Parent.Spotlight)
local SkillsTab = require(script.Parent.SkillsTab)
local GeneralsTab = require(script.Parent.GeneralsTab)
local RelicsTab = require(script.Parent.RelicsTab)
local StateController = require(Client.Controllers.StateController)
local AbilityController = require(Client.Controllers.AbilityController)

type Snapshot = Types.Snapshot
type Tab = { title: string, frame: Frame, render: (snapshot: Snapshot) -> () }

local Theme = UIKit.Theme
local fmt = NumberFormat.number
local EQUIPPED_COLOR = Color3.fromRGB(80, 160, 255)

local ArmyUI = {}

local openWindow: ((tabTitle: string?) -> ())? = nil

-- Opens the ARMY window, optionally on a tab ("Abilities").
function ArmyUI.open(tabTitle: string?)
	if openWindow ~= nil then
		openWindow(tabTitle)
	end
end

-- One line of stats for an ability, e.g. "Cooldown 60s  |  lasts 10s".
local function statsLine(abilityId: string, upgrades: { [string]: number }, skillRanks: { [string]: number }): string
	local stats = Formulas.abilityStats(abilityId, upgrades, skillRanks)
	local parts = { `Cooldown {fmt(stats.cooldown)}s` }
	if stats.duration ~= nil then
		table.insert(parts, `lasts {fmt(stats.duration)}s`)
	end
	if stats.tapMultiplier ~= nil then
		table.insert(parts, `x{fmt(stats.tapMultiplier)} clicks`)
	end
	if stats.damageMultiplier ~= nil then
		table.insert(parts, `x{fmt(stats.damageMultiplier)} damage`)
	end
	if stats.goldMultiplier ~= nil then
		table.insert(parts, `x{fmt(stats.goldMultiplier)} gold`)
	end
	if stats.burstDpsSeconds ~= nil then
		table.insert(parts, `{fmt(stats.burstDpsSeconds)}s of damage`)
	end
	if stats.healFraction ~= nil then
		table.insert(parts, `heals {math.floor(stats.healFraction * 100 + 0.5)}%`)
	end
	if stats.bountyKills ~= nil then
		table.insert(parts, `{math.floor(stats.bountyKills)} kills`)
	end
	return table.concat(parts, "  |  ")
end

local function buildAbilitiesTab(parent: Instance): Tab
	local frame = UIKit.create("Frame", {
		Name = "Abilities",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = parent,
	}) :: Frame

	-- Equipped slots.
	local maxSlots = #AbilityConfig.SLOT_KEYS
	local slotLabels: { TextLabel } = {}
	local slotCards: { Frame } = {}
	for slot = 1, maxSlots do
		local card = UIKit.create("Frame", {
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1 / AbilityConfig.LOADOUT_SLOTS, -6, 0, 44),
			Parent = frame,
		}, { UIKit.corner(8), UIKit.create("UIStroke", { Color = EQUIPPED_COLOR, Thickness = 2 }) }) :: Frame
		slotCards[slot] = card
		UIKit.label({
			Text = if Layout.compact then `Slot {slot}` else `Slot {slot}  (key {slot})`,
			TextColor3 = Theme.Muted,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 0, 0, 3),
			Size = UDim2.new(1, 0, 0, 14),
			Parent = card,
		})
		slotLabels[slot] = UIKit.label({
			Text = "",
			Font = Theme.FontBold,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 0, 0, 18),
			Size = UDim2.new(1, 0, 0, 22),
			Parent = card,
		})
	end
	UIKit.label({
		Text = "Swap abilities any time outside boss fights. A newly equipped one needs "
			.. `{AbilityConfig.SWAP_COOLDOWN}s before it's ready.`,
		TextColor3 = Theme.Muted,
		TextSize = 11,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Position = UDim2.new(0, 0, 0, 48),
		Size = UDim2.new(1, 0, 0, 28),
		Parent = frame,
	})

	local list = UIKit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 80),
		Size = UDim2.new(1, 0, 1, -80),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = frame,
	}, {
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		UIKit.create("UIPadding", { PaddingRight = UDim.new(0, 8) }),
	}) :: ScrollingFrame

	type Row = { frame: Frame, name: TextLabel, stats: TextLabel, status: TextLabel, buttons: { TextButton } }
	local rows: { [string]: Row } = {}
	for order, abilityId in AbilityConfig.ORDER do
		local def = AbilityConfig.ABILITIES[abilityId]
		local row = UIKit.create("Frame", {
			LayoutOrder = order,
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 62),
			Parent = list,
		}, { UIKit.corner(8) }) :: Frame
		local name = UIKit.label({ Text = def.displayName, Font = Theme.FontBold, TextSize = 15, Position = UDim2.new(0, 10, 0, 4), Size = UDim2.new(1, -150, 0, 18), Parent = row })
		UIKit.label({ Text = def.description, TextSize = 12, Position = UDim2.new(0, 10, 0, 22), Size = UDim2.new(1, -150, 0, 16), Parent = row })
		local stats = UIKit.label({ Text = "", TextColor3 = Theme.Muted, TextSize = 11, Position = UDim2.new(0, 10, 0, 40), Size = UDim2.new(1, -150, 0, 16), Parent = row })
		local status = UIKit.label({
			Text = "",
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 4),
			Size = UDim2.new(0, 132, 0, 16),
			Parent = row,
		})
		local buttons: { TextButton } = {}
		for slot = 1, maxSlots do
			local button = UIKit.button({
				Text = tostring(slot),
				TextSize = 14,
				BackgroundColor3 = Theme.Panel,
				AnchorPoint = Vector2.new(1, 1),
				Size = UDim2.new(0, 34, 0, 30),
				Parent = row,
			})
			button.Activated:Connect(function()
				AbilityController.equip(slot, abilityId)
			end)
			buttons[slot] = button
		end
		rows[abilityId] = { frame = row, name = name, stats = stats, status = status, buttons = buttons }
	end

	local function render(snapshot: Snapshot)
		local loadout = snapshot.abilityLoadout
		local inBoss = snapshot.encounter ~= "Normal"
		local slots = Formulas.loadoutSlots(snapshot.skillRanks)
		for slot, label in slotLabels do
			local def = AbilityConfig.ABILITIES[loadout[slot] or ""]
			label.Text = if def ~= nil then def.displayName else "(empty)"
			local card = slotCards[slot]
			card.Visible = slot <= slots
			card.Position = UDim2.new((slot - 1) / slots, 3, 0, 0)
			card.Size = UDim2.new(1 / slots, -6, 0, 44)
		end
		for _, abilityId in AbilityConfig.ORDER do
			local def = AbilityConfig.ABILITIES[abilityId]
			local row = rows[abilityId]
			local unlocked = snapshot.bestStage >= def.unlockStage
			local equippedSlot = table.find(loadout, abilityId)
			row.frame.BackgroundTransparency = if unlocked then 0 else 0.45
			row.name.TextColor3 = if equippedSlot ~= nil then EQUIPPED_COLOR else Theme.Text
			row.stats.Text = statsLine(abilityId, snapshot.abilityUpgrades, snapshot.skillRanks)
			row.status.Text = if not unlocked then `Unlocks at stage {def.unlockStage}`
				elseif equippedSlot ~= nil then `Equipped (slot {equippedSlot})`
				elseif inBoss then "Swap after this fight"
				else "Not equipped"
			row.status.TextColor3 = if equippedSlot ~= nil then EQUIPPED_COLOR elseif unlocked then Theme.Muted else Theme.HpFill
			for slot, button in row.buttons do
				local usable = unlocked and not inBoss and equippedSlot ~= slot
				button.Visible = unlocked and slot <= slots
				button.Position = UDim2.new(1, -6 - (slots - slot) * 38, 1, -6)
				button.BackgroundColor3 = if equippedSlot == slot then EQUIPPED_COLOR elseif usable then Theme.Accent else Theme.Disabled
				button.AutoButtonColor = usable
			end
		end
	end

	return { title = "Abilities", frame = frame, render = render }
end

function ArmyUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = UIKit.create("ScreenGui", {
		Name = "Army",
		ResetOnSpawn = false,
		DisplayOrder = 15,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	local menuPosition, menuSize = Layout.menuSlot("Army")
	local menuButton = UIKit.button({
		Name = "ArmyButton",
		Text = "ARMY",
		TextSize = Layout.MENU_TEXT_SIZE,
		BackgroundColor3 = Color3.fromRGB(70, 110, 200),
		Position = menuPosition,
		Size = menuSize,
		Parent = gui,
	})
	Spotlight.register("Menu:Army", menuButton)
	-- Red dot: unspent skill points.
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
	UIKit.label({ Text = "ARMY", Font = Theme.FontBold, TextSize = 24, TextColor3 = Theme.Gold, Size = UDim2.new(1, -50, 0, 28), Parent = window })
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

	local tabs: { Tab } = { buildAbilitiesTab(content), SkillsTab.build(content), GeneralsTab.build(content), RelicsTab.build(content) }
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
		Spotlight.register(`Army:{tab.title}`, button)
		Spotlight.registerOpener(`Army:{tab.title}`, function()
			ArmyUI.open(tab.title)
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
		ArmyUI.open()
	end)
	Spotlight.registerOpener("Menu:Army", function()
		ArmyUI.open()
	end)
	closeButton.Activated:Connect(function()
		overlay.Visible = false
	end)
	StateController.Changed:Connect(function(snapshot: Snapshot)
		-- Red dot: skill points to spend, or Recruit Scrolls once Generals are unlocked.
		dot.Visible = SkillsTab.unspentPoints(snapshot) > 0
			or (snapshot.bestStage >= GeneralConfig.UNLOCK_STAGE and snapshot.generals.scrolls > 0)
		render()
	end)

	gui.Parent = playerGui
end

return ArmyUI
