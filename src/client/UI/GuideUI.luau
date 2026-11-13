--!strict
-- The GUIDE: every tutorial lesson (TutorialConfig), grouped by topic. Opened from the
-- Settings window. Lessons you've seen, or that your best stage has reached, can be
-- replayed (TutorialUI.play); the rest say when they unlock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local TutorialConfig = require(Shared:WaitForChild("Config"):WaitForChild("TutorialConfig"))
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)
local TutorialUI = require(script.Parent.TutorialUI)
local StateController = require(Client.Controllers.StateController)

type Snapshot = Types.Snapshot

local Theme = UIKit.Theme

local GuideUI = {}

local openGuide: () -> () = function() end

function GuideUI.open()
	openGuide()
end

local function unlocked(snapshot: Snapshot?, lesson: Types.TutorialLesson): boolean
	if snapshot == nil then
		return false
	end
	return snapshot.tutorialSeen[lesson.id] == true or snapshot.bestStage >= lesson.stage
end

function GuideUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = UIKit.create("ScreenGui", {
		Name = "Guide",
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
		Size = Layout.windowSize(0.6, 0.8),
		Parent = overlay,
	}, { UIKit.corner(14), UIKit.padding(14), UIKit.create("UISizeConstraint", { MaxSize = Vector2.new(600, 500) }) }) :: Frame
	UIKit.label({ Text = "Guide", Font = Theme.FontBold, TextSize = 22, TextColor3 = Theme.Gold, Size = UDim2.new(1, -50, 0, 28), Parent = window })
	local subtitle = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 12,
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
	local list = UIKit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 50),
		Size = UDim2.new(1, 0, 1, -50),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = window,
	}, { UIKit.create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) }) :: ScrollingFrame

	type Row = { lesson: Types.TutorialLesson, button: TextButton, status: TextLabel, title: TextLabel }
	local rows: { Row } = {}
	local order = 0
	for _, topic in TutorialConfig.TOPICS do
		order += 1
		UIKit.label({
			Text = topic,
			Font = Theme.FontBold,
			TextSize = 16,
			TextColor3 = Theme.Gold,
			LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, 24),
			TextYAlignment = Enum.TextYAlignment.Bottom,
			Parent = list,
		})
		for _, lesson in TutorialConfig.LESSONS do
			if lesson.topic ~= topic then
				continue
			end
			order += 1
			local frame = UIKit.create("Frame", {
				Name = lesson.id,
				BackgroundColor3 = Theme.PanelLight,
				BorderSizePixel = 0,
				LayoutOrder = order,
				Size = UDim2.new(1, -8, 0, 40),
				Parent = list,
			}, { UIKit.corner(6) }) :: Frame
			local title = UIKit.label({ Text = lesson.title, Font = Theme.FontBold, TextSize = 14, Position = UDim2.new(0, 10, 0, 3), Size = UDim2.new(1, -120, 0, 18), Parent = frame })
			local status = UIKit.label({ Text = "", TextColor3 = Theme.Muted, TextSize = 12, Position = UDim2.new(0, 10, 0, 21), Size = UDim2.new(1, -120, 0, 16), Parent = frame })
			local button = UIKit.button({
				Text = "Replay",
				TextSize = 13,
				BackgroundColor3 = Theme.Accent,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -6, 0.5, 0),
				Size = UDim2.new(0, 90, 0, 30),
				Parent = frame,
			})
			button.Activated:Connect(function()
				if unlocked(StateController.get(), lesson) then
					overlay.Visible = false
					TutorialUI.play(lesson.id)
				end
			end)
			table.insert(rows, { lesson = lesson, button = button, status = status, title = title })
		end
	end

	local function refresh()
		local snapshot = StateController.get()
		local open = 0
		for _, row in rows do
			local isOpen = unlocked(snapshot, row.lesson)
			if isOpen then
				open += 1
			end
			row.button.Visible = isOpen
			row.title.TextColor3 = if isOpen then Theme.Text else Theme.Muted
			local first = row.lesson.steps[1].text
			first = (string.gsub(first, "{tap}", if Layout.compact then "Tap" else "Click"))
			row.status.Text = if isOpen then first else `Unlocks at stage {row.lesson.stage}`
		end
		subtitle.Text = `{open} of {#rows} lessons unlocked. Replay any of them here.`
	end

	openGuide = function()
		refresh()
		list.CanvasPosition = Vector2.zero
		UIKit.openModal(overlay, window)
	end
	closeButton.Activated:Connect(function()
		overlay.Visible = false
	end)

	gui.Parent = playerGui
end

return GuideUI
