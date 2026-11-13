--!strict
-- Clan window tab: the bank (donate gold as Supplies) and clan perks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local ClanConfig = require(Shared:WaitForChild("Config"):WaitForChild("ClanConfig"))
local UIKit = require(script.Parent.UIKit)
local ClanTypes = require(script.Parent.ClanTypes)

type ClanView = Types.ClanView
type ClanPerkDef = Types.ClanPerkDef

local Theme = UIKit.Theme
local fmt = NumberFormat.number

type PerkRow = { level: TextLabel, effect: TextLabel, button: TextButton }

local ClanBankTab = {}

local function perkEffect(def: ClanPerkDef, level: number): string
	local multiplier = def.damageMultiplier or def.goldMultiplier or def.armyHpMultiplier or def.raidMultiplier or 1
	return `now x{fmt(multiplier ^ level)}`
end

function ClanBankTab.build(parent: Instance, context: ClanTypes.Context): ClanTypes.Tab
	local frame = UIKit.create("Frame", {
		Name = "Bank",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = parent,
	}) :: Frame

	---------------------------------------------------------------- donate (left)
	local left = UIKit.create("Frame", {
		Name = "Donate",
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Size = UDim2.new(0.42, -4, 1, 0),
		Parent = frame,
	}, { UIKit.corner(8), UIKit.padding(10) }) :: Frame

	local bankLabel = UIKit.label({
		Text = "",
		Font = Theme.FontBold,
		TextSize = 18,
		TextColor3 = Theme.Gold,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = left,
	})
	local priceLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 12,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Position = UDim2.new(0, 0, 0, 24),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = left,
	})
	local todayLabel = UIKit.label({
		Text = "",
		TextSize = 13,
		Position = UDim2.new(0, 0, 0, 56),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = left,
	})

	local amounts: { number } = table.clone(ClanConfig.DONATION_PRESETS)
	table.insert(amounts, -1) -- -1 = Max
	local donateButtons: { [number]: TextButton } = {}
	local donating = false
	for index, amount in amounts do
		local column = (index - 1) % 2
		local row = (index - 1) // 2
		local button = UIKit.button({
			Text = "",
			TextSize = 12,
			Position = UDim2.new(column * 0.5, if column == 0 then 0 else 3, 0, 78 + row * 46),
			Size = UDim2.new(0.5, -3, 0, 42),
			Parent = left,
		})
		button.Activated:Connect(function()
			if donating then
				return
			end
			local toSend = button:GetAttribute("Amount")
			if typeof(toSend) ~= "number" or toSend <= 0 then
				return
			end
			donating = true
			task.spawn(function()
				context.request("Donate", toSend)
				donating = false
			end)
		end)
		donateButtons[amount] = button
	end

	---------------------------------------------------------------- perks (right)
	local list = UIKit.create("ScrollingFrame", {
		Name = "Perks",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0.42, 4, 0, 0),
		Size = UDim2.new(0.58, -4, 1, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = frame,
	}, {
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	}) :: ScrollingFrame

	local perkRows: { [string]: PerkRow } = {}
	for order, perkId in ClanConfig.PERK_ORDER do
		local def = ClanConfig.PERKS[perkId]
		local row = UIKit.create("Frame", {
			Name = perkId,
			LayoutOrder = order,
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -8, 0, 44),
			Parent = list,
		}, { UIKit.corner(6) }) :: Frame
		UIKit.label({
			Text = def.displayName,
			Font = Theme.FontBold,
			TextSize = 13,
			Position = UDim2.new(0, 8, 0, 4),
			Size = UDim2.new(0.5, -8, 0, 16),
			Parent = row,
		})
		local level = UIKit.label({
			Text = "",
			TextColor3 = Theme.Gold,
			TextSize = 12,
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.new(0.5, -100, 0, 16),
			Parent = row,
		})
		local effect = UIKit.label({
			Text = "",
			TextColor3 = Theme.Muted,
			TextSize = 11,
			Position = UDim2.new(0, 8, 0, 23),
			Size = UDim2.new(1, -108, 0, 15),
			Parent = row,
		})
		local button = UIKit.button({
			Text = "",
			TextSize = 11,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			Size = UDim2.new(0, 92, 1, -8),
			Parent = row,
		})
		button.Activated:Connect(function()
			task.spawn(function()
				context.request("BuyPerk", perkId)
			end)
		end)
		perkRows[perkId] = { level = level, effect = effect, button = button }
	end

	local function render(view: ClanView, snapshot: Types.Snapshot?)
		local clan = view.clan
		if clan == nil then
			return
		end
		bankLabel.Text = `Bank: {fmt(clan.bank)} Supplies`
		local remaining = math.max(0, ClanConfig.DONATION_DAILY_CAP - view.donatedToday)
		todayLabel.Text = `Donated today: {fmt(view.donatedToday)} / {fmt(ClanConfig.DONATION_DAILY_CAP)}`

		local price = if snapshot ~= nil then Formulas.goldPerSupply(snapshot.highestStage) else BigNum.ONE
		priceLabel.Text = `1 Supply = {NumberFormat.big(price)} gold (one kill's worth at your best stage this run).`
		local affordable = if snapshot ~= nil
			then math.floor(BigNum.toNumber(BigNum.div(snapshot.gold, price)))
			else 0

		for amount, button in donateButtons do
			local actual = if amount < 0 then math.min(remaining, affordable) else math.min(amount, remaining)
			local canDo = actual > 0 and actual <= affordable
			button:SetAttribute("Amount", if canDo then actual else 0)
			local label = if amount < 0 then "Max" else `+{amount}`
			button.Text = if canDo
				then `{label} Supplies\n{NumberFormat.big(BigNum.mulNumber(price, actual))} gold`
				else `{label}\n{if remaining <= 0 then "Daily cap reached" else "Not enough gold"}`
			button.BackgroundColor3 = if canDo then Theme.Good else Theme.Disabled
			button.AutoButtonColor = canDo
		end

		local canBuy = view.myRole == "Leader" or view.myRole == "Officer"
		for perkId, row in perkRows do
			local def = ClanConfig.PERKS[perkId]
			local level = clan.perks[perkId] or 0
			row.level.Text = `Lv {level}/{def.maxLevel}`
			row.effect.Text = `{def.description} ({perkEffect(def, level)})`
			if level >= def.maxLevel then
				row.button.Text = "MAX"
				row.button.BackgroundColor3 = Theme.Disabled
				row.button.AutoButtonColor = false
			else
				local cost = Formulas.clanPerkCost(perkId, level)
				local enough = clan.bank >= cost
				row.button.Text = if canBuy then `Buy\n{fmt(cost)} Supplies` else `{fmt(cost)} Supplies\nOfficers buy`
				local active = canBuy and enough
				row.button.BackgroundColor3 = if active then Theme.Good else Theme.Disabled
				row.button.AutoButtonColor = active
			end
		end
	end

	return { title = "Bank", frame = frame, render = render }
end

return ClanBankTab
