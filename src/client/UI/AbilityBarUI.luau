--!strict
-- Ability buttons on the right side of the screen, with cooldown countdowns.
-- Cooldowns are drawn from server timestamps, so they're accurate without extra messages.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local AbilityConfig = require(Shared:WaitForChild("Config"):WaitForChild("AbilityConfig"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)
local Spotlight = require(script.Parent.Spotlight)
local StateController = require(Client.Controllers.StateController)
local AbilityController = require(Client.Controllers.AbilityController)

local Theme = UIKit.Theme

local BUTTON_SIZE = Layout.ABILITY_SIZE
local GAP = 6
local UPDATE_INTERVAL = 0.1

-- Number keys shown on the buttons.
local KEY_LABELS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.One] = "1",
	[Enum.KeyCode.Two] = "2",
	[Enum.KeyCode.Three] = "3",
	[Enum.KeyCode.Four] = "4",
	[Enum.KeyCode.Five] = "5",
}

type Slot = {
	button: TextButton,
	nameLabel: TextLabel,
	timerLabel: TextLabel,
	cooldownFill: Frame,
	stroke: UIStroke,
}

local slots: { [string]: Slot } = {}

local AbilityBarUI = {}

local function buildSlot(abilityId: string, order: number, parent: Instance): Slot
	local def = AbilityConfig.ABILITIES[abilityId]

	local button = UIKit.button({
		Name = abilityId,
		Text = "",
		LayoutOrder = order,
		BackgroundColor3 = Theme.PanelLight,
		Size = UDim2.new(0, BUTTON_SIZE, 0, BUTTON_SIZE),
		ClipsDescendants = true,
		Parent = parent,
	})
	local stroke = UIKit.create("UIStroke", {
		Color = Theme.Gold,
		Thickness = 3,
		Enabled = false,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = button,
	}) :: UIStroke

	-- Dark overlay that shrinks as the cooldown finishes.
	local cooldownFill = UIKit.create("Frame", {
		Name = "Cooldown",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 0),
		ZIndex = 2,
		Parent = button,
	}) :: Frame

	local nameLabel = UIKit.label({
		Text = def.displayName,
		Font = Theme.FontBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 6),
		Size = UDim2.new(1, 0, 0, 16),
		ZIndex = 3,
		Parent = button,
	})
	UIKit.label({
		Text = KEY_LABELS[def.key] or "",
		TextColor3 = Theme.Muted,
		TextSize = 11,
		Position = UDim2.new(0, 4, 1, -16),
		Size = UDim2.new(0, 14, 0, 14),
		ZIndex = 3,
		Parent = button,
	})
	local timerLabel = UIKit.label({
		Text = "",
		Font = Theme.FontBold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 24),
		Size = UDim2.new(1, 0, 0, 24),
		ZIndex = 3,
		Parent = button,
	})

	button.Activated:Connect(function()
		AbilityController.use(abilityId)
	end)

	return {
		button = button,
		nameLabel = nameLabel,
		timerLabel = timerLabel,
		cooldownFill = cooldownFill,
		stroke = stroke,
	}
end

local function update()
	local snapshot = StateController.get()
	if snapshot == nil then
		return
	end
	local now = workspace:GetServerTimeNow()

	for abilityId, slot in slots do
		local def = AbilityConfig.ABILITIES[abilityId]
		local timers = snapshot.abilities[abilityId]
		local readyAt = if timers ~= nil then timers.readyAt else 0
		local activeUntil = if timers ~= nil then timers.activeUntil else 0

		if snapshot.bestStage < def.unlockStage then
			slot.button.BackgroundColor3 = Theme.Disabled
			slot.nameLabel.TextColor3 = Theme.Muted
			slot.timerLabel.TextSize = 11
			slot.timerLabel.Text = `Stage {def.unlockStage}`
			slot.cooldownFill.Size = UDim2.new(1, 0, 0, 0)
			slot.stroke.Enabled = false
		else
			local remaining = readyAt - now
			local active = now < activeUntil
			slot.nameLabel.TextColor3 = Theme.Text
			slot.stroke.Enabled = active
			slot.timerLabel.TextSize = 18
			if remaining > 0 then
				slot.button.BackgroundColor3 = Theme.PanelLight
				slot.timerLabel.Text = if active then `{math.ceil(activeUntil - now)}s` else `{math.ceil(remaining)}`
				slot.timerLabel.TextColor3 = if active then Theme.Gold else Theme.Text
				local cooldown = Formulas.abilityStats(abilityId, snapshot.abilityUpgrades).cooldown
				slot.cooldownFill.Size = UDim2.new(1, 0, math.clamp(remaining / cooldown, 0, 1), 0)
			else
				slot.button.BackgroundColor3 = Theme.Accent
				slot.timerLabel.Text = "READY"
				slot.timerLabel.TextSize = 13
				slot.timerLabel.TextColor3 = Theme.Text
				slot.cooldownFill.Size = UDim2.new(1, 0, 0, 0)
			end
		end
	end
end

function AbilityBarUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = UIKit.create("ScreenGui", {
		Name = "AbilityBar",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	local count = #AbilityConfig.ORDER
	local length = count * BUTTON_SIZE + (count - 1) * GAP
	local bar = UIKit.create("Frame", {
		Name = "Bar",
		BackgroundTransparency = 1,
		-- Desktop: a row centred just above the shop panel.
		-- Compact (phones): a column on the left edge (the menu column has the right side).
		AnchorPoint = if Layout.compact then Vector2.new(0, 0.5) else Vector2.new(0.5, 1),
		Position = if Layout.compact
			then UDim2.new(0, Layout.ABILITY_EDGE, 0.45, 0)
			else UDim2.new(0.5, 0, 1, -(Layout.SHOP_HEIGHT + Layout.SHOP_BOTTOM_MARGIN + 8)),
		Size = if Layout.compact
			then UDim2.new(0, BUTTON_SIZE, 0, length)
			else UDim2.new(0, length, 0, BUTTON_SIZE),
		Parent = gui,
	}, {
		UIKit.create("UIListLayout", {
			Padding = UDim.new(0, GAP),
			FillDirection = if Layout.compact then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	for order, abilityId in AbilityConfig.ORDER do
		slots[abilityId] = buildSlot(abilityId, order, bar)
		Spotlight.register(`Ability:{abilityId}`, slots[abilityId].button)
	end

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= UPDATE_INTERVAL then
			elapsed = 0
			update()
		end
	end)

	gui.Parent = playerGui
end

return AbilityBarUI
