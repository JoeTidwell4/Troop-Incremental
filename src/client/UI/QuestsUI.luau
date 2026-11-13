--!strict
-- The QUESTS window (left column button, red dot when something is ready to claim):
--   Daily        7-day login calendar with a Claim button. Opens by itself once per
--                session when today's reward is waiting.
--   Quests       today's quests with progress bars, Claim, one free Reroll, and the
--                "finish all" bonus.
--   Achievements permanent goals that pay Honor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local GearInfo = require(Shared:WaitForChild("GearInfo"))
local Config = Shared:WaitForChild("Config")
local DailyConfig = require(Config:WaitForChild("DailyConfig"))
local AchievementConfig = require(Config:WaitForChild("AchievementConfig"))
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)
local ProgressController = require(Client.Controllers.ProgressController)

type ProgressView = Types.ProgressView
type RewardDef = Types.RewardDef
type QuestRow = { text: TextLabel, fill: Frame, progress: TextLabel, reward: TextLabel, claim: TextButton, reroll: TextButton }
type AchievementRow = { frame: Frame, progress: TextLabel, claim: TextButton }

local Theme = UIKit.Theme
local fmt = NumberFormat.number

local FAIL_MESSAGES: { [string]: string } = {
	AlreadyClaimed = "Already claimed.",
	NotDone = "Not finished yet.",
	NoRerolls = "No rerolls left today.",
	NoOtherQuests = "No other quests available.",
	Rejected = "Slow down a little!",
}

local QUEST_TEXT: { [string]: string } = {}
local QUEST_MINUTES: { [string]: { number } } = {}
for _, def in DailyConfig.QUESTS do
	QUEST_TEXT[def.key] = def.text
	QUEST_MINUTES[def.key] = def.minutes
end

local QuestsUI = {}

local function duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	if hours > 0 then
		return `{hours}h {minutes}m`
	end
	return `{minutes}m {seconds % 60}s`
end

local function rewardText(reward: RewardDef): string
	local parts: { string } = {}
	if reward.goldMinutes ~= nil then
		table.insert(parts, if reward.goldMinutes >= 60 then `{reward.goldMinutes // 60}h of gold` else `{reward.goldMinutes} min of gold`)
	end
	if reward.packs ~= nil then
		table.insert(parts, `{reward.packs} pack{if reward.packs == 1 then "" else "s"}`)
	end
	if reward.heroChests ~= nil then
		table.insert(parts, "Hero Chest")
	end
	if reward.honor ~= nil then
		table.insert(parts, `{reward.honor} Honor`)
	end
	return table.concat(parts, " + ")
end

function QuestsUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = UIKit.create("ScreenGui", {
		Name = "Quests",
		ResetOnSpawn = false,
		DisplayOrder = 18,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	local questsButton = UIKit.button({
		Name = "QuestsButton",
		Text = "QUESTS",
		TextSize = 15,
		BackgroundColor3 = Color3.fromRGB(150, 90, 220),
		Position = UDim2.new(0, Layout.LEFT, 0, Layout.ROW3_TOP),
		Size = UDim2.new(0, Layout.COLUMN_WIDTH, 0, Layout.ROW_HEIGHT),
		Parent = gui,
	})
	local dot = UIKit.create("Frame", {
		Name = "Dot",
		BackgroundColor3 = Color3.fromRGB(235, 60, 60),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(14, 14),
		Visible = false,
		Parent = questsButton,
	}, { UIKit.corner(7), UIKit.create("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }) }) :: Frame

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
		Size = UDim2.new(0.94, 0, 0.86, 0),
		Parent = overlay,
	}, {
		UIKit.corner(14),
		UIKit.padding(14),
		UIKit.create("UISizeConstraint", { MaxSize = Vector2.new(620, 420) }),
	}) :: Frame
	UIKit.label({ Text = "Quests", Font = Theme.FontBold, TextSize = 22, Size = UDim2.new(0, 120, 0, 26), Parent = window })
	local statusLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.HpFill,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0, 0, 0, 30),
		Size = UDim2.new(1, -40, 0, 16),
		Parent = window,
	})
	local closeButton = UIKit.button({
		Text = "X",
		TextSize = 16,
		BackgroundColor3 = Theme.PanelLight,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 32, 0, 32),
		Parent = window,
	})
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
	local function request(action: string, arg: any?)
		task.spawn(function()
			local result = ProgressController.request(action, arg)
			if not result.ok then
				showStatus(FAIL_MESSAGES[result.reason or ""] or "Try again in a moment.")
			end
		end)
	end

	local body = UIKit.create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		Parent = window,
	}) :: Frame
	local function page(name: string): Frame
		return UIKit.create("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			Visible = false,
			Parent = body,
		}) :: Frame
	end

	---------------------------------------------------------------- Daily
	local dailyPage = page("Daily")
	local dayCells: { { frame: Frame, title: TextLabel, reward: TextLabel } } = {}
	for i, reward in DailyConfig.LOGIN_REWARDS do
		local cell = UIKit.create("Frame", {
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Position = UDim2.new((i - 1) / 7, 2, 0, 0),
			Size = UDim2.new(1 / 7, -4, 0, 120),
			Parent = dailyPage,
		}, { UIKit.corner(8), UIKit.padding(4), UIKit.create("UIStroke", { Thickness = 2, Transparency = 1 }) }) :: Frame
		local title = UIKit.label({
			Text = `Day {i}`,
			Font = Theme.FontBold,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 20),
			Parent = cell,
		})
		local rewardLabel = UIKit.label({
			Text = rewardText(reward),
			TextSize = 12,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = if reward.heroChests ~= nil then GearInfo.rarity(4).color else Theme.Gold,
			Position = UDim2.new(0, 0, 0, 26),
			Size = UDim2.new(1, 0, 1, -26),
			Parent = cell,
		})
		table.insert(dayCells, { frame = cell, title = title, reward = rewardLabel })
	end
	local loginInfo = UIKit.label({
		Text = "",
		TextSize = 14,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 132),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = dailyPage,
	})
	local claimLoginButton = UIKit.button({
		Text = "CLAIM",
		TextSize = 20,
		BackgroundColor3 = Theme.Good,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 180),
		Size = UDim2.new(0, 220, 0, 48),
		Parent = dailyPage,
	})
	claimLoginButton.Activated:Connect(function()
		request("ClaimLogin")
	end)

	---------------------------------------------------------------- Quests
	local questsPage = page("QuestList")
	local questRows: { QuestRow } = {}
	for i = 1, DailyConfig.QUESTS_PER_DAY do
		local row = UIKit.create("Frame", {
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 0, (i - 1) * 66),
			Size = UDim2.new(1, 0, 0, 60),
			Parent = questsPage,
		}, { UIKit.corner(8) }) :: Frame
		local text = UIKit.label({ Text = "", Font = Theme.FontBold, TextSize = 15, Position = UDim2.new(0, 10, 0, 6), Size = UDim2.new(1, -200, 0, 18), Parent = row })
		local barBack = UIKit.create("Frame", {
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 10, 0, 30),
			Size = UDim2.new(1, -200, 0, 14),
			Parent = row,
		}, { UIKit.corner(6) }) :: Frame
		local fill = UIKit.create("Frame", { BackgroundColor3 = Theme.Good, BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0), Parent = barBack }, { UIKit.corner(6) }) :: Frame
		local progress = UIKit.label({ Text = "", TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 1, 0), ZIndex = 2, Parent = barBack })
		local reward = UIKit.label({ Text = "", TextColor3 = Theme.Gold, TextSize = 12, Position = UDim2.new(0, 10, 0, 45), Size = UDim2.new(1, -200, 0, 14), Parent = row })
		local claim = UIKit.button({ Text = "Claim", TextSize = 14, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 90, 0, 40), Parent = row })
		local reroll = UIKit.button({
			Text = "Reroll",
			TextSize = 12,
			BackgroundColor3 = Theme.PanelLight,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -104, 0.5, 0),
			Size = UDim2.new(0, 76, 0, 32),
			Parent = row,
		})
		claim.Activated:Connect(function()
			request("ClaimQuest", i)
		end)
		reroll.Activated:Connect(function()
			request("RerollQuest", i)
		end)
		table.insert(questRows, { text = text, fill = fill, progress = progress, reward = reward, claim = claim, reroll = reroll })
	end
	local bonusLabel = UIKit.label({
		Text = `Finish all {DailyConfig.QUESTS_PER_DAY} quests: {rewardText(DailyConfig.ALL_QUESTS_BONUS)}`,
		TextColor3 = Theme.Gold,
		TextSize = 14,
		Position = UDim2.new(0, 0, 0, DailyConfig.QUESTS_PER_DAY * 66 + 6),
		Size = UDim2.new(1, -110, 0, 36),
		Parent = questsPage,
	})
	local bonusButton = UIKit.button({
		Text = "Claim",
		TextSize = 14,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, DailyConfig.QUESTS_PER_DAY * 66 + 6),
		Size = UDim2.new(0, 90, 0, 36),
		Parent = questsPage,
	})
	bonusButton.Activated:Connect(function()
		request("ClaimBonus")
	end)
	local resetLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 12,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = questsPage,
	})

	---------------------------------------------------------------- Achievements
	local achievementsPage = page("Achievements")
	local list = UIKit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = achievementsPage,
	}, { UIKit.create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) }) :: ScrollingFrame
	local achievementRows: { [string]: AchievementRow } = {}
	for _, def in AchievementConfig.LIST do
		local row = UIKit.create("Frame", {
			Name = def.id,
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -8, 0, 46),
			Parent = list,
		}, { UIKit.corner(6) }) :: Frame
		UIKit.label({ Text = def.name, Font = Theme.FontBold, TextSize = 14, Position = UDim2.new(0, 10, 0, 4), Size = UDim2.new(1, -200, 0, 18), Parent = row })
		UIKit.label({ Text = def.description, TextColor3 = Theme.Muted, TextSize = 12, Position = UDim2.new(0, 10, 0, 24), Size = UDim2.new(1, -200, 0, 16), Parent = row })
		local progress = UIKit.label({
			Text = "",
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -104, 0, 4),
			Size = UDim2.new(0, 90, 0, 18),
			Parent = row,
		})
		UIKit.label({
			Text = `+{def.honor} Honor`,
			TextColor3 = Theme.Gold,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -104, 0, 24),
			Size = UDim2.new(0, 90, 0, 16),
			Parent = row,
		})
		local claim = UIKit.button({ Text = "", TextSize = 13, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.new(0, 90, 0, 34), Parent = row })
		claim.Activated:Connect(function()
			request("ClaimAchievement", def.id)
		end)
		achievementRows[def.id] = { frame = row, progress = progress, claim = claim }
	end

	---------------------------------------------------------------- tabs
	local pages: { { title: string, frame: Frame } } = {
		{ title = "Daily", frame = dailyPage },
		{ title = "Quests", frame = questsPage },
		{ title = "Achievements", frame = achievementsPage },
	}
	local activePage = dailyPage
	local tabButtons: { [Frame]: TextButton } = {}

	local function render()
		for frame, button in tabButtons do
			frame.Visible = frame == activePage
			button.BackgroundColor3 = if frame == activePage then Theme.Accent else Theme.PanelLight
		end
		local view = ProgressController.get()
		dot.Visible = ProgressController.hasClaimable()
		if view == nil then
			return
		end

		-- Daily calendar.
		local login = view.login
		local claimedCount = if login.canClaim then login.nextIndex - 1 else login.streak
		for i, cell in dayCells do
			local claimed = i <= claimedCount
			local isNext = i == login.nextIndex and (login.canClaim or claimedCount < #dayCells)
			cell.frame.BackgroundColor3 = if claimed then Color3.fromRGB(45, 90, 60) else Theme.PanelLight
			local stroke = cell.frame:FindFirstChildOfClass("UIStroke") :: UIStroke
			stroke.Transparency = if isNext then 0 else 1
			stroke.Color = if login.canClaim then Theme.Gold else Theme.Muted
			cell.title.Text = if claimed then "Claimed" elseif isNext and login.canClaim then "TODAY" else `Day {i}`
		end
		local nextIn = duration(ProgressController.secondsToNextDay())
		if login.canClaim then
			loginInfo.Text = `Day {login.nextIndex} reward is ready! Come back every day to keep your streak. Missing a day starts over at Day 1.`
		else
			loginInfo.Text = `Claimed for today. Next reward (Day {login.nextIndex}) in {nextIn}.`
		end
		claimLoginButton.Text = if login.canClaim then "CLAIM" else "Claimed"
		claimLoginButton.BackgroundColor3 = if login.canClaim then Theme.Good else Theme.Disabled
		claimLoginButton.AutoButtonColor = login.canClaim

		-- Quests.
		local allClaimed = #view.quests > 0
		for i, row in questRows do
			local quest = view.quests[i]
			local frame = row.text.Parent :: Frame
			frame.Visible = quest ~= nil
			if quest ~= nil then
				local done = quest.progress >= quest.target
				if not quest.claimed then
					allClaimed = false
				end
				row.text.Text = string.gsub(QUEST_TEXT[quest.key] or quest.key, "{n}", fmt(quest.target))
				row.fill.Size = UDim2.new(math.clamp(quest.progress / quest.target, 0, 1), 0, 1, 0)
				row.progress.Text = `{fmt(quest.progress)} / {fmt(quest.target)}`
				local minutes = (QUEST_MINUTES[quest.key] or {})[quest.difficulty] or 0
				row.reward.Text = `Reward: {rewardText({ goldMinutes = minutes })}`
				row.claim.Text = if quest.claimed then "Done" elseif done then "Claim" else "..."
				row.claim.BackgroundColor3 = if done and not quest.claimed then Theme.Good else Theme.Disabled
				row.claim.AutoButtonColor = done and not quest.claimed
				row.reroll.Visible = not quest.claimed and view.rerollsLeft > 0
			end
		end
		local bonusReady = allClaimed and not view.bonusClaimed
		bonusButton.Text = if view.bonusClaimed then "Done" else "Claim"
		bonusButton.BackgroundColor3 = if bonusReady then Theme.Good else Theme.Disabled
		bonusButton.AutoButtonColor = bonusReady
		bonusLabel.TextColor3 = if view.bonusClaimed then Theme.Muted else Theme.Gold
		resetLabel.Text = `New quests in {nextIn}. Rerolls left today: {view.rerollsLeft}.`
			.. (if view.studioTestMode then " (Studio test mode: days are 3 minutes)" else "")

		-- Achievements: claimable first, then in progress, then done.
		for order, def in AchievementConfig.LIST do
			local row = achievementRows[def.id]
			local entry = view.achievements[def.id]
			local status = if entry ~= nil then entry.status else "locked"
			local currentValue = if entry ~= nil then entry.current else 0
			row.frame.LayoutOrder = (if status == "unlocked" then 0 elseif status == "locked" then 1000 else 2000) + order
			row.progress.Text = if status == "claimed" then "Complete" else `{fmt(currentValue)} / {fmt(def.target)}`
			row.claim.Text = if status == "claimed" then "Claimed" elseif status == "unlocked" then "Claim" else "Locked"
			row.claim.BackgroundColor3 = if status == "unlocked" then Theme.Good else Theme.Disabled
			row.claim.AutoButtonColor = status == "unlocked"
			row.frame.BackgroundTransparency = if status == "claimed" then 0.4 else 0
		end
	end

	for index, info in pages do
		local button = UIKit.button({
			Text = info.title,
			TextSize = 14,
			BackgroundColor3 = Theme.PanelLight,
			Position = UDim2.new(0, 130 + (index - 1) * 116, 0, 0),
			Size = UDim2.new(0, 110, 0, 28),
			Parent = window,
		})
		button.Activated:Connect(function()
			activePage = info.frame
			render()
		end)
		tabButtons[info.frame] = button
	end

	questsButton.Activated:Connect(function()
		UIKit.openModal(overlay, window)
		render()
	end)
	closeButton.Activated:Connect(function()
		overlay.Visible = false
	end)

	-- Open the calendar by itself once per session when today's reward is waiting.
	local autoOpened = false
	ProgressController.Changed:Connect(function(view: ProgressView)
		if not autoOpened and view.login.canClaim then
			autoOpened = true
			activePage = dailyPage
			UIKit.openModal(overlay, window)
		end
		render()
	end)

	-- Keep the countdowns moving while open.
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

return QuestsUI
