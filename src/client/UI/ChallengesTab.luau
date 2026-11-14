--!strict
-- ADVENTURE > Challenges (ChallengeConfig): every challenge as a card (rule, tiers
-- cleared, the permanent bonus so far, the next goal and its prize) with a Start button,
-- and a status panel with Leave while you're in one. The server decides everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local ChallengeConfig = require(Shared:WaitForChild("Config"):WaitForChild("ChallengeConfig"))
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)
local ChallengeController = require(Client.Controllers.ChallengeController)

type Snapshot = Types.Snapshot

local Theme = UIKit.Theme
local MAX_TIER = #ChallengeConfig.TIER_GOALS
local CARD_HEIGHT = if Layout.compact then 96 else 88
local CONFIRM_SECONDS = 3

local FAIL_MESSAGES: { [string]: string } = {
	AlreadyIn = "You're already in a challenge.",
	Locked = "Ascend more times to unlock this one.",
	Complete = "Every tier of this challenge is cleared.",
	InFight = "Finish your boss fight or raid attack first.",
	NotIn = "You're not in a challenge.",
	Rejected = "Slow down a little!",
}

local ChallengesTab = {}

-- "+1.2K Honor, +2 Recruit Scrolls, +120 Relic Dust" for clearing tier `tier`.
local function prizeText(tier: number, bestStage: number): string
	local reward = ChallengeConfig.TIER_REWARDS[tier]
	if reward == nil then
		return ""
	end
	local parts = { `+{NumberFormat.big(Formulas.scaledHonor(bestStage, reward.honorShare, reward.honor))} Honor` }
	if reward.scrolls ~= nil then
		table.insert(parts, `+{reward.scrolls} Recruit Scroll{if reward.scrolls == 1 then "" else "s"}`)
	end
	if reward.relicDust ~= nil then
		table.insert(parts, `+{reward.relicDust} Relic Dust`)
	end
	if reward.heroChests ~= nil then
		table.insert(parts, `+{reward.heroChests} Hero Chest`)
	end
	return table.concat(parts, ", ")
end

function ChallengesTab.build(parent: Instance): { title: string, frame: Frame, render: (snapshot: Snapshot) -> () }
	local frame = UIKit.create("Frame", {
		Name = "Challenges",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = parent,
	}) :: Frame

	-- Status: an explanation, or the challenge you're in + Leave.
	local status = UIKit.create("Frame", {
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 50),
		Parent = frame,
	}, { UIKit.corner(8) }) :: Frame
	local statusStroke = UIKit.create("UIStroke", { Color = Theme.Gold, Thickness = 2, Enabled = false, Parent = status }) :: UIStroke
	local statusTitle = UIKit.label({ Text = "", Font = Theme.FontBold, TextSize = 15, Position = UDim2.new(0, 10, 0, 5), Size = UDim2.new(1, -150, 0, 18), Parent = status })
	local statusText = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 12,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 10, 0, 24),
		Size = UDim2.new(1, -150, 0, 24),
		Parent = status,
	})
	local leaveButton = UIKit.button({
		Text = "Leave",
		TextSize = 13,
		BackgroundColor3 = Theme.HpFill,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0, 124, 0, 34),
		Visible = false,
		Parent = status,
	})
	local message = UIKit.label({
		Text = "",
		TextColor3 = Theme.HpFill,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 4),
		Size = UDim2.new(0, 330, 0, 16),
		ZIndex = 3,
		Parent = status,
	})

	local messageToken = 0
	local function say(reason: string?)
		messageToken += 1
		local token = messageToken
		message.Text = FAIL_MESSAGES[reason or ""] or "That didn't work. Try again."
		task.delay(3, function()
			if messageToken == token then
				message.Text = ""
			end
		end)
	end

	-- Leave needs a second click.
	local leaveArmedUntil = 0
	leaveButton.Activated:Connect(function()
		if os.clock() < leaveArmedUntil then
			leaveArmedUntil = 0
			local result = ChallengeController.request("Leave")
			if not result.ok then
				say(result.reason)
			end
		else
			leaveArmedUntil = os.clock() + CONFIRM_SECONDS
			leaveButton.Text = "Sure? Click again"
			task.delay(CONFIRM_SECONDS, function()
				if os.clock() >= leaveArmedUntil then
					leaveButton.Text = "Leave"
				end
			end)
		end
	end)

	local list = UIKit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 56),
		Size = UDim2.new(1, 0, 1, -56),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = frame,
	}, { UIKit.create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }) }) :: ScrollingFrame

	type Card = { frame: Frame, progress: TextLabel, next: TextLabel, button: TextButton, stroke: UIStroke }
	local cards: { [string]: Card } = {}
	local busy = false
	for index, challengeId in ChallengeConfig.ORDER do
		local def = ChallengeConfig.CHALLENGES[challengeId]
		local card = UIKit.create("Frame", {
			Name = challengeId,
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Size = UDim2.new(1, -8, 0, CARD_HEIGHT),
			Parent = list,
		}, { UIKit.corner(8) }) :: Frame
		local stroke = UIKit.create("UIStroke", { Color = def.color, Thickness = 2, Enabled = false, Parent = card }) :: UIStroke
		UIKit.create("Frame", {
			BackgroundColor3 = def.color,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 0, 8),
			Size = UDim2.new(0, 5, 1, -16),
			Parent = card,
		}, { UIKit.corner(3) })
		UIKit.label({ Text = def.name, Font = Theme.FontBold, TextSize = 16, TextColor3 = def.color, Position = UDim2.new(0, 14, 0, 4), Size = UDim2.new(1, -150, 0, 20), Parent = card })
		UIKit.label({
			Text = def.rule,
			TextSize = 12,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.new(0, 14, 0, 25),
			Size = UDim2.new(1, -150, 0, CARD_HEIGHT - 63),
			Parent = card,
		})
		local progress = UIKit.label({ Text = "", TextSize = 12, TextColor3 = Theme.Gold, RichText = true, Position = UDim2.new(0, 14, 1, -36), Size = UDim2.new(1, -150, 0, 16), Parent = card })
		local nextLabel = UIKit.label({ Text = "", TextSize = 11, TextColor3 = Theme.Muted, Position = UDim2.new(0, 14, 1, -19), Size = UDim2.new(1, -150, 0, 15), Parent = card })
		local button = UIKit.button({
			Text = "Start",
			TextSize = 13,
			BackgroundColor3 = Theme.Good,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0, 124, 0, if Layout.compact then 44 else 40),
			Parent = card,
		})
		button.Activated:Connect(function()
			if busy then
				return
			end
			busy = true
			local result = ChallengeController.request("Start", challengeId)
			busy = false
			if not result.ok then
				say(result.reason)
			end
		end)
		cards[challengeId] = { frame = card, progress = progress, next = nextLabel, button = button, stroke = stroke }
	end

	local function render(snapshot: Snapshot)
		local active = snapshot.challengeActive
		local activeDef = ChallengeConfig.CHALLENGES[active]
		if activeDef ~= nil then
			local cleared = snapshot.challengeTiers[active] or 0
			local goal = Formulas.challengeGoal(cleared + 1)
			statusTitle.Text = `IN CHALLENGE: {activeDef.name}`
			statusTitle.TextColor3 = activeDef.color
			statusText.Text = if goal ~= nil
				then `Next goal: beat the boss of stage {goal}. Your main run is parked and comes back when you leave.`
				else "Every tier cleared!"
			statusStroke.Color = activeDef.color
		else
			statusTitle.Text = "Fresh run, one nasty rule"
			statusTitle.TextColor3 = Theme.Text
			statusText.Text = if snapshot.ascensions >= ChallengeConfig.UNLOCK_ASCENDS
				then "Your main run is parked while you're in a challenge and comes back exactly as it was. Each tier you clear is a permanent bonus."
				else "Challenges open after your first Ascend (stage 50)."
		end
		statusStroke.Enabled = activeDef ~= nil
		leaveButton.Visible = activeDef ~= nil
		statusTitle.Size = UDim2.new(1, if activeDef ~= nil then -150 else -20, 0, 18)
		statusText.Size = UDim2.new(1, if activeDef ~= nil then -150 else -20, 0, 24)

		for challengeId, card in cards do
			local def = ChallengeConfig.CHALLENGES[challengeId]
			local cleared = snapshot.challengeTiers[challengeId] or 0
			local unlocked = snapshot.ascensions >= def.unlockAscends
			local goal = Formulas.challengeGoal(cleared + 1)
			local bonus = if cleared > 0 then Formulas.challengeRewardText(def, cleared) else "no bonus yet"
			card.progress.Text = `Tier {cleared}/{MAX_TIER}  <font color="#FFFFFF">|  {bonus}</font>  <font color="#A0A5B9">(each tier: {Formulas.challengeRewardText(def, 1)})</font>`
			card.next.Text = if goal ~= nil
				then `Next: beat boss {goal}  ->  {prizeText(cleared + 1, snapshot.bestStage)}`
				else "All tiers cleared. Nicely done."
			card.stroke.Enabled = challengeId == active
			card.frame.BackgroundTransparency = if unlocked then 0 else 0.5

			local button = card.button
			local canStart = false
			if challengeId == active then
				button.Text = "You're in it"
			elseif not unlocked then
				button.Text = `Needs {def.unlockAscends} Ascends`
			elseif goal == nil then
				button.Text = "Complete"
			elseif active ~= "" then
				button.Text = "In another one"
			elseif snapshot.encounter ~= "Normal" then
				button.Text = "Finish the fight"
			else
				button.Text = "Start"
				canStart = true
			end
			button.BackgroundColor3 = if canStart then Theme.Good else Theme.Disabled
			button.AutoButtonColor = canStart
		end
	end

	return { title = "Challenges", frame = frame, render = render }
end

return ChallengesTab
