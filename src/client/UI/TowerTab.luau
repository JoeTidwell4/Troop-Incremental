--!strict
-- ADVENTURE > Tower (TowerConfig): your best floor and its permanent bonus, the next
-- floor (laws, toughness, rewards) with the Climb button, the floors coming up, the
-- Tower Chest odds and the daily Tribute. The server decides everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local TowerConfig = require(Shared:WaitForChild("Config"):WaitForChild("TowerConfig"))
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)
local Spotlight = require(script.Parent.Spotlight)
local AudioController = require(Client.Controllers.AudioController)
local TowerController = require(Client.Controllers.TowerController)

type Snapshot = Types.Snapshot

local Theme = UIKit.Theme
local UPCOMING = 6 -- floors listed after the next one

local FAIL_MESSAGES: { [string]: string } = {
	Locked = `The Tower opens at best stage {TowerConfig.UNLOCK_STAGE}.`,
	InChallenge = "Leave your challenge first.",
	InFight = "Finish your boss fight or raid attack first.",
	NoFloors = "Clear floor 1 first.",
	Claimed = "Already claimed today.",
	Rejected = "Slow down a little!",
}

local TowerTab = {}

-- "Warded: Your clicks do nothing" for each law of a floor.
function TowerTab.lawLines(info: Types.TowerFloor): { string }
	local lines: { string } = {}
	for _, lawId in info.laws do
		local law = TowerConfig.LAWS[lawId]
		table.insert(lines, `{law.name}: {law.text}`)
	end
	return lines
end

local function lawNames(info: Types.TowerFloor): string
	local names: { string } = {}
	for _, lawId in info.laws do
		table.insert(names, TowerConfig.LAWS[lawId].name)
	end
	return if #names > 0 then table.concat(names, " + ") else "no law"
end

local function chestOdds(): string
	local total = 0
	for _, prize in TowerConfig.CHEST_PRIZES do
		total += prize.weight
	end
	local parts: { string } = {}
	for _, prize in TowerConfig.CHEST_PRIZES do
		table.insert(parts, `{prize.text} {math.floor(prize.weight / total * 1000 + 0.5) / 10}%`)
	end
	return table.concat(parts, "  |  ")
end

function TowerTab.build(parent: Instance): { title: string, frame: Frame, render: (snapshot: Snapshot) -> () }
	local frame = UIKit.create("ScrollingFrame", {
		Name = "Tower",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Visible = false,
		Parent = parent,
	}) :: ScrollingFrame

	local lockedLabel = UIKit.label({
		Text = `The Endless Tower opens at best stage {TowerConfig.UNLOCK_STAGE}.`,
		TextColor3 = Theme.Muted,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 60),
		Size = UDim2.new(1, -8, 0, 20),
		Visible = false,
		Parent = frame,
	})
	local body = UIKit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 392), Parent = frame }) :: Frame

	-- Best floor + permanent bonus.
	local bestLabel = UIKit.label({ Text = "", Font = Theme.FontBold, TextSize = 18, TextColor3 = TowerConfig.COLOR, Size = UDim2.new(0.5, 0, 0, 22), Parent = body })
	local bonusLabel = UIKit.label({
		Text = "",
		TextSize = 12,
		TextColor3 = Theme.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0.4, 0, 0, 0),
		Size = UDim2.new(0.6, 0, 0, 22),
		Parent = body,
	})

	-- The next floor.
	local card = UIKit.create("Frame", {
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 28),
		Size = UDim2.new(1, 0, 0, 118),
		Parent = body,
	}, { UIKit.corner(8), UIKit.create("UIStroke", { Color = TowerConfig.COLOR, Thickness = 2 }) }) :: Frame
	local floorLabel = UIKit.label({ Text = "", Font = Theme.FontBold, TextSize = 18, Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(1, -170, 0, 22), Parent = card })
	local lawsLabel = UIKit.label({
		Text = "",
		TextSize = 13,
		RichText = true,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 12, 0, 30),
		Size = UDim2.new(1, -170, 0, 36),
		Parent = card,
	})
	local toughLabel = UIKit.label({ Text = "", TextSize = 12, TextColor3 = Theme.Muted, Position = UDim2.new(0, 12, 0, 70), Size = UDim2.new(1, -170, 0, 16), Parent = card })
	local rewardLabel = UIKit.label({ Text = "", TextSize = 12, TextColor3 = Theme.Gold, Position = UDim2.new(0, 12, 0, 90), Size = UDim2.new(1, -24, 0, 16), Parent = card })
	local climbButton = UIKit.button({
		Text = "CLIMB",
		TextSize = 18,
		BackgroundColor3 = TowerConfig.COLOR,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 12),
		Size = UDim2.new(0, 140, 0, 52),
		Parent = card,
	})
	Spotlight.register("Tower:Climb", climbButton)

	local message = UIKit.label({
		Text = "",
		TextColor3 = Theme.HpFill,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0, 0, 0, 148),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = body,
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

	-- Floors coming up.
	UIKit.label({ Text = "Coming up", Font = Theme.FontBold, TextSize = 14, Position = UDim2.new(0, 0, 0, 150), Size = UDim2.new(0.5, 0, 0, 18), Parent = body })
	local upcoming: { TextLabel } = {}
	for i = 1, UPCOMING do
		upcoming[i] = UIKit.label({
			Text = "",
			TextSize = 12,
			RichText = true,
			Position = UDim2.new(if i % 2 == 1 then 0 else 0.5, 0, 0, 170 + ((i - 1) // 2) * 18),
			Size = UDim2.new(0.5, -6, 0, 16),
			Parent = body,
		})
	end

	-- Tower Chest odds.
	UIKit.label({
		Text = `Tower Chest on every {TowerConfig.CHEST_EVERY}th floor. One prize:`,
		Font = Theme.FontBold,
		TextSize = 13,
		Position = UDim2.new(0, 0, 0, 232),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = body,
	})
	UIKit.label({
		Text = chestOdds(),
		TextSize = 11,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 0, 0, 250),
		Size = UDim2.new(1, 0, 0, 44),
		Parent = body,
	})

	-- Daily Tribute.
	local tributeBox = UIKit.create("Frame", {
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 300),
		Size = UDim2.new(1, 0, 0, 56),
		Parent = body,
	}, { UIKit.corner(8) }) :: Frame
	UIKit.label({ Text = "Daily Tribute", Font = Theme.FontBold, TextSize = 15, Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(1, -170, 0, 20), Parent = tributeBox })
	local tributeLabel = UIKit.label({ Text = "", TextSize = 12, TextColor3 = Theme.Muted, Position = UDim2.new(0, 12, 0, 28), Size = UDim2.new(1, -170, 0, 18), Parent = tributeBox })
	local tributeButton = UIKit.button({
		Text = "Claim",
		TextSize = 14,
		BackgroundColor3 = Theme.Good,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 140, 0, if Layout.compact then 42 else 36),
		Parent = tributeBox,
	})
	UIKit.label({
		Text = "Losing a floor costs nothing. Floors don't get easier or harder: come back when your army is stronger.",
		TextSize = 11,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 0, 0, 362),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = body,
	})

	local busy = false
	local function send(action: string)
		if busy then
			return
		end
		busy = true
		local result = TowerController.request(action)
		busy = false
		if not result.ok then
			say(result.reason)
		elseif action == "Tribute" then
			AudioController.play("Reward")
		end
	end
	climbButton.Activated:Connect(function()
		send("Climb")
	end)
	tributeButton.Activated:Connect(function()
		send("Tribute")
	end)

	local function describe(floor: number): string
		local info = Formulas.towerFloor(floor)
		local tags = ""
		if info.guardian then
			tags ..= ` <font color="#{TowerConfig.GUARDIAN_COLOR:ToHex()}">GUARDIAN</font>`
		end
		if info.chest then
			tags ..= ` <font color="#FFCD46">+Chest</font>`
		end
		return `<b>{floor}</b>:{tags} {lawNames(info)}`
	end

	local function render(snapshot: Snapshot)
		local unlocked = snapshot.bestStage >= TowerConfig.UNLOCK_STAGE
		lockedLabel.Visible = not unlocked
		body.Visible = unlocked
		if not unlocked then
			return
		end
		local best = snapshot.towerBest
		local nextFloor = best + 1
		local info = Formulas.towerFloor(nextFloor)

		bestLabel.Text = `Best floor: {best}`
		local bonusPercent = math.floor((Formulas.towerBonus(best) - 1) * 100 + 0.5)
		local nextBonusAt = (best // TowerConfig.BONUS_EVERY + 1) * TowerConfig.BONUS_EVERY
		bonusLabel.Text = `+{bonusPercent}% damage and gold forever (next +{math.floor(TowerConfig.BONUS_PER_STEP * 100 + 0.5)}% at floor {nextBonusAt})`

		local title = `FLOOR {nextFloor}`
		if info.guardian then
			title ..= "  -  GUARDIAN"
		end
		floorLabel.Text = title
		floorLabel.TextColor3 = if info.guardian then TowerConfig.GUARDIAN_COLOR else Theme.Text
		local lines = TowerTab.lawLines(info)
		if info.guardian then
			table.insert(lines, 1, "Guardian: enrages, shields and summons")
		end
		lawsLabel.Text = if #lines > 0 then table.concat(lines, "\n") else "No law on this floor."
		toughLabel.Text = `About as tough as the stage {info.stage} boss ({NumberFormat.big(Formulas.towerHp(nextFloor))} HP). Your best stage: {snapshot.bestStage}`
		local honor = Formulas.scaledHonor(snapshot.bestStage, TowerConfig.FLOOR_HONOR_SHARE, TowerConfig.FLOOR_HONOR_MIN)
		local rewardText = `First clear: +{Formulas.towerFloorDust(nextFloor)} Relic Dust, +{NumberFormat.big(honor)} Honor`
		if info.chest then
			rewardText ..= ", a Tower Chest"
		end
		if nextFloor % TowerConfig.BONUS_EVERY == 0 then
			rewardText ..= `, +{math.floor(TowerConfig.BONUS_PER_STEP * 100 + 0.5)}% damage and gold forever`
		end
		rewardLabel.Text = rewardText

		local canClimb = snapshot.encounter == "Normal" and snapshot.challengeActive == ""
		climbButton.Text = if snapshot.towerFloor > 0
			then "Climbing..."
			elseif snapshot.challengeActive ~= "" then "In a challenge"
			elseif snapshot.encounter ~= "Normal" then "In a fight"
			else "CLIMB"
		climbButton.BackgroundColor3 = if canClimb then TowerConfig.COLOR else Theme.Disabled
		climbButton.AutoButtonColor = canClimb

		for i, label in upcoming do
			label.Text = describe(nextFloor + i)
		end

		local minutes, dust = Formulas.towerTribute(best)
		if best < 1 then
			tributeLabel.Text = "Clear floor 1 to start earning a daily Tribute."
			tributeButton.Text = "Locked"
		elseif snapshot.towerTributeReady then
			tributeLabel.Text = `{minutes} minutes of gold + {dust} Relic Dust. Grows with your best floor.`
			tributeButton.Text = "Claim"
		else
			tributeLabel.Text = `Claimed. Tomorrow: {minutes} minutes of gold + {dust} Relic Dust.`
			tributeButton.Text = "Come back tomorrow"
		end
		local canClaim = best >= 1 and snapshot.towerTributeReady
		tributeButton.BackgroundColor3 = if canClaim then Theme.Good else Theme.Disabled
		tributeButton.AutoButtonColor = canClaim
	end

	return { title = "Tower", frame = frame :: any, render = render }
end

return TowerTab
