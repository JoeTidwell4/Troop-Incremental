--!strict
-- "TOP" button (left of WAR) that opens the global Top Commanders window: highest best
-- stage and most lifetime Honor, across every server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Config = Shared:WaitForChild("Config")
local LeaderboardConfig = require(Config:WaitForChild("LeaderboardConfig"))
local AbilityConfig = require(Config:WaitForChild("AbilityConfig"))
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)

type Leaderboards = Types.Leaderboards

local Theme = UIKit.Theme

local LeaderboardUI = {}

function LeaderboardUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = UIKit.create("ScreenGui", {
		Name = "Leaderboards",
		ResetOnSpawn = false,
		DisplayOrder = 14,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	-- Left column, menu row (War | Clan | Top).
	local topPosition, topSize = Layout.menuSlot("Top")
	local topButton = UIKit.button({
		Name = "TopButton",
		Text = "TOP",
		TextSize = 15,
		BackgroundColor3 = Theme.Gold,
		TextColor3 = Theme.Panel,
		Position = topPosition,
		Size = topSize,
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
		Size = Layout.windowSize(0.9, 0.8),
		Parent = overlay,
	}, {
		UIKit.corner(14),
		UIKit.padding(14),
		UIKit.create("UISizeConstraint", { MaxSize = Vector2.new(520, 330) }),
	}) :: Frame
	UIKit.label({
		Text = "Top Commanders",
		Font = Theme.FontBold,
		TextSize = 22,
		TextColor3 = Theme.Gold,
		Size = UDim2.new(1, -40, 0, 26),
		Parent = window,
	})
	UIKit.label({
		Text = "Across every server. Updates every couple of minutes.",
		TextColor3 = Theme.Muted,
		TextSize = 12,
		Position = UDim2.new(0, 0, 0, 26),
		Size = UDim2.new(1, -40, 0, 16),
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

	local function column(titleText: string, index: number): { TextLabel }
		local box = UIKit.create("Frame", {
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Position = UDim2.new((index - 1) * 0.5, if index == 1 then 0 else 4, 0, 50),
			Size = UDim2.new(0.5, -4, 1, -50),
			Parent = window,
		}, { UIKit.corner(8), UIKit.padding(10) }) :: Frame
		UIKit.label({ Text = titleText, Font = Theme.FontBold, TextSize = 15, Size = UDim2.new(1, 0, 0, 18), Parent = box })
		local labels: { TextLabel } = {}
		for i = 1, LeaderboardConfig.TOP_COUNT do
			table.insert(
				labels,
				UIKit.label({
					Text = "",
					TextSize = 13,
					Position = UDim2.new(0, 0, 0, 22 + (i - 1) * 20),
					Size = UDim2.new(1, 0, 0, 18),
					Parent = box,
				})
			)
		end
		return labels
	end
	local stageLabels = column("Best stage", 1)
	local honorLabels = column("Lifetime Honor", 2)

	local function fill(labels: { TextLabel }, entries: { Types.LeaderboardEntry }, prefix: string)
		for i, label in labels do
			local entry = entries[i]
			label.Text = if entry ~= nil then `{i}. {entry.name}   {prefix}{NumberFormat.number(entry.value)}` else ""
			label.TextColor3 = if i == 1 then Theme.Gold else Theme.Text
		end
		if #entries == 0 then
			labels[1].Text = "No scores yet."
		end
	end

	Remotes.waitForEvent(Remotes.Events.LeaderboardSync).OnClientEvent:Connect(function(boards: Leaderboards)
		fill(stageLabels, boards.bestStage, "Stage ")
		fill(honorLabels, boards.honor, "")
	end)

	topButton.Activated:Connect(function()
		UIKit.openModal(overlay, window)
	end)
	closeButton.Activated:Connect(function()
		overlay.Visible = false
	end)

	gui.Parent = playerGui
end

return LeaderboardUI
