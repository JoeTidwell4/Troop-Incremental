--!strict
-- The LEGACY window (opened from the Honor tab): the second prestige (LegacyConfig).
-- Left: your Legacy rank, Crowns, what a Legacy would give now, and the Legacy button,
-- which first shows exactly what resets and what's kept. Right: the Crown shop.
-- Display only; the server (LegacyService) decides everything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local LegacyConfig = require(Shared:WaitForChild("Config"):WaitForChild("LegacyConfig"))
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)
local NoticeUI = require(script.Parent.NoticeUI)
local StateController = require(Client.Controllers.StateController)
local ShopController = require(Client.Controllers.ShopController)

type Snapshot = Types.Snapshot

local Theme = UIKit.Theme
local fmt = NumberFormat.number
local CROWN_COLOR = Color3.fromRGB(255, 200, 60)
local DANGER_COLOR = Color3.fromRGB(200, 60, 60)
local CONFIRM_DELAY = 3 -- seconds before the final button can be pressed

local FAIL_MESSAGES: { [string]: string } = {
	TooEarly = `Reach stage {LegacyConfig.MIN_STAGE} during this Legacy first.`,
	NoCrowns = "Earn more Honor first: a Legacy right now would give no Crowns.",
	InRaid = "Finish your raid attack first.",
	CantAfford = "Not enough Crowns.",
	InChallenge = "Leave your challenge first (ADVENTURE).",
	MaxReached = "Already maxed.",
}

local RESETS = {
	"Gold, troops, gear, stage (like Ascend)",
	"ALL your Honor",
	"Honor upgrades (Drills, War Chest, ...)",
	"Ability upgrades",
}
local KEPT = {
	"Crowns and Crown upgrades (forever)",
	"Wardrobe gear, achievements, login streak",
	"Clan, faction, Clan Tokens, packs",
	"Troop and ability unlocks, passes",
}

local LegacyUI = {}

local openWindow: (() -> ())? = nil

-- The rank name + color for a number of Legacies done (nil before the first).
function LegacyUI.rankFor(count: number): { count: number, name: string, color: Color3 }?
	return Formulas.legacyRank(count)
end

function LegacyUI.open()
	if openWindow ~= nil then
		openWindow()
	end
end

-- Whether the Legacy button should show yet (close enough to matter, or done before).
function LegacyUI.visibleFor(snapshot: Snapshot): boolean
	return snapshot.legacyCount > 0 or snapshot.bestStage >= LegacyConfig.MIN_STAGE - 30
end

function LegacyUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = UIKit.create("ScreenGui", {
		Name = "Legacy",
		ResetOnSpawn = false,
		DisplayOrder = 16,
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
		Size = Layout.windowSize(0.7, 0.8),
		Parent = overlay,
	}, {
		UIKit.corner(14),
		UIKit.padding(14),
		UIKit.create("UISizeConstraint", { MaxSize = Vector2.new(720, 460) }),
	}) :: Frame
	UIKit.label({
		Text = "LEGACY",
		Font = Theme.FontBold,
		TextSize = 24,
		TextColor3 = CROWN_COLOR,
		Size = UDim2.new(1, -50, 0, 28),
		Parent = window,
	})
	local subtitle = UIKit.label({
		Text = "Start over from scratch for Crowns: permanent upgrades that are never reset.",
		TextColor3 = Theme.Muted,
		TextSize = 13,
		Position = UDim2.new(0, 0, 0, 28),
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
	local body = UIKit.create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		Parent = window,
	}) :: Frame

	---------------------------------------------------------------- left: rank + Legacy
	local left = UIKit.create("Frame", {
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Size = UDim2.new(0.42, -4, 1, 0),
		Parent = body,
	}, { UIKit.corner(8), UIKit.padding(10) }) :: Frame
	local rankLabel = UIKit.label({ Text = "", Font = Theme.FontBold, TextSize = 16, Size = UDim2.new(1, 0, 0, 20), Parent = left })
	local crownsLabel = UIKit.label({
		Text = "",
		Font = Theme.FontBold,
		TextSize = 20,
		TextColor3 = CROWN_COLOR,
		Position = UDim2.new(0, 0, 0, 22),
		Size = UDim2.new(1, 0, 0, 24),
		Parent = left,
	})
	local previewLabel = UIKit.label({
		Text = "",
		TextSize = 13,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 0, 0, 52),
		Size = UDim2.new(1, 0, 1, -110),
		Parent = left,
	})
	local legacyButton = UIKit.button({
		Text = "LEGACY",
		TextSize = 18,
		BackgroundColor3 = CROWN_COLOR,
		TextColor3 = Theme.Panel,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 46),
		Parent = left,
	})

	-- Confirm view: covers the left panel with the full reset list.
	local confirm = UIKit.create("Frame", {
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		ZIndex = 5,
		Parent = left,
	}, { UIKit.corner(8) }) :: Frame
	local confirmText = UIKit.label({
		Text = "",
		RichText = true,
		TextSize = 12,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 1, -96),
		ZIndex = 6,
		Parent = confirm,
	})
	local yesButton = UIKit.button({
		Text = "",
		TextSize = 15,
		BackgroundColor3 = DANGER_COLOR,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -48),
		Size = UDim2.new(1, 0, 0, 42),
		ZIndex = 6,
		Parent = confirm,
	})
	local backButton = UIKit.button({
		Text = "Not yet",
		TextSize = 15,
		BackgroundColor3 = Theme.PanelLight,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 42),
		ZIndex = 6,
		Parent = confirm,
	})

	---------------------------------------------------------------- right: Crown shop
	local shop = UIKit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0.42, 4, 0, 0),
		Size = UDim2.new(0.58, -4, 1, 0),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = body,
	}, {
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		UIKit.create("UIPadding", { PaddingRight = UDim.new(0, 8) }),
	}) :: ScrollingFrame
	UIKit.label({
		LayoutOrder = 0,
		Text = "Crown shop (permanent)",
		Font = Theme.FontBold,
		TextSize = 15,
		TextColor3 = CROWN_COLOR,
		Size = UDim2.new(1, 0, 0, 20),
		Parent = shop,
	})
	local statusLabel = UIKit.label({
		LayoutOrder = 1,
		Text = "",
		TextSize = 12,
		TextColor3 = DANGER_COLOR,
		Size = UDim2.new(1, 0, 0, 14),
		Parent = shop,
	})

	type Row = { level: TextLabel, effect: TextLabel, button: TextButton }
	local rows: { [string]: Row } = {}
	local busy = false

	local function showStatus(text: string)
		statusLabel.Text = text
		task.delay(3, function()
			if statusLabel.Text == text then
				statusLabel.Text = ""
			end
		end)
	end

	for order, upgradeId in LegacyConfig.ORDER do
		local def = LegacyConfig.UPGRADES[upgradeId]
		local row = UIKit.create("Frame", {
			LayoutOrder = order + 1,
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 48),
			Parent = shop,
		}, { UIKit.corner(6) }) :: Frame
		UIKit.label({ Text = def.displayName, Font = Theme.FontBold, TextSize = 14, Position = UDim2.new(0, 8, 0, 4), Size = UDim2.new(0.6, -8, 0, 18), Parent = row })
		local level = UIKit.label({
			Text = "",
			TextSize = 12,
			TextColor3 = CROWN_COLOR,
			Position = UDim2.new(0.6, 0, 0, 4),
			Size = UDim2.new(0.4, -104, 0, 18),
			Parent = row,
		})
		local effect = UIKit.label({
			Text = "",
			TextSize = 11,
			TextColor3 = Theme.Muted,
			Position = UDim2.new(0, 8, 0, 24),
			Size = UDim2.new(1, -112, 0, 16),
			Parent = row,
		})
		local button = UIKit.button({
			Text = "",
			TextSize = 12,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			Size = UDim2.new(0, 96, 1, -10),
			Parent = row,
		})
		button.Activated:Connect(function()
			if busy then
				return
			end
			busy = true
			task.spawn(function()
				local result = ShopController.buyCrownUpgrade(upgradeId)
				busy = false
				if not result.ok then
					showStatus(FAIL_MESSAGES[result.reason or ""] or "Try again in a moment.")
				end
			end)
		end)
		rows[upgradeId] = { level = level, effect = effect, button = button }
	end

	---------------------------------------------------------------- render
	local confirmToken = 0

	local function render()
		local snapshot = StateController.get()
		if snapshot == nil or not overlay.Visible then
			return
		end
		local rank = LegacyUI.rankFor(snapshot.legacyCount)
		rankLabel.Text = if rank ~= nil then `{rank.name} (Legacy {snapshot.legacyCount})` else "No Legacy yet"
		rankLabel.TextColor3 = if rank ~= nil then rank.color else Theme.Text
		crownsLabel.Text = `Crowns: {fmt(snapshot.crowns)}`

		local ready = snapshot.legacyCrowns > 0
		if ready then
			previewLabel.Text = `Legacy now for +{fmt(snapshot.legacyCrowns)} Crowns.\n\n`
				.. "More Honor earned before your Legacy = more Crowns. "
				.. `Best stage this Legacy: {snapshot.legacyBest}.`
		elseif snapshot.legacyBest < LegacyConfig.MIN_STAGE then
			previewLabel.Text = `Reach stage {LegacyConfig.MIN_STAGE} during this Legacy to unlock it.\n\n`
				.. `Best stage this Legacy: {snapshot.legacyBest}.`
		else
			previewLabel.Text = "Earn more Honor (Ascend!) before your Legacy: right now it would give no Crowns."
		end
		legacyButton.BackgroundColor3 = if ready then CROWN_COLOR else Theme.Disabled
		legacyButton.TextColor3 = if ready then Theme.Panel else Theme.Muted
		legacyButton.AutoButtonColor = ready

		subtitle.Text = if snapshot.legacyCount > 0
			then `{snapshot.legacyCount} Legacies done. All Crown upgrades are permanent.`
			else "Start over from scratch for Crowns: permanent upgrades that are never reset."

		for _, upgradeId in LegacyConfig.ORDER do
			local def = LegacyConfig.UPGRADES[upgradeId]
			local row = rows[upgradeId]
			local current = snapshot.crownUpgrades[upgradeId] or 0
			row.level.Text = `Lv {current}`
			local now = Formulas.crownMultiplier({ [upgradeId] = current }, def.stat)
			row.effect.Text = `{def.description} (now x{fmt(now)})`
			local cost = Formulas.crownUpgradeCost(upgradeId, current)
			local affordable = snapshot.crowns >= cost
			row.button.Text = `Upgrade\n{fmt(cost)} Crowns`
			row.button.BackgroundColor3 = if affordable then Theme.Good else Theme.Disabled
			row.button.AutoButtonColor = affordable
		end
	end

	local function list(lines: { string }): string
		local out: { string } = {}
		for _, line in lines do
			table.insert(out, `  - {line}`)
		end
		return table.concat(out, "\n")
	end

	legacyButton.Activated:Connect(function()
		local snapshot = StateController.get()
		if snapshot == nil or snapshot.legacyCrowns <= 0 then
			return
		end
		confirmText.Text = `<b>Legacy for +{fmt(snapshot.legacyCrowns)} Crowns?</b>\n\n`
			.. `<font color="#FF7878"><b>Resets:</b></font>\n{list(RESETS)}\n\n`
			.. `<font color="#78DC78"><b>Kept:</b></font>\n{list(KEPT)}`
		confirm.Visible = true
		confirmToken += 1
		local token = confirmToken
		-- A short countdown so it can't be clicked through by accident.
		task.spawn(function()
			for secondsLeft = CONFIRM_DELAY, 1, -1 do
				if confirmToken ~= token then
					return
				end
				yesButton.Text = `Wait {secondsLeft}...`
				yesButton.AutoButtonColor = false
				task.wait(1)
			end
			if confirmToken == token then
				yesButton.Text = "YES, START MY LEGACY"
				yesButton.AutoButtonColor = true
			end
		end)
	end)
	backButton.Activated:Connect(function()
		confirmToken += 1
		confirm.Visible = false
	end)
	yesButton.Activated:Connect(function()
		if busy or not yesButton.AutoButtonColor then
			return
		end
		busy = true
		confirmToken += 1
		task.spawn(function()
			local result = ShopController.legacy()
			busy = false
			confirm.Visible = false
			if result.ok then
				overlay.Visible = false
				NoticeUI.show("LEGACY!", `+{fmt(result.crowns or 0)} Crowns. Spend them in the Crown shop, then conquer again.`, CROWN_COLOR)
			else
				showStatus(FAIL_MESSAGES[result.reason or ""] or "Try again in a moment.")
			end
		end)
	end)

	openWindow = function()
		confirm.Visible = false
		confirmToken += 1
		UIKit.openModal(overlay, window)
		render()
	end
	closeButton.Activated:Connect(function()
		overlay.Visible = false
	end)
	StateController.Changed:Connect(function()
		render()
	end)

	gui.Parent = playerGui
end

return LegacyUI
