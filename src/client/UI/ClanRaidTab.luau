--!strict
-- Clan window tab: the weekly raid boss. Progress through the tiers, your attacks left
-- today, the Attack button, the current reward preview, and the top contributors.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local RaidConfig = require(Shared:WaitForChild("Config"):WaitForChild("RaidConfig"))
local UIKit = require(script.Parent.UIKit)
local ClanTypes = require(script.Parent.ClanTypes)
local ClanController = require(Client.Controllers.ClanController)
local StateController = require(Client.Controllers.StateController)

type ClanView = Types.ClanView

local Theme = UIKit.Theme
local fmt = NumberFormat.number

local ClanRaidTab = {}

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

function ClanRaidTab.build(parent: Instance, context: ClanTypes.Context): ClanTypes.Tab
	local frame = UIKit.create("Frame", {
		Name = "Raid",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = parent,
	}) :: Frame

	local left = UIKit.create("Frame", {
		Name = "Boss",
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Size = UDim2.new(0.55, -4, 1, 0),
		Parent = frame,
	}, { UIKit.corner(8), UIKit.padding(10) }) :: Frame

	UIKit.label({
		Text = RaidConfig.BOSS_NAME,
		Font = Theme.FontBold,
		TextSize = 17,
		TextColor3 = RaidConfig.BOSS_COLOR,
		Size = UDim2.new(1, 0, 0, 20),
		Parent = left,
	})
	local weekLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 12,
		Position = UDim2.new(0, 0, 0, 22),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = left,
	})
	local barBack = UIKit.create("Frame", {
		BackgroundColor3 = Theme.HpBack,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = left,
	}, { UIKit.corner(6) }) :: Frame
	local barFill = UIKit.create("Frame", {
		BackgroundColor3 = RaidConfig.BOSS_COLOR,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		Parent = barBack,
	}, { UIKit.corner(6) }) :: Frame
	local barLabel = UIKit.label({
		Text = "",
		Font = Theme.FontBold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.6,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 2,
		Parent = barBack,
	})
	local tierLabel = UIKit.label({
		Text = "",
		TextSize = 13,
		Position = UDim2.new(0, 0, 0, 72),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = left,
	})
	local rewardLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.Gold,
		TextSize = 13,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Position = UDim2.new(0, 0, 0, 92),
		Size = UDim2.new(1, 0, 0, 32),
		Parent = left,
	})
	local meLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 12,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Position = UDim2.new(0, 0, 0, 126),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = left,
	})
	local attackButton = UIKit.button({
		Text = "",
		TextSize = 15,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 44),
		Parent = left,
	})

	local right = UIKit.create("Frame", {
		Name = "Top",
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Position = UDim2.new(0.55, 4, 0, 0),
		Size = UDim2.new(0.45, -4, 1, 0),
		Parent = frame,
	}, { UIKit.corner(8), UIKit.padding(10) }) :: Frame
	UIKit.label({ Text = "Top raiders this week", Font = Theme.FontBold, TextSize = 14, Size = UDim2.new(1, 0, 0, 18), Parent = right })
	local topLabels: { TextLabel } = {}
	for i = 1, RaidConfig.TOP_COUNT do
		table.insert(
			topLabels,
			UIKit.label({
				Text = "",
				TextSize = 12,
				Position = UDim2.new(0, 0, 0, 20 + (i - 1) * 18),
				Size = UDim2.new(1, 0, 0, 16),
				Parent = right,
			})
		)
	end

	local attacking = false
	attackButton.Activated:Connect(function()
		if attacking then
			return
		end
		attacking = true
		task.spawn(function()
			local result = context.request("RaidAttack")
			attacking = false
			if result.ok then
				context.showStatus("Raid attack started! Close this window and fight!")
			end
		end)
	end)

	local function render(_view: ClanView, givenSnapshot: Types.Snapshot?)
		local snapshot = givenSnapshot or StateController.get()
		local raid = ClanController.getRaid()
		local units = if raid ~= nil then raid.units else 0
		local tier = Formulas.raidTier(units)
		local tiers = RaidConfig.TIERS

		local secondsLeft = ClanController.raidSecondsLeft()
		weekLabel.Text = `Raid ends in {duration(secondsLeft)}`
			.. (if raid ~= nil and raid.studioTestMode then "  (Studio test mode: short raid weeks)" else "")

		local floor = if tier > 0 then tiers[tier] else 0
		local nextGoal = tiers[tier + 1]
		if nextGoal ~= nil then
			barFill.Size = UDim2.new(math.clamp((units - floor) / (nextGoal - floor), 0, 1), 0, 1, 0)
			barLabel.Text = `{fmt(units)} / {fmt(nextGoal)} to tier {tier + 1}`
		else
			barFill.Size = UDim2.new(1, 0, 1, 0)
			barLabel.Text = `{fmt(units)} units. Every tier cleared!`
		end
		tierLabel.Text = `Tier {tier} of {#tiers} reached`
		local honor, packs = Formulas.raidRewards(tier)
		rewardLabel.Text = if tier > 0
			then `Rewards so far: +{honor} Honor, +{packs} free gear pack{if packs == 1 then "" else "s"} for everyone who attacked.`
			else "Reach tier 1 to earn rewards. Every attack counts."

		local attacksLeft = if snapshot ~= nil then snapshot.raidAttacksLeft else 0
		local mine = if snapshot ~= nil then snapshot.raidUnitsWeek else 0
		meLabel.Text = `Your units this week: {fmt(mine)}. `
			.. `Each attack: {RaidConfig.ATTACK_SECONDS}s, up to {RaidConfig.UNITS_CAP_PER_ATTACK} units. Clicks and abilities count.`
		local raiding = snapshot ~= nil and snapshot.encounter == "Raid"
		local inBoss = snapshot ~= nil and snapshot.encounter == "Boss"
		local canAttack = attacksLeft > 0 and not raiding and not inBoss
		attackButton.Text = if raiding
			then "Raid in progress!"
			elseif inBoss then "Finish your boss fight first"
			elseif attacksLeft > 0 then `ATTACK  ({attacksLeft} left today)`
			else "No attacks left today"
		attackButton.BackgroundColor3 = if canAttack then RaidConfig.BOSS_COLOR else Theme.Disabled
		attackButton.AutoButtonColor = canAttack

		local top = if raid ~= nil then raid.top else {}
		for i, label in topLabels do
			local entry = top[i]
			label.Text = if entry ~= nil then `{i}. {entry.name}  {fmt(entry.units)} ({entry.attacks} atk)` else ""
		end
		if #top == 0 then
			topLabels[1].Text = "Nobody has attacked yet."
		end
	end

	ClanController.RaidChanged:Connect(function()
		local view = ClanController.get()
		if frame.Visible and view ~= nil then
			render(view, nil)
		end
	end)

	return { title = "Raid", frame = frame, render = render }
end

return ClanRaidTab
