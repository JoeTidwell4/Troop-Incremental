--!strict
-- Shop tab: gear packs. Three tiers bought with gold (Basic / Elite / Royal, see
-- PackConfig.TIERS), free packs from bosses, Hero Chests from the login calendar, and
-- Epic Forge tokens (Robux product). Shows the exact odds of the selected tier and how
-- close the guaranteed Epic is.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local GearInfo = require(Shared:WaitForChild("GearInfo"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Config = Shared:WaitForChild("Config")
local PackConfig = require(Config:WaitForChild("PackConfig"))
local GearConfig = require(Config:WaitForChild("GearConfig"))
local MonetizationConfig = require(Config:WaitForChild("MonetizationConfig"))
local UIKit = require(script.Parent.UIKit)
local ShopTypes = require(script.Parent.ShopTypes)
local PackRevealUI = require(script.Parent.PackRevealUI)
local ForgeUI = require(script.Parent.ForgeUI)
local WardrobeUI = require(script.Parent.WardrobeUI)
local ShopController = require(Client.Controllers.ShopController)
local MonetizationController = require(Client.Controllers.MonetizationController)

type Snapshot = Types.Snapshot

local Theme = UIKit.Theme
local format = NumberFormat.big

-- OpenPack mode for each paid tier ("Gold" is the Basic pack's mode name on the server).
local TIER_MODE: { [string]: string } = { Basic = "Gold", Elite = "Elite", Royal = "Royal" }
local FORGE_ON_SALE = MonetizationConfig.PRODUCTS.EpicForge.id > 0

local PackTab = {}

function PackTab.build(parent: Instance, context: ShopTypes.Context): ShopTypes.Tab
	local opening = false
	local selectedTier = "Basic"

	local frame = UIKit.create("Frame", {
		Name = "Packs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = parent,
	}) :: Frame

	-- Left: tier picker, open buttons, pity counter.
	local left = UIKit.create("Frame", {
		Name = "Open",
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Size = UDim2.new(0.62, -4, 1, 0),
		Parent = frame,
	}, { UIKit.corner(8), UIKit.padding(8) }) :: Frame

	-- Pack tiers, plus a shortcut to the Wardrobe Chests (commander gear) at the end.
	local tierButtons: { [string]: TextButton } = {}
	local columns = #PackConfig.TIER_ORDER + 1
	for index, tierId in PackConfig.TIER_ORDER do
		local button = UIKit.button({
			Name = tierId,
			Text = "",
			TextSize = 12,
			BackgroundColor3 = Theme.Panel,
			Position = UDim2.new((index - 1) / columns, if index == 1 then 0 else 2, 0, 0),
			Size = UDim2.new(1 / columns, -4, 0, 30),
			Parent = left,
		})
		tierButtons[tierId] = button
	end
	local chestsButton = UIKit.button({
		Name = "WardrobeChests",
		Text = "Wardrobe Chests",
		TextSize = 12,
		BackgroundColor3 = Color3.fromRGB(60, 140, 130),
		Position = UDim2.new((columns - 1) / columns, 2, 0, 0),
		Size = UDim2.new(1 / columns, -4, 0, 30),
		Parent = left,
	})
	chestsButton.Activated:Connect(function()
		WardrobeUI.open("Chests")
	end)

	-- Open (selected tier) | Free | Hero | Forge (Forge only when it's on sale or owned).
	local function actionButton(index: number, name: string): TextButton
		return UIKit.button({
			Name = name,
			Text = "",
			TextSize = 13,
			Position = UDim2.new((index - 1) / 4, if index == 1 then 0 else 2, 0, 36),
			Size = UDim2.new(1 / 4, -4, 0, 46),
			Parent = left,
		})
	end
	local buyButton = actionButton(1, "Buy")
	local freeButton = actionButton(2, "Free")
	local heroButton = actionButton(3, "Hero")
	local forgeButton = actionButton(4, "Forge")

	local pityLabel = UIKit.label({
		Text = "",
		TextColor3 = GearInfo.rarity(PackConfig.PITY_MIN_RARITY).color,
		TextSize = 13,
		Position = UDim2.new(0, 0, 0, 88),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = left,
	})
	UIKit.label({
		Text = "Free packs: beat new bosses. Hero Chests (Epic+): daily login. "
			.. `Duplicates give back {math.floor(PackConfig.DUPLICATE_REFUND * 100)}% of the price.`,
		TextColor3 = Theme.Muted,
		TextSize = 11,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 0, 0, 106),
		Size = UDim2.new(1, 0, 0, 28),
		Parent = left,
	})

	-- Right: odds of the selected tier.
	local right = UIKit.create("Frame", {
		Name = "Odds",
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Position = UDim2.new(0.62, 4, 0, 0),
		Size = UDim2.new(0.38, -4, 1, 0),
		Parent = frame,
	}, {
		UIKit.corner(8),
		UIKit.padding(8),
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
	}) :: Frame
	local oddsTitle = UIKit.label({
		Text = "",
		Font = Theme.FontBold,
		TextSize = 14,
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 18),
		Parent = right,
	})
	local oddsLabels: { TextLabel } = {}
	for index, rarity in GearConfig.RARITIES do
		oddsLabels[index] = UIKit.label({
			Text = "",
			TextColor3 = rarity.color,
			Font = Theme.FontBold,
			TextSize = 13,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 18),
			Parent = right,
		})
	end

	local function open(mode: string)
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

	local lastSnapshot: Snapshot? = nil
	local function render(snapshot: Snapshot)
		lastSnapshot = snapshot
		for tierId, button in tierButtons do
			local tier = PackConfig.TIERS[tierId]
			local unlocked = snapshot.bestStage >= tier.unlockStage
			button.Text = if unlocked then tier.displayName else `{tierId} (stage {tier.unlockStage})`
			button.BackgroundColor3 = if tierId == selectedTier then Theme.Accent elseif unlocked then Theme.Panel else Theme.Disabled
		end

		local tier = PackConfig.TIERS[selectedTier]
		local unlocked = snapshot.bestStage >= tier.unlockStage
		local price = Formulas.packPrice(snapshot.highestStage, selectedTier)
		local affordable = unlocked and BigNum.gte(snapshot.gold, price)
		buyButton.Text = if unlocked then `Open {selectedTier}\n{format(price)}` else `Locked\nstage {tier.unlockStage}`
		buyButton.BackgroundColor3 = if affordable then Theme.Good else Theme.Disabled
		buyButton.AutoButtonColor = affordable

		oddsTitle.Text = `{tier.displayName} odds`
		for index, rarity in GearConfig.RARITIES do
			local chance = tier.odds[index] or 0
			oddsLabels[index].Text = `{rarity.name}  {chance}%  (x{rarity.multiplier})`
			oddsLabels[index].TextTransparency = if chance > 0 then 0 else 0.6
		end

		local free = snapshot.packs.free
		freeButton.Text = `Free Pack\n{free} left`
		freeButton.BackgroundColor3 = if free > 0 then Theme.Gold else Theme.Disabled
		freeButton.TextColor3 = if free > 0 then Theme.Panel else Theme.Text
		freeButton.AutoButtonColor = free > 0

		local hero = snapshot.packs.hero
		heroButton.Text = `Hero Chest\n{hero} left`
		heroButton.BackgroundColor3 = if hero > 0 then GearInfo.rarity(4).color else Theme.Disabled
		heroButton.AutoButtonColor = hero > 0

		local forge = snapshot.packs.forge
		forgeButton.Visible = FORGE_ON_SALE or forge > 0
		forgeButton.Text = if forge > 0 then `Epic Forge\n{forge} left` else "Epic Forge\nin Store"
		forgeButton.BackgroundColor3 = if forge > 0 then GearInfo.rarity(PackConfig.FORGE_RARITY).color else Theme.PanelLight

		local packsLeft = math.max(1, PackConfig.PITY_EVERY - snapshot.packs.sinceEpic)
		local pityName = GearInfo.rarity(PackConfig.PITY_MIN_RARITY).name
		local plural = if packsLeft == 1 then "" else "s"
		pityLabel.Text = `{pityName} or better guaranteed within {packsLeft} pack{plural}`
	end

	for tierId, button in tierButtons do
		button.Activated:Connect(function()
			selectedTier = tierId
			if lastSnapshot ~= nil then
				render(lastSnapshot)
			end
		end)
	end
	buyButton.Activated:Connect(function()
		open(TIER_MODE[selectedTier])
	end)
	freeButton.Activated:Connect(function()
		open("Free")
	end)
	heroButton.Activated:Connect(function()
		open("Hero")
	end)
	forgeButton.Activated:Connect(function()
		local snapshot = lastSnapshot
		if snapshot ~= nil and snapshot.packs.forge > 0 then
			ForgeUI.open()
		elseif FORGE_ON_SALE then
			MonetizationController.promptProduct("EpicForge")
		end
	end)

	return {
		title = "Packs",
		frame = frame,
		modes = {},
		render = render,
	}
end

return PackTab
