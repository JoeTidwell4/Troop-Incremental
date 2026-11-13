--!strict
-- Factions and the faction war:
--   * A "WAR" button under the ability bar opens the window.
--   * Picker view: the 3 factions with their bonus and a Join button.
--     Opens by itself once after you beat your first boss if you have no faction.
--   * War view: standings, your contribution, last week's result, top 10 of your faction,
--     time left, and a Switch faction button (with cooldown).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Config = Shared:WaitForChild("Config")
local FactionConfig = require(Config:WaitForChild("FactionConfig"))
local TroopConfig = require(Config:WaitForChild("TroopConfig"))
local AbilityConfig = require(Config:WaitForChild("AbilityConfig"))
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)
local StateController = require(Client.Controllers.StateController)
local FactionController = require(Client.Controllers.FactionController)

type Snapshot = Types.Snapshot
type WarState = Types.WarState
type StandingRow = { fill: Frame, text: TextLabel }

local Theme = UIKit.Theme
local fmt = NumberFormat.number

local FAIL_MESSAGES: { [string]: string } = {
	AlreadyInFaction = "You're already in that faction.",
	OnCooldown = "You can't switch faction yet.",
	WarLocked = "Switching is locked near the end of a war.",
	LeaveClanFirst = "Leave your clan before switching faction.",
	Rejected = "Slow down a little!",
}

local FactionUI = {}

-- 273600 -> "3d 4h", 750 -> "12m 30s"
local function duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local days = seconds // 86400
	local hours = (seconds % 86400) // 3600
	local minutes = (seconds % 3600) // 60
	if days > 0 then
		return `{days}d {hours}h`
	elseif hours > 0 then
		return `{hours}h {minutes}m`
	end
	return `{minutes}m {seconds % 60}s`
end

local function bonusText(factionId: string): string
	local def = FactionConfig.FACTIONS[factionId]
	local troop = TroopConfig.TROOPS[def.troopId]
	return `{troop.displayName}s x{FactionConfig.TROOP_BONUS} damage and HP`
end

function FactionUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = UIKit.create("ScreenGui", {
		Name = "FactionWar",
		ResetOnSpawn = false,
		DisplayOrder = 15,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	-- "WAR" button: left column, menu row (War | Clan | Top).
	local warPosition, warSize = Layout.menuSlot("War")
	local warButton = UIKit.button({
		Name = "WarButton",
		Text = "WAR",
		TextSize = 15,
		Position = warPosition,
		Size = warSize,
		BackgroundColor3 = Theme.HpFill,
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
		Size = Layout.windowSize(0.94, 0.86),
		Parent = overlay,
	}, {
		UIKit.corner(14),
		UIKit.padding(14),
		UIKit.create("UISizeConstraint", { MaxSize = Vector2.new(600, 420) }),
	}) :: Frame

	local title = UIKit.label({
		Text = "Faction War",
		Font = Theme.FontBold,
		TextSize = 22,
		Size = UDim2.new(1, -40, 0, 26),
		Parent = window,
	})
	local timeLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 13,
		Position = UDim2.new(0, 0, 0, 26),
		Size = UDim2.new(1, -40, 0, 16),
		Parent = window,
	})
	local closeButton = UIKit.button({
		Name = "Close",
		Text = "X",
		TextSize = 16,
		BackgroundColor3 = Theme.PanelLight,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(Layout.CLOSE_SIZE, Layout.CLOSE_SIZE),
		Parent = window,
	})
	local statusLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.HpFill,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0, 0, 0, 26),
		Size = UDim2.new(1, -40, 0, 16),
		Parent = window,
	})

	local body = UIKit.create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 48),
		Size = UDim2.new(1, 0, 1, -48),
		Parent = window,
	}) :: Frame

	local statusToken = 0
	local function showStatus(text: string)
		statusToken += 1
		local token = statusToken
		statusLabel.Text = text
		task.delay(3, function()
			if statusToken == token then
				statusLabel.Text = ""
			end
		end)
	end

	---------------------------------------------------------------- picker view
	local picker = UIKit.create("Frame", {
		Name = "Picker",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = body,
	}) :: Frame
	local pickerHint = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 13,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.new(1, 0, 0, 32),
		Parent = picker,
	})
	local joinButtons: { [string]: TextButton } = {}
	local count = #FactionConfig.ORDER
	local choosing = false

	local function onJoin(factionId: string)
		if choosing then
			return
		end
		choosing = true
		task.spawn(function()
			local result = FactionController.choose(factionId)
			choosing = false
			if result.ok then
				showStatus(`Welcome to the {FactionConfig.FACTIONS[factionId].displayName}!`)
			else
				showStatus(FAIL_MESSAGES[result.reason or ""] or "Couldn't join, try again.")
			end
		end)
	end

	for index, factionId in FactionConfig.ORDER do
		local def = FactionConfig.FACTIONS[factionId]
		local card = UIKit.create("Frame", {
			Name = factionId,
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Position = UDim2.new((index - 1) / count, if index == 1 then 0 else 4, 0, 38),
			Size = UDim2.new(1 / count, -8, 1, -84),
			Parent = picker,
		}, { UIKit.corner(10), UIKit.padding(10) }) :: Frame
		UIKit.create("UIStroke", { Color = def.color, Thickness = 2, Parent = card })
		UIKit.label({
			Text = def.displayName,
			Font = Theme.FontBold,
			TextSize = 17,
			TextColor3 = def.color,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 40),
			Parent = card,
		})
		UIKit.label({
			Text = `"{def.motto}"`,
			TextColor3 = Theme.Muted,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 0, 0, 44),
			Size = UDim2.new(1, 0, 0, 18),
			Parent = card,
		})
		UIKit.label({
			Text = bonusText(factionId),
			TextSize = 14,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 0, 0, 70),
			Size = UDim2.new(1, 0, 0, 40),
			Parent = card,
		})
		local join = UIKit.button({
			Name = "Join",
			Text = "Join",
			TextSize = 16,
			BackgroundColor3 = def.color,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 40),
			Parent = card,
		})
		join.Activated:Connect(function()
			onJoin(factionId)
		end)
		joinButtons[factionId] = join
	end

	local laterButton = UIKit.button({
		Name = "Later",
		Text = "Decide later",
		TextSize = 14,
		BackgroundColor3 = Theme.PanelLight,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0, 180, 0, 36),
		Parent = picker,
	})

	---------------------------------------------------------------- war view
	local warView = UIKit.create("Frame", {
		Name = "War",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = body,
	}) :: Frame

	local youLabel = UIKit.label({
		Text = "",
		Font = Theme.FontBold,
		TextSize = 15,
		Size = UDim2.new(1, -150, 0, 20),
		Parent = warView,
	})
	local switchButton = UIKit.button({
		Name = "Switch",
		Text = "Switch faction",
		TextSize = 12,
		BackgroundColor3 = Theme.PanelLight,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 140, 0, 30),
		Parent = warView,
	})
	local contributionLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 13,
		Position = UDim2.new(0, 0, 0, 22),
		Size = UDim2.new(1, -150, 0, 16),
		Parent = warView,
	})

	-- Standings: one bar per faction.
	local standingRows: { [string]: StandingRow } = {}
	for index, factionId in FactionConfig.ORDER do
		local def = FactionConfig.FACTIONS[factionId]
		local y = 44 + (index - 1) * 30
		local back = UIKit.create("Frame", {
			Name = factionId,
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 0, y),
			Size = UDim2.new(1, 0, 0, 26),
			Parent = warView,
		}, { UIKit.corner(6) }) :: Frame
		local fill = UIKit.create("Frame", {
			Name = "Fill",
			BackgroundColor3 = def.color,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 0, 1, 0),
			Parent = back,
		}, { UIKit.corner(6) }) :: Frame
		local text = UIKit.label({
			Text = "",
			TextSize = 13,
			Font = Theme.FontBold,
			TextStrokeTransparency = 0.6,
			Position = UDim2.new(0, 8, 0, 0),
			Size = UDim2.new(1, -16, 1, 0),
			ZIndex = 2,
			Parent = back,
		})
		standingRows[factionId] = { fill = fill, text = text }
	end

	local resultLabel = UIKit.label({
		Text = "",
		TextSize = 13,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Position = UDim2.new(0, 0, 0, 136),
		Size = UDim2.new(1, 0, 0, 32),
		Parent = warView,
	})

	local topTitle = UIKit.label({
		Text = "Top contributors",
		Font = Theme.FontBold,
		TextSize = 14,
		Position = UDim2.new(0, 0, 0, 170),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = warView,
	})
	local topLabels: { TextLabel } = {}
	for i = 1, FactionConfig.TOP_COUNT do
		local column = (i - 1) // 5
		local row = (i - 1) % 5
		table.insert(
			topLabels,
			UIKit.label({
				Text = "",
				TextSize = 12,
				Position = UDim2.new(column * 0.5, 0, 0, 190 + row * 17),
				Size = UDim2.new(0.5, -6, 0, 16),
				Parent = warView,
			})
		)
	end
	local footerLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 11,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = warView,
	})

	---------------------------------------------------------------- behaviour
	local view: "Picker" | "War" = "War"
	local promptedThisSession = false

	local function render()
		local snapshot = StateController.get()
		local war = FactionController.getWar()
		local hasFaction = snapshot ~= nil and snapshot.faction ~= ""

		picker.Visible = view == "Picker"
		warView.Visible = view == "War"
		title.Text = if view == "Picker" then "Choose your faction" else "Faction War"

		local secondsLeft = FactionController.warSecondsLeft()
		timeLabel.Text = if war ~= nil then `This war ends in {duration(secondsLeft)}` else "Loading war..."

		if snapshot == nil then
			return
		end

		-- Picker
		if view == "Picker" then
			local switchIn = snapshot.factionSwitchIn
			if not hasFaction then
				pickerHint.Text = `Pick a side. Your faction's troop type gets x{FactionConfig.TROOP_BONUS} `
					.. "damage and HP, and your kills earn war points for it."
			elseif switchIn > 0 then
				pickerHint.Text = `You can switch again in {duration(switchIn)}.`
			else
				pickerHint.Text = `Switching resets your war points for this week. Next switch: `
					.. `{duration(FactionConfig.SWITCH_COOLDOWN)} cooldown.`
			end
			for factionId, button in joinButtons do
				local isCurrent = snapshot.faction == factionId
				local allowed = not isCurrent and switchIn <= 0
				button.Text = if isCurrent then "Your faction" else "Join"
				button.AutoButtonColor = allowed
				button.BackgroundColor3 = if allowed then FactionConfig.FACTIONS[factionId].color else Theme.Disabled
			end
			laterButton.Text = if hasFaction then "Back" else "Decide later"
			return
		end

		-- War view
		if not hasFaction then
			youLabel.Text = "You haven't joined a faction yet."
			youLabel.TextColor3 = Theme.Text
			switchButton.Text = "Choose faction"
			contributionLabel.Text = "Join a faction to earn war points."
		else
			local def = FactionConfig.FACTIONS[snapshot.faction]
			youLabel.Text = `{def.displayName}  ({bonusText(snapshot.faction)})`
			youLabel.TextColor3 = def.color
			switchButton.Text = if snapshot.factionSwitchIn > 0
				then `Switch in {duration(snapshot.factionSwitchIn)}`
				else "Switch faction"
			local activeText = if snapshot.warActive
				then "Active"
				else `{FactionConfig.ACTIVE_THRESHOLD} pts to become active`
			contributionLabel.Text = `Today {fmt(snapshot.warDayPoints)} / {fmt(FactionConfig.DAILY_CAP)}`
				.. `  |  This week {fmt(snapshot.warPoints)}  |  {activeText}`
		end

		if war == nil then
			return
		end

		local bestAverage = 0
		for _, standing in war.standings do
			bestAverage = math.max(bestAverage, standing.average)
		end
		for factionId, row in standingRows do
			local standing = war.standings[factionId] or { points = 0, active = 0, average = 0 }
			local def = FactionConfig.FACTIONS[factionId]
			local leading = bestAverage > 0 and standing.average == bestAverage
			row.fill.Size = UDim2.new(if bestAverage > 0 then standing.average / bestAverage else 0, 0, 1, 0)
			row.text.Text = `{def.displayName}{if leading then "  (LEADING)" else ""}   `
				.. `{fmt(math.floor(standing.average))} avg  |  {standing.active} active  |  {fmt(standing.points)} total`
		end

		local last = war.lastResult
		if snapshot.warBonusActive then
			resultLabel.Text = `You won last week's war! +{math.floor((FactionConfig.WINNER_GOLD_MULTIPLIER - 1) * 100 + 0.5)}% gold until this war ends.`
			resultLabel.TextColor3 = Theme.Gold
		elseif last ~= nil and last.winner ~= "" then
			resultLabel.Text = `Last war: {FactionConfig.FACTIONS[last.winner].displayName} won. `
				.. "Be active in the winning faction to earn the gold bonus."
			resultLabel.TextColor3 = Theme.Text
		else
			resultLabel.Text = "Score = war points per active member. Only kills near your best stage count."
			resultLabel.TextColor3 = Theme.Muted
		end

		local listFaction = if hasFaction then snapshot.faction else FactionConfig.ORDER[1]
		topTitle.Text = `Top contributors: {FactionConfig.FACTIONS[listFaction].displayName}`
		local list = war.top[listFaction] or {}
		for i, label in topLabels do
			local entry = list[i]
			label.Text = if entry ~= nil then `{i}. {entry.name}  {fmt(entry.points)}` else ""
		end
		if #list == 0 then
			topLabels[1].Text = "No contributors yet this week."
		end

		local notes: { string } = {}
		if not war.available then
			table.insert(notes, "Live standings unavailable right now (couldn't reach Roblox servers).")
		end
		if war.studioTestMode then
			table.insert(notes, `Studio test mode: wars last {duration(FactionConfig.WEEK_SECONDS)}.`)
		end
		footerLabel.Text = table.concat(notes, "  ")
	end

	local function open(which: "Picker" | "War")
		view = which
		UIKit.openModal(overlay, window)
		render()
	end

	warButton.Activated:Connect(function()
		open("War")
	end)
	closeButton.Activated:Connect(function()
		overlay.Visible = false
	end)
	laterButton.Activated:Connect(function()
		local snapshot = StateController.get()
		if snapshot ~= nil and snapshot.faction ~= "" then
			open("War")
		else
			overlay.Visible = false
		end
	end)
	switchButton.Activated:Connect(function()
		open("Picker")
	end)

	StateController.Changed:Connect(function(snapshot: Snapshot, previous: Snapshot?)
		-- Joined a faction from the picker: show the war.
		if previous ~= nil and previous.faction == "" and snapshot.faction ~= "" and view == "Picker" then
			view = "War"
		end
		-- Offer the picker once per session after the first boss.
		if not promptedThisSession and snapshot.faction == "" and snapshot.bestStage > FactionConfig.PROMPT_AFTER_STAGE then
			promptedThisSession = true
			open("Picker")
		end
		local def = FactionConfig.FACTIONS[snapshot.faction]
		warButton.BackgroundColor3 = if def ~= nil then def.color else Theme.HpFill
		if overlay.Visible then
			render()
		end
	end)
	FactionController.WarChanged:Connect(function(_war: WarState)
		if overlay.Visible then
			render()
		end
	end)

	-- Keep countdowns moving while the window is open.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= 1 and overlay.Visible then
			elapsed = 0
			render()
		end
	end)

	gui.Parent = playerGui
end

return FactionUI
