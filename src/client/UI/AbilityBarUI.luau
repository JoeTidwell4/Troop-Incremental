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


type Slot = {
	abilityId: string, -- what's equipped in this slot right now
	button: TextButton,
	nameLabel: TextLabel,
	timerLabel: TextLabel,
	cooldownFill: Frame,
	stroke: UIStroke,
}

local slots: { Slot } = {}

local AbilityBarUI = {}

local function buildSlot(order: number, parent: Instance): Slot
	local abilityId = AbilityConfig.DEFAULT_LOADOUT[order]
	local def = AbilityConfig.ABILITIES[abilityId]

	local button = UIKit.button({
		Name = `Slot{order}`,
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
		Text = tostring(order),
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

	local slot: Slot
	button.Activated:Connect(function()
		AbilityController.use(slot.abilityId)
	end)

	slot = {
		abilityId = abilityId,
		button = button,
		nameLabel = nameLabel,
		timerLabel = timerLabel,
		cooldownFill = cooldownFill,
		stroke = stroke,
	}
	return slot
end

local function update()
	local snapshot = StateController.get()
	if snapshot == nil then
		return
	end
	local now = workspace:GetServerTimeNow()

	for index, slot in slots do
		-- Follow the loadout: the slot's ability can change (ARMY > Abilities).
		local equippedId = snapshot.abilityLoadout[index] or slot.abilityId
		if equippedId ~= slot.abilityId then
			slot.abilityId = equippedId
			Spotlight.register(`Ability:{equippedId}`, slot.button)
		end
		local abilityId = slot.abilityId
		local def = AbilityConfig.ABILITIES[abilityId]
		slot.nameLabel.Text = def.displayName
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
			local waitsForBoss = def.bossOnly == true and snapshot.encounter ~= "Boss"
			if abilityId == "Bounty" and snapshot.bountyLeft > 0 then
				-- Bounty runs on kills, not time: show the kills left.
				slot.stroke.Enabled = true
				slot.button.BackgroundColor3 = Theme.PanelLight
				slot.timerLabel.Text = `{snapshot.bountyLeft} kills`
				slot.timerLabel.TextSize = 13
				slot.timerLabel.TextColor3 = Theme.Gold
				local cooldown = Formulas.abilityStats(abilityId, snapshot.abilityUpgrades).cooldown
				slot.cooldownFill.Size = UDim2.new(1, 0, math.clamp(math.max(remaining, 0) / cooldown, 0, 1), 0)
			elseif remaining <= 0 and waitsForBoss then
				slot.button.BackgroundColor3 = Theme.PanelLight
				slot.timerLabel.Text = "Boss only"
				slot.timerLabel.TextSize = 12
				slot.timerLabel.TextColor3 = Theme.Muted
				slot.cooldownFill.Size = UDim2.new(1, 0, 0, 0)
			elseif remaining > 0 then
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

	local count = AbilityConfig.LOADOUT_SLOTS
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

	for order = 1, AbilityConfig.LOADOUT_SLOTS do
		local slot = buildSlot(order, bar)
		slots[order] = slot
		Spotlight.register(`Ability:{slot.abilityId}`, slot.button)
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
