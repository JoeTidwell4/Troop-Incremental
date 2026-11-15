--!strict
-- ADVENTURE > Story (StoryConfig): "The Hollow King". A card for the final battle (FIGHT /
-- retry, his weakening, the rewards), then one row per chapter: title, cleared or not, and
-- WATCH buttons for the scenes you've seen. Replays never pause anything or save.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Config = Shared:WaitForChild("Config")
local StoryConfig = require(Config:WaitForChild("StoryConfig"))
local AreaConfig = require(Config:WaitForChild("AreaConfig"))
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)
local NoticeUI = require(script.Parent.NoticeUI)
local StoryController = require(Client.Controllers.StoryController)

type Snapshot = Types.Snapshot

local Theme = UIKit.Theme
local ROW_HEIGHT = if Layout.compact then 52 else 46
local KINDS = { { id = "Arrive", label = "Arrival" }, { id = "Boss", label = "Boss" }, { id = "Outro", label = "Victory" } }

local FAIL: { [string]: string } = {
	Locked = "Clear chapter 10 (the stage 100 boss) first.",
	InChallenge = "Leave your challenge run first.",
	Busy = "Finish the current boss / raid / Tower floor first.",
}

local StoryTab = {}

function StoryTab.build(parent: Instance): { title: string, frame: Frame, render: (snapshot: Snapshot) -> () }
	local frame = UIKit.create("ScrollingFrame", {
		Name = "Story",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Visible = false,
		Parent = parent,
	}) :: ScrollingFrame
	UIKit.create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })

	local header = UIKit.label({
		Text = "",
		Font = Theme.FontBold,
		TextSize = 16,
		TextColor3 = Theme.Gold,
		Size = UDim2.new(1, -8, 0, 22),
		LayoutOrder = 1,
		Parent = frame,
	})

	-- The final battle.
	local card = UIKit.create("Frame", {
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -8, 0, 96),
		LayoutOrder = 2,
		Parent = frame,
	}, { UIKit.corner(8), UIKit.create("UIStroke", { Color = StoryConfig.HOLLOW_COLOR, Thickness = 2 }) }) :: Frame
	UIKit.label({ Text = "FINAL BATTLE: THE HOLLOW KING", Font = Theme.FontBold, TextSize = 16, TextColor3 = StoryConfig.HOLLOW_COLOR, Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(1, -150, 0, 20), Parent = card })
	local finalInfo = UIKit.label({
		Text = "",
		TextSize = 12,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 12, 0, 28),
		Size = UDim2.new(1, -150, 0, 62),
		Parent = card,
	})
	local fightButton = UIKit.button({
		Text = "FIGHT",
		TextSize = 16,
		BackgroundColor3 = StoryConfig.HOLLOW_COLOR,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0, 120, 0, 40),
		Parent = card,
	})
	local reward = StoryConfig.FINAL.REWARD
	local rewardText = `First win: +{math.floor(StoryConfig.FINAL.BONUS * 100 + 0.5)}% damage forever, {reward.scrolls} scrolls, {reward.heroChests} Hero Chests, Honor, Dust, the Hollow Crown + Banner of Valdren.`
	fightButton.Activated:Connect(function()
		local result = StoryController.fightFinal()
		if not result.ok then
			NoticeUI.show("NOT YET", FAIL[result.reason or ""] or "Try again in a moment.", Theme.HpFill)
		end
	end)

	-- One row per chapter.
	type Row = { frame: Frame, title: TextLabel, status: TextLabel, buttons: { [string]: TextButton } }
	local rows: { Row } = {}
	for _, chapter in StoryConfig.CHAPTERS do
		local theme = AreaConfig.THEMES[chapter.number]
		local row = UIKit.create("Frame", {
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -8, 0, ROW_HEIGHT),
			LayoutOrder = 10 + chapter.number,
			Parent = frame,
		}, { UIKit.corner(8) }) :: Frame
		local title = UIKit.label({
			Text = `{chapter.number}. {chapter.title}`,
			Font = Theme.FontBold,
			TextSize = 14,
			Position = UDim2.new(0, 10, 0, 4),
			Size = UDim2.new(0.5, -10, 0, 20),
			Parent = row,
		})
		local status = UIKit.label({
			Text = if theme ~= nil then theme.name else "",
			TextSize = 11,
			TextColor3 = Theme.Muted,
			Position = UDim2.new(0, 10, 0, 24),
			Size = UDim2.new(0.5, -10, 0, 16),
			Parent = row,
		})
		local buttons: { [string]: TextButton } = {}
		for index, kind in KINDS do
			local id = `{kind.id}_{chapter.number}`
			local button = UIKit.button({
				Text = kind.label,
				TextSize = 12,
				BackgroundColor3 = Theme.Accent,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8 - (3 - index) * 84, 0.5, 0),
				Size = UDim2.new(0, 78, 0, 30),
				Parent = row,
			})
			button.Activated:Connect(function()
				StoryController.replay(id)
			end)
			buttons[kind.id] = button
		end
		table.insert(rows, { frame = row, title = title, status = status, buttons = buttons })
	end

	-- Ending replays.
	local extra = UIKit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 34), LayoutOrder = 100, Parent = frame }) :: Frame
	local introButton = UIKit.button({ Text = "Watch: Final Battle intro", TextSize = 12, BackgroundColor3 = StoryConfig.HOLLOW_COLOR, Size = UDim2.new(0.5, -4, 1, 0), Parent = extra })
	local endingButton = UIKit.button({ Text = "Watch: The Ending", TextSize = 12, BackgroundColor3 = Theme.Gold, Position = UDim2.new(0.5, 4, 0, 0), Size = UDim2.new(0.5, -4, 1, 0), Parent = extra })
	introButton.Activated:Connect(function()
		StoryController.replay("Final_Intro")
	end)
	endingButton.Activated:Connect(function()
		StoryController.replay("Ending")
	end)

	local function render(snapshot: Snapshot)
		local seen = snapshot.storySeen or {}
		local cleared = snapshot.storyCleared or {}
		local count = 0
		for _ in cleared do
			count += 1
		end
		local bonus = count * StoryConfig.BONUS_PER_CHAPTER + (if snapshot.storyFinalWon then StoryConfig.FINAL.BONUS else 0)
		header.Text = `THE HOLLOW KING: {count} / {#StoryConfig.CHAPTERS} chapters  |  story bonus +{math.floor(bonus * 100 + 0.5)}% damage`

		local unlocked = cleared["10"] == true
		if snapshot.storyFinalWon then
			finalInfo.Text = "You defeated the Hollow King. Valdren is free! You can fight him again any time (no more rewards)."
			fightButton.Text = "FIGHT AGAIN"
		elseif unlocked then
			local weaken = snapshot.storyFinalWeaken or 0
			finalInfo.Text = `His true form waits atop the Sky Citadel. Every boss move, a long timer.{if weaken > 0 then ` Weakened -{math.floor(weaken * 100 + 0.5)}% from your earlier tries.` else ""}\n{rewardText}`
			fightButton.Text = "FIGHT"
		else
			finalInfo.Text = `Clear all ten chapters (beat the stage 100 boss) to face him.\n{rewardText}`
			fightButton.Text = "LOCKED"
		end
		fightButton.Visible = true
		fightButton.Active = unlocked
		fightButton.AutoButtonColor = unlocked

		for index, row in rows do
			local done = cleared[tostring(index)] == true
			row.title.TextColor3 = if done then Theme.Gold else Theme.Text
			local theme = AreaConfig.THEMES[index]
			row.status.Text = `{if theme ~= nil then theme.name else ""}  |  {if done then "Cleared" else `Boss at stage {index * 10}`}`
			for _, kind in KINDS do
				row.buttons[kind.id].Visible = seen[`{kind.id}_{index}`] == true
			end
		end
		introButton.Visible = seen.Final_Intro == true
		endingButton.Visible = seen.Ending == true
	end

	return { title = "Story", frame = frame, render = render }
end

return StoryTab
