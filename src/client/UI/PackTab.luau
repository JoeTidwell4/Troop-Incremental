--!strict
-- Shop tab: gear packs. Buy with gold or open free packs earned from bosses.
-- Shows the exact odds and how close the guaranteed Epic is.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local GearInfo = require(Shared:WaitForChild("GearInfo"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Config = Shared:WaitForChild("Config")
local PackConfig = require(Config:WaitForChild("PackConfig"))
local GearConfig = require(Config:WaitForChild("GearConfig"))
local UIKit = require(script.Parent.UIKit)
local ShopTypes = require(script.Parent.ShopTypes)
local PackRevealUI = require(script.Parent.PackRevealUI)
local ShopController = require(Client.Controllers.ShopController)

type Snapshot = Types.Snapshot

local Theme = UIKit.Theme
local format = NumberFormat.big

local PackTab = {}

function PackTab.build(parent: Instance, context: ShopTypes.Context): ShopTypes.Tab
	local opening = false

	local frame = UIKit.create("Frame", {
		Name = "Packs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = parent,
	}) :: Frame

	-- Left: description, buttons, pity counter.
	local left = UIKit.create("Frame", {
		Name = "Open",
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Size = UDim2.new(0.6, -4, 1, 0),
		Parent = frame,
	}, { UIKit.corner(8), UIKit.padding(10) }) :: Frame

	UIKit.label({
		Text = "Gear Pack",
		Font = Theme.FontBold,
		TextSize = 18,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = left,
	})
	UIKit.label({
		Text = "Random troop + Weapon/Armor + rarity. Better rarity upgrades that slot; "
			.. `otherwise you get {math.floor(PackConfig.DUPLICATE_REFUND * 100)}% of the price back.`,
		TextColor3 = Theme.Muted,
		TextSize = 12,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 0, 0, 24),
		Size = UDim2.new(1, 0, 0, 32),
		Parent = left,
	})

	local buyButton = UIKit.button({
		Name = "Buy",
		Text = "",
		TextSize = 14,
		Position = UDim2.new(0, 0, 0, 64),
		Size = UDim2.new(1 / 3, -4, 0, 48),
		Parent = left,
	})
	local freeButton = UIKit.button({
		Name = "Free",
		Text = "",
		TextSize = 14,
		Position = UDim2.new(1 / 3, 2, 0, 64),
		Size = UDim2.new(1 / 3, -4, 0, 48),
		Parent = left,
	})
	local heroButton = UIKit.button({
		Name = "Hero",
		Text = "",
		TextSize = 14,
		Position = UDim2.new(2 / 3, 4, 0, 64),
		Size = UDim2.new(1 / 3, -4, 0, 48),
		Parent = left,
	})
	local pityLabel = UIKit.label({
		Text = "",
		TextColor3 = GearInfo.rarity(PackConfig.PITY_MIN_RARITY).color,
		TextSize = 13,
		Position = UDim2.new(0, 0, 0, 120),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = left,
	})
	UIKit.label({
		Text = "Free packs: beat new bosses. Hero Chests (Epic+): daily login rewards.",
		TextColor3 = Theme.Muted,
		TextSize = 12,
		Position = UDim2.new(0, 0, 0, 140),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = left,
	})

	-- Right: odds table.
	local right = UIKit.create("Frame", {
		Name = "Odds",
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Position = UDim2.new(0.6, 4, 0, 0),
		Size = UDim2.new(0.4, -4, 1, 0),
		Parent = frame,
	}, {
		UIKit.corner(8),
		UIKit.padding(10),
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	}) :: Frame
	UIKit.label({
		Text = "Odds",
		Font = Theme.FontBold,
		TextSize = 15,
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 18),
		Parent = right,
	})
	for index, rarity in GearConfig.RARITIES do
		UIKit.label({
			Text = `{rarity.name}  {PackConfig.ODDS[index]}%  (x{rarity.multiplier})`,
			TextColor3 = rarity.color,
			Font = Theme.FontBold,
			TextSize = 13,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 18),
			Parent = right,
		})
	end

	local function open(mode: "Gold" | "Free" | "Hero")
		if opening then
			return
		end
		opening = true
		task.spawn(function()
			local result = ShopController.openPack(mode)
			if result.ok then
				PackRevealUI.show(result) -- yields through the shuffle
			else
				context.showStatus(context.failMessage(result.reason))
			end
			opening = false
		end)
	end
	buyButton.Activated:Connect(function()
		open("Gold")
	end)
	freeButton.Activated:Connect(function()
		open("Free")
	end)
	heroButton.Activated:Connect(function()
		open("Hero")
	end)

	local function render(snapshot: Snapshot)
		local affordable = BigNum.gte(snapshot.gold, snapshot.packPrice)
		buyButton.Text = `Open Pack\n{format(snapshot.packPrice)} gold`
		buyButton.BackgroundColor3 = if affordable then Theme.Good else Theme.Disabled
		buyButton.AutoButtonColor = affordable

		local free = snapshot.packs.free
		freeButton.Text = `Open Free\n{free} left`
		freeButton.BackgroundColor3 = if free > 0 then Theme.Gold else Theme.Disabled
		freeButton.TextColor3 = if free > 0 then Theme.Panel else Theme.Text
		freeButton.AutoButtonColor = free > 0

		local hero = snapshot.packs.hero
		heroButton.Text = `Hero Chest
{hero} left`
		heroButton.BackgroundColor3 = if hero > 0 then GearInfo.rarity(4).color else Theme.Disabled
		heroButton.AutoButtonColor = hero > 0

		local packsLeft = math.max(1, PackConfig.PITY_EVERY - snapshot.packs.sinceEpic)
		local pityName = GearInfo.rarity(PackConfig.PITY_MIN_RARITY).name
		local plural = if packsLeft == 1 then "" else "s"
		pityLabel.Text = `{pityName} or better guaranteed within {packsLeft} pack{plural}`
	end

	return {
		title = "Packs",
		frame = frame,
		modes = {},
		render = render,
	}
end

return PackTab
