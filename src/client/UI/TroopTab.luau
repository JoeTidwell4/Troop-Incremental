--!strict
-- Shop tab: train troops. One row per troop type; buy x1 / x10 / Max (mode from ShopUI).
-- Prices are calculated locally for display only; the server re-checks every purchase.
-- Troops with an unlockStage show as locked rows until your best stage reaches it.
-- Scrolls, since there are more troop types than fit in the shop at once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Areas = require(Shared:WaitForChild("Areas"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local TroopConfig = require(Shared:WaitForChild("Config"):WaitForChild("TroopConfig"))
local UIKit = require(script.Parent.UIKit)
local ShopTypes = require(script.Parent.ShopTypes)
local ShopController = require(Client.Controllers.ShopController)
local Spotlight = require(script.Parent.Spotlight)

type Snapshot = Types.Snapshot
type BuyMode = Types.BuyMode

local Theme = UIKit.Theme
local format = NumberFormat.big

local ROW_HEIGHT = 56

type Row = { frame: Frame, owned: TextLabel, info: TextLabel, button: TextButton }

local TroopTab = {}

function TroopTab.build(parent: Instance, context: ShopTypes.Context): ShopTypes.Tab
	local rows: { [string]: Row } = {}
	local pending: { [string]: boolean } = {}

	local frame = UIKit.create("ScrollingFrame", {
		Name = "Troops",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		Parent = parent,
	}, {
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		UIKit.create("UIPadding", { PaddingRight = UDim.new(0, 10) }),
	}) :: ScrollingFrame

	-- What the buy button would buy right now: (amount, cost, affordable).
	local function preview(troopId: string, snapshot: Snapshot): (number, BigNum.BigNum, boolean)
		local mode = context.getMode()
		local owned = snapshot.troops[troopId] or 0
		local cap = math.min(TroopConfig.MAX_BUY_PER_REQUEST, TroopConfig.MAX_PER_TYPE - owned)
		if mode == "Max" then
			local amount, cost = Formulas.maxAffordable(troopId, owned, snapshot.gold, cap)
			if amount > 0 then
				return amount, cost, true
			end
			-- Can't afford any: show the price of one so the player knows what to save for.
			return 1, Formulas.troopCost(troopId, owned, 1), false
		end
		local amount = if mode == "Ten" then 10 else 1
		local cost = Formulas.troopCost(troopId, owned, amount)
		return amount, cost, amount <= cap and BigNum.gte(snapshot.gold, cost)
	end

	local function onBuy(troopId: string)
		if pending[troopId] then
			return
		end
		pending[troopId] = true
		local mode = context.getMode() :: BuyMode
		task.spawn(function()
			local result = ShopController.buyTroop(troopId, mode)
			pending[troopId] = nil
			if not result.ok then
				context.showStatus(context.failMessage(result.reason))
			end
		end)
	end

	for order, troopId in TroopConfig.ORDER do
		local def = TroopConfig.TROOPS[troopId]
		local row = UIKit.create("Frame", {
			Name = troopId,
			LayoutOrder = order,
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			Parent = frame,
		}, { UIKit.corner(8) }) :: Frame

		UIKit.create("Frame", {
			Name = "Swatch",
			BackgroundColor3 = def.color,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 8, 0, 8),
			Size = UDim2.new(0, 6, 1, -16),
			Parent = row,
		}, { UIKit.corner(3) })
		UIKit.label({
			Text = def.displayName,
			Font = Theme.FontBold,
			TextSize = 17,
			Position = UDim2.new(0, 22, 0, 6),
			Size = UDim2.new(0.3, -22, 0, 20),
			Parent = row,
		})
		UIKit.label({
			Text = def.role,
			TextColor3 = Theme.Muted,
			TextSize = 12,
			Position = UDim2.new(0, 22, 0, 30),
			Size = UDim2.new(0.3, -22, 0, 18),
			Parent = row,
		})
		local owned = UIKit.label({
			Text = "Owned: 0",
			TextColor3 = Theme.Gold,
			TextSize = 14,
			Position = UDim2.new(0.3, 0, 0, 6),
			Size = UDim2.new(0.7, -160, 0, 20),
			Parent = row,
		})
		local info = UIKit.label({
			Text = "",
			RichText = true,
			TextColor3 = Theme.Muted,
			TextSize = 12,
			Position = UDim2.new(0.3, 0, 0, 30),
			Size = UDim2.new(0.7, -160, 0, 18),
			Parent = row,
		})
		local button = UIKit.button({
			Name = "Buy",
			Text = "",
			TextSize = 14,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.new(0, 144, 1, -10),
			Parent = row,
		})
		button.Activated:Connect(function()
			onBuy(troopId)
		end)
		rows[troopId] = { frame = row, owned = owned, info = info, button = button }
		Spotlight.register(`Buy:{troopId}`, button)
	end

	local function render(snapshot: Snapshot)
		-- DPS is shown for the current fight: faction, area trait, and boss/normal jobs.
		-- Challenge rules change the numbers too (no Generals / no gear / one troop type).
		local rules = Formulas.challengeRules(snapshot.challengeActive)
		local _, generals = Formulas.fightBuild(snapshot.challengeActive, nil, snapshot.generals, nil)
		local gear = if rules.noGear then nil else snapshot.gear
		local factionBonus = Formulas.troopHpMultipliers(snapshot.faction, generals)
		local fightBonus = Formulas.fightDamageMultipliers(snapshot.faction, snapshot.stage, snapshot.encounter ~= "Normal", generals, snapshot.towerFloor)
		local trait = if snapshot.towerFloor > 0 then nil else Areas.forStage(snapshot.stage).theme.trait
		for _, troopId in TroopConfig.ORDER do
			local row = rows[troopId]
			local def = TroopConfig.TROOPS[troopId]
			if not Formulas.troopUnlocked(troopId, snapshot.bestStage) then
				row.frame.BackgroundTransparency = 0.5
				row.owned.Text = "LOCKED"
				row.info.Text = `Reach stage {def.unlockStage} to unlock`
				row.button.Text = `Unlocks at\nstage {def.unlockStage}`
				row.button.BackgroundColor3 = Theme.Disabled
				row.button.AutoButtonColor = false
				continue
			end
			if rules.onlyTroop ~= nil and troopId ~= rules.onlyTroop then
				row.frame.BackgroundTransparency = 0.5
				row.owned.Text = "CHALLENGE"
				row.info.Text = `Only {TroopConfig.TROOPS[rules.onlyTroop].displayName} can be trained in this challenge`
				row.button.Text = "Not in this\nchallenge"
				row.button.BackgroundColor3 = Theme.Disabled
				row.button.AutoButtonColor = false
				continue
			end
			row.frame.BackgroundTransparency = 0
			local count = snapshot.troops[troopId] or 0
			row.owned.Text = `Owned: {count}`
			local dps = format(Formulas.troopDps(troopId, count, gear, fightBonus))
			local hp = format(Formulas.troopHp(troopId, count, gear, factionBonus))
			local nextMilestone = Formulas.nextMilestone(count)
			local weak = if trait ~= nil and trait.troopId == troopId
				then `  <font color="#FF6E6E">({trait.name} area: -{math.floor((1 - trait.damageMultiplier) * 100 + 0.5)}%)</font>`
				else ""
			row.info.Text = `DPS {dps}  |  HP {hp}  |  x{TroopConfig.MILESTONE_MULTIPLIER} at {nextMilestone}{weak}`

			local amount, cost, affordable = preview(troopId, snapshot)
			row.button.Text = `Buy x{amount}\n{format(cost)} gold`
			row.button.BackgroundColor3 = if affordable then Theme.Good else Theme.Disabled
			row.button.AutoButtonColor = affordable
		end
	end

	return {
		title = "Troops",
		frame = frame,
		modes = { "One", "Ten", "Max" },
		render = render,
	}
end

return TroopTab
