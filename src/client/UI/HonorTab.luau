--!strict
-- Shop tab: Honor. Left side: Ascend (preview + button). Right side: the Honor shop's
-- permanent upgrades, then ability upgrades (AbilityConfig.UPGRADES, also Honor).
-- All prices and previews are display only; the server decides.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Config = Shared:WaitForChild("Config")
local HonorConfig = require(Config:WaitForChild("HonorConfig"))
local AbilityConfig = require(Config:WaitForChild("AbilityConfig"))
local AscendConfig = require(Config:WaitForChild("AscendConfig"))
local UIKit = require(script.Parent.UIKit)
local ShopTypes = require(script.Parent.ShopTypes)
local AscendConfirmUI = require(script.Parent.AscendConfirmUI)
local LegacyUI = require(script.Parent.LegacyUI)
local NoticeUI = require(script.Parent.NoticeUI)
local ShopController = require(Client.Controllers.ShopController)

type Snapshot = Types.Snapshot
type HonorUpgradeDef = Types.HonorUpgradeDef

local Theme = UIKit.Theme
local format = NumberFormat.big
local HONOR_COLOR = Color3.fromRGB(255, 205, 70)
local ROW_HEIGHT = 40

type Row = { level: TextLabel, effect: TextLabel, button: TextButton }

local HonorTab = {}

-- What an upgrade currently gives at `level`, e.g. "now x1.95 damage".
local function effectText(def: HonorUpgradeDef, level: number, upgrades: { [string]: number }): string
	local fmt = NumberFormat.number
	if def.damageMultiplier ~= nil then
		return `now x{fmt(def.damageMultiplier ^ level)} damage`
	elseif def.goldMultiplier ~= nil then
		return `now x{fmt(def.goldMultiplier ^ level)} gold`
	elseif def.armyHpMultiplier ~= nil then
		return `now x{fmt(def.armyHpMultiplier ^ level)} army HP`
	elseif def.tapMultiplier ~= nil then
		return `now x{fmt(def.tapMultiplier ^ level)} click damage`
	elseif def.tapPerLevel ~= nil then
		local counted = if def.maxLevel ~= nil then math.min(level, def.maxLevel) else level
		return `now x{fmt(1 + def.tapPerLevel * counted)} click damage`
	elseif def.startGoldMultiplier ~= nil then
		return `start runs with {format(Formulas.startingGold(upgrades))} gold`
	elseif def.offlineHoursPerLevel ~= nil then
		local hours = (def.offlineHoursPerLevel or 0) * level
		local percent = math.floor((def.offlineEfficiencyPerLevel or 0) * level * 100 + 0.5)
		return `now +{hours}h cap, +{percent}% offline gold`
	end
	return ""
end

-- "x2.30 -> x2.45 damage" style text for an ability upgrade at `level`.
local function abilityEffectText(def: Types.AbilityUpgradeDef, level: number): string
	local fmt = NumberFormat.number
	local function value(atLevel: number): number
		local stats = Formulas.abilityStats(def.abilityId, { [def.id] = atLevel }) :: any
		return stats[def.stat] or 0
	end
	local now = value(level)
	local nextValue = if level < def.maxLevel then value(level + 1) else nil
	local function show(v: number): string
		if def.stat == "damageMultiplier" or def.stat == "goldMultiplier" or def.stat == "tapMultiplier" then
			return `x{fmt(v)}`
		elseif def.stat == "healFraction" then
			return `{math.floor(v * 100 + 0.5)}%`
		elseif def.stat == "bountyKills" then
			return `{math.floor(v)}`
		end
		return `{fmt(v)}s`
	end
	local what = ({
		damageMultiplier = "damage",
		goldMultiplier = "gold",
		duration = "long",
		cooldown = "cooldown",
		burstDpsSeconds = "of army damage",
		tapMultiplier = "clicks",
		healFraction = "heal",
		bountyKills = "kills",
	} :: { [string]: string })[def.stat] or ""
	if nextValue == nil then
		return `{show(now)} {what} (max)`
	end
	return `{show(now)} -> {show(nextValue)} {what}`
end

function HonorTab.build(parent: Instance, context: ShopTypes.Context): ShopTypes.Tab
	local rows: { [string]: Row } = {}
	local pending: { [string]: boolean } = {}
	local ascending = false
	local latest: Snapshot? = nil

	local frame = UIKit.create("Frame", {
		Name = "Honor",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = parent,
	}) :: Frame

	---------------------------------------------------------------- Ascend (left)
	local left = UIKit.create("Frame", {
		Name = "Ascend",
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Size = UDim2.new(0.38, -4, 1, 0),
		Parent = frame,
	}, { UIKit.corner(8), UIKit.padding(10) }) :: Frame

	local honorLabel = UIKit.label({
		Text = "",
		Font = Theme.FontBold,
		TextSize = 18,
		TextColor3 = HONOR_COLOR,
		Size = UDim2.new(1, -76, 0, 22),
		Parent = left,
	})
	-- Opens the Legacy window (shown once you're getting close to it, or after your first).
	local legacyButton = UIKit.button({
		Name = "LegacyButton",
		Text = "LEGACY",
		TextSize = 12,
		BackgroundColor3 = Color3.fromRGB(255, 200, 60),
		TextColor3 = Theme.Panel,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 72, 0, 22),
		Visible = false,
		Parent = left,
	})
	legacyButton.Activated:Connect(function()
		LegacyUI.open()
	end)
	local runLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 12,
		Position = UDim2.new(0, 0, 0, 24),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = left,
	})
	local previewLabel = UIKit.label({
		Text = "",
		TextSize = 13,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 0, 52),
		Parent = left,
	})
	local ascendButton = UIKit.button({
		Name = "AscendButton",
		Text = "ASCEND",
		TextSize = 18,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 44),
		Parent = left,
	})

	ascendButton.Activated:Connect(function()
		local snapshot = latest
		if snapshot == nil or ascending or BigNum.isZero(snapshot.ascendHonor) then
			return
		end
		AscendConfirmUI.show(snapshot.ascendHonor, function()
			ascending = true
			task.spawn(function()
				local result = ShopController.ascend()
				ascending = false
				if result.ok then
					local gained = if result.honor ~= nil then format(result.honor) else "0"
					NoticeUI.show("ASCENDED!", `+{gained} Honor. A new campaign begins.`, HONOR_COLOR)
				else
					context.showStatus(context.failMessage(result.reason))
				end
			end)
		end)
	end)

	---------------------------------------------------------------- Honor shop (right)
	local list = UIKit.create("ScrollingFrame", {
		Name = "Upgrades",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0.38, 4, 0, 0),
		Size = UDim2.new(0.62, -4, 1, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = frame,
	}, {
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	}) :: ScrollingFrame

	local function onBuy(upgradeId: string)
		if pending[upgradeId] then
			return
		end
		pending[upgradeId] = true
		task.spawn(function()
			local result = ShopController.buyHonorUpgrade(upgradeId)
			pending[upgradeId] = nil
			if not result.ok then
				context.showStatus(context.failMessage(result.reason))
			end
		end)
	end

	for order, upgradeId in HonorConfig.ORDER do
		local def = HonorConfig.UPGRADES[upgradeId]
		local row = UIKit.create("Frame", {
			Name = upgradeId,
			LayoutOrder = order,
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -8, 0, ROW_HEIGHT),
			Parent = list,
		}, { UIKit.corner(6) }) :: Frame

		UIKit.label({
			Text = def.displayName,
			Font = Theme.FontBold,
			TextSize = 13,
			Position = UDim2.new(0, 8, 0, 3),
			Size = UDim2.new(0.5, -8, 0, 16),
			Parent = row,
		})
		local level = UIKit.label({
			Text = "",
			TextColor3 = HONOR_COLOR,
			TextSize = 12,
			Position = UDim2.new(0.5, 0, 0, 3),
			Size = UDim2.new(0.5, -96, 0, 16),
			Parent = row,
		})
		local effect = UIKit.label({
			Text = "",
			TextColor3 = Theme.Muted,
			TextSize = 11,
			Position = UDim2.new(0, 8, 0, 21),
			Size = UDim2.new(1, -104, 0, 15),
			Parent = row,
		})
		local button = UIKit.button({
			Name = "Buy",
			Text = "",
			TextSize = 12,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			Size = UDim2.new(0, 88, 1, -8),
			Parent = row,
		})
		button.Activated:Connect(function()
			onBuy(upgradeId)
		end)
		rows[upgradeId] = { level = level, effect = effect, button = button }
	end

	-- Ability upgrades, under a heading, in the same list.
	local abilityRows: { [string]: Row } = {}
	local abilityPending: { [string]: boolean } = {}
	UIKit.label({
		Text = "Ability upgrades",
		Font = Theme.FontBold,
		TextSize = 14,
		TextColor3 = HONOR_COLOR,
		LayoutOrder = 100,
		Size = UDim2.new(1, -8, 0, 20),
		Parent = list,
	})
	for order, upgradeId in AbilityConfig.UPGRADE_ORDER do
		local def = AbilityConfig.UPGRADES[upgradeId]
		local row = UIKit.create("Frame", {
			Name = upgradeId,
			LayoutOrder = 100 + order,
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -8, 0, ROW_HEIGHT),
			Parent = list,
		}, { UIKit.corner(6) }) :: Frame
		UIKit.label({
			Text = def.displayName,
			Font = Theme.FontBold,
			TextSize = 13,
			Position = UDim2.new(0, 8, 0, 3),
			Size = UDim2.new(0.5, -8, 0, 16),
			Parent = row,
		})
		local level = UIKit.label({
			Text = "",
			TextColor3 = HONOR_COLOR,
			TextSize = 12,
			Position = UDim2.new(0.5, 0, 0, 3),
			Size = UDim2.new(0.5, -96, 0, 16),
			Parent = row,
		})
		local effect = UIKit.label({
			Text = "",
			TextColor3 = Theme.Muted,
			TextSize = 11,
			Position = UDim2.new(0, 8, 0, 21),
			Size = UDim2.new(1, -104, 0, 15),
			Parent = row,
		})
		local button = UIKit.button({
			Name = "Buy",
			Text = "",
			TextSize = 12,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			Size = UDim2.new(0, 88, 1, -8),
			Parent = row,
		})
		button.Activated:Connect(function()
			if abilityPending[upgradeId] then
				return
			end
			abilityPending[upgradeId] = true
			task.spawn(function()
				local result = ShopController.buyAbilityUpgrade(upgradeId)
				abilityPending[upgradeId] = nil
				if not result.ok then
					context.showStatus(context.failMessage(result.reason))
				end
			end)
		end)
		abilityRows[upgradeId] = { level = level, effect = effect, button = button }
	end

	local function renderAbilityRows(snapshot: Snapshot)
		for upgradeId, row in abilityRows do
			local def = AbilityConfig.UPGRADES[upgradeId]
			local ability = AbilityConfig.ABILITIES[def.abilityId]
			local current = snapshot.abilityUpgrades[upgradeId] or 0
			row.level.Text = `Lv {current}/{def.maxLevel}`
			row.effect.Text = abilityEffectText(def, current)
			if snapshot.bestStage < ability.unlockStage then
				row.button.Text = `Unlocks at\nstage {ability.unlockStage}`
				row.button.BackgroundColor3 = Theme.Disabled
				row.button.AutoButtonColor = false
			elseif current >= def.maxLevel then
				row.button.Text = "MAX"
				row.button.BackgroundColor3 = Theme.Disabled
				row.button.AutoButtonColor = false
			else
				local cost = Formulas.abilityUpgradeCost(upgradeId, current)
				local affordable = BigNum.gte(snapshot.honor, cost)
				row.button.Text = `Upgrade\n{format(cost)} Honor`
				row.button.BackgroundColor3 = if affordable then Theme.Good else Theme.Disabled
				row.button.AutoButtonColor = affordable
			end
		end
	end

	---------------------------------------------------------------- render
	local function render(snapshot: Snapshot)
		renderAbilityRows(snapshot)
		latest = snapshot
		honorLabel.Text = `Honor: {format(snapshot.honor)}`
		legacyButton.Visible = LegacyUI.visibleFor(snapshot)
		legacyButton.Text = if snapshot.legacyCrowns > 0 then "LEGACY!" else "LEGACY"
		runLabel.Text = `Best this run: stage {snapshot.highestStage}  |  Ascensions: {snapshot.ascensions}`

		local canAscend = not BigNum.isZero(snapshot.ascendHonor)
		if canAscend then
			local nextStage = Formulas.nextHonorStage(snapshot.highestStage)
			local nextHonor = Formulas.ascendHonor(nextStage, snapshot.crownUpgrades, snapshot.skillRanks)
			previewLabel.Text = `Ascend now for +{format(snapshot.ascendHonor)} Honor.\n`
				.. `Reach stage {nextStage} for +{format(nextHonor)}.`
			previewLabel.TextColor3 = Theme.Text
		else
			previewLabel.Text = `Reach stage {AscendConfig.MIN_STAGE} to Ascend.\n`
				.. `(Best this run: {snapshot.highestStage})`
			previewLabel.TextColor3 = Theme.Muted
		end
		ascendButton.BackgroundColor3 = if canAscend then HONOR_COLOR else Theme.Disabled
		ascendButton.TextColor3 = if canAscend then Theme.Panel else Theme.Muted
		ascendButton.AutoButtonColor = canAscend

		for _, upgradeId in HonorConfig.ORDER do
			local def = HonorConfig.UPGRADES[upgradeId]
			local row = rows[upgradeId]
			local current = snapshot.honorUpgrades[upgradeId] or 0
			row.level.Text = if def.maxLevel ~= nil then `Lv {math.min(current, def.maxLevel)}/{def.maxLevel}` else `Lv {current}`
			row.effect.Text = `{def.description}  ({effectText(def, current, snapshot.honorUpgrades)})`

			if def.maxLevel ~= nil and current >= def.maxLevel then
				row.button.Text = "MAX"
				row.button.BackgroundColor3 = Theme.Disabled
				row.button.AutoButtonColor = false
			else
				local cost = Formulas.honorUpgradeCost(upgradeId, current)
				local affordable = BigNum.gte(snapshot.honor, cost)
				row.button.Text = `Upgrade\n{format(cost)} Honor`
				row.button.BackgroundColor3 = if affordable then Theme.Good else Theme.Disabled
				row.button.AutoButtonColor = affordable
			end
		end
	end

	return {
		title = "Honor",
		frame = frame,
		modes = {},
		render = render,
	}
end

return HonorTab
