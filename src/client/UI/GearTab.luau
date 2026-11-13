--!strict
-- Shop tab: gear. One row per troop type with its Weapon and Armor slots.
-- Each slot shows its name ("Rare Steel Bow", colored by rarity), level, multiplier, and
-- an upgrade button (x1 or Max, mode from ShopUI).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local GearInfo = require(Shared:WaitForChild("GearInfo"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Config = Shared:WaitForChild("Config")
local TroopConfig = require(Config:WaitForChild("TroopConfig"))
local GearConfig = require(Config:WaitForChild("GearConfig"))
local UIKit = require(script.Parent.UIKit)
local ShopTypes = require(script.Parent.ShopTypes)
local ShopController = require(Client.Controllers.ShopController)

type Snapshot = Types.Snapshot
type GearSlot = Types.GearSlot

local Theme = UIKit.Theme
local format = NumberFormat.big

local ROW_HEIGHT = 56
local NAME_WIDTH = 100
local BUTTON_WIDTH = 92

type Cell = { name: TextLabel, stats: TextLabel, button: TextButton }

local GearTab = {}

local function slotState(snapshot: Snapshot, troopId: string, slot: GearSlot): Types.GearSlotState
	local troopGear = snapshot.gear[troopId]
	if troopGear == nil then
		return { level = 0, rarity = 1 }
	end
	return if slot == "weapon" then troopGear.weapon else troopGear.armor
end

function GearTab.build(parent: Instance, context: ShopTypes.Context): ShopTypes.Tab
	local cells: { [string]: Cell } = {}
	local pending: { [string]: boolean } = {}

	local frame = UIKit.create("Frame", {
		Name = "Gear",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = parent,
	}, {
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	}) :: Frame

	local function onUpgrade(troopId: string, slot: GearSlot)
		local key = troopId .. slot
		if pending[key] then
			return
		end
		pending[key] = true
		local mode: Types.GearBuyMode = if context.getMode() == "Max" then "Max" else "One"
		task.spawn(function()
			local result = ShopController.upgradeGear(troopId, slot, mode)
			pending[key] = nil
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
			TextSize = 16,
			Position = UDim2.new(0, 22, 0, 0),
			Size = UDim2.new(0, NAME_WIDTH - 22, 1, 0),
			Parent = row,
		})

		for slotIndex, slot in GearConfig.SLOTS do
			-- Two cells side by side, splitting the space after the troop name.
			local cell = UIKit.create("Frame", {
				Name = slot,
				BackgroundTransparency = 1,
				Position = UDim2.new((slotIndex - 1) / 2, if slotIndex == 1 then NAME_WIDTH else NAME_WIDTH / 2, 0, 0),
				Size = UDim2.new(0.5, -NAME_WIDTH / 2 - 4, 1, 0),
				Parent = row,
			}) :: Frame
			local name = UIKit.label({
				Text = "",
				Font = Theme.FontBold,
				TextSize = 13,
				Position = UDim2.new(0, 0, 0, 7),
				Size = UDim2.new(1, -BUTTON_WIDTH - 6, 0, 18),
				Parent = cell,
			})
			local stats = UIKit.label({
				Text = "",
				TextColor3 = Theme.Muted,
				TextSize = 12,
				Position = UDim2.new(0, 0, 0, 29),
				Size = UDim2.new(1, -BUTTON_WIDTH - 6, 0, 18),
				Parent = cell,
			})
			local button = UIKit.button({
				Name = "Upgrade",
				Text = "",
				TextSize = 12,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				Size = UDim2.new(0, BUTTON_WIDTH, 1, -12),
				Parent = cell,
			})
			button.Activated:Connect(function()
				onUpgrade(troopId, slot)
			end)
			cells[troopId .. slot] = { name = name, stats = stats, button = button }
		end
	end

	local function render(snapshot: Snapshot)
		local mode = context.getMode()
		for _, troopId in TroopConfig.ORDER do
			for _, slot in GearConfig.SLOTS do
				local cell = cells[troopId .. slot]
				local state = slotState(snapshot, troopId, slot)
				local statName = GearConfig.SLOT_INFO[slot].statName
				local multiplier = Formulas.gearMultiplier(state)

				cell.name.Text = GearInfo.itemName(troopId, slot, state)
				cell.name.TextColor3 = GearInfo.rarity(state.rarity).color
				cell.stats.Text = `Lv {state.level}  |  x{NumberFormat.number(multiplier)} {statName}`

				if state.level >= GearConfig.MAX_LEVEL then
					cell.button.Text = "MAX"
					cell.button.BackgroundColor3 = Theme.Disabled
					cell.button.AutoButtonColor = false
				else
					local cap = if mode == "Max"
						then math.min(GearConfig.MAX_LEVELS_PER_REQUEST, GearConfig.MAX_LEVEL - state.level)
						else 1
					local levels, cost = Formulas.gearMaxAffordable(troopId, state.level, snapshot.gold, cap)
					local affordable = levels > 0
					if not affordable then
						levels, cost = 1, Formulas.gearUpgradeCost(troopId, state.level)
					end
					cell.button.Text = `+{levels} Lv\n{format(cost)}`
					cell.button.BackgroundColor3 = if affordable and BigNum.gte(snapshot.gold, cost)
						then Theme.Good
						else Theme.Disabled
					cell.button.AutoButtonColor = affordable
				end
			end
		end
	end

	return {
		title = "Gear",
		frame = frame,
		modes = { "One", "Max" },
		render = render,
	}
end

return GearTab
