--!strict
-- Pack opening popup: a short rarity "shuffle", then the result.
-- The result was already decided by the server before this starts; the shuffle is only
-- for fun.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local GearInfo = require(Shared:WaitForChild("GearInfo"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local GearConfig = require(Shared:WaitForChild("Config"):WaitForChild("GearConfig"))
local UIKit = require(script.Parent.UIKit)

type PackResult = Types.PackResult

local Theme = UIKit.Theme

local SHUFFLE_SECONDS = 0.9
local SHUFFLE_STEP = 0.07
local AUTO_CLOSE_SECONDS = 5

local overlay: Frame
local card: Frame
local rarityLabel: TextLabel
local itemLabel: TextLabel
local detailLabel: TextLabel
local cardStroke: UIStroke
local showToken = 0

local PackRevealUI = {}

local function hide()
	overlay.Visible = false
end

local function setRarity(index: number)
	local rarity = GearInfo.rarity(index)
	rarityLabel.Text = string.upper(rarity.name)
	rarityLabel.TextColor3 = rarity.color
	cardStroke.Color = rarity.color
end

-- Shows the reveal. Yields until the shuffle finishes (about a second).
function PackRevealUI.show(result: PackResult)
	local troopId, slot, rarity = result.troopId, result.slot, result.rarity
	if not result.ok or troopId == nil or slot == nil or rarity == nil then
		return
	end
	showToken += 1
	local token = showToken

	overlay.Visible = true
	itemLabel.Text = "Opening..."
	detailLabel.Text = ""

	local elapsed = 0
	while elapsed < SHUFFLE_SECONDS do
		setRarity(math.random(1, #GearConfig.RARITIES))
		task.wait(SHUFFLE_STEP)
		elapsed += SHUFFLE_STEP
	end
	if showToken ~= token then
		return
	end

	setRarity(rarity)
	local rarityDef = GearInfo.rarity(rarity)
	itemLabel.Text = GearInfo.slotLabel(troopId, slot)
	local statName = GearConfig.SLOT_INFO[slot].statName
	if result.upgraded then
		detailLabel.Text = `Upgraded to {rarityDef.name}! Rarity bonus is now x{NumberFormat.number(
			Formulas.rarityMultiplier(rarity)
		)} {statName}.`
		detailLabel.TextColor3 = Theme.Gold
	else
		local refund = if result.refund ~= nil then NumberFormat.big(result.refund) else "0"
		detailLabel.Text = `Not better than what you have. Refunded {refund} gold.`
		detailLabel.TextColor3 = Theme.Muted
	end

	task.delay(AUTO_CLOSE_SECONDS, function()
		if showToken == token then
			hide()
		end
	end)
end

function PackRevealUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = UIKit.create("ScreenGui", {
		Name = "PackReveal",
		ResetOnSpawn = false,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	-- Full-screen dim layer. Clicking anywhere closes the popup.
	local dim = UIKit.create("TextButton", {
		Name = "Overlay",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = gui,
	}) :: TextButton
	dim.Activated:Connect(hide)
	overlay = dim

	card = UIKit.create("Frame", {
		Name = "Card",
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.45, 0),
		Size = UDim2.new(0, 380, 0, 190),
		Parent = dim,
	}, { UIKit.corner(14), UIKit.padding(14) }) :: Frame
	cardStroke = UIKit.create("UIStroke", { Thickness = 4, Parent = card }) :: UIStroke

	UIKit.label({
		Text = "GEAR PACK",
		TextColor3 = Theme.Muted,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 16),
		Parent = card,
	})
	rarityLabel = UIKit.label({
		Text = "",
		Font = Theme.FontBold,
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 20),
		Size = UDim2.new(1, 0, 0, 42),
		Parent = card,
	})
	itemLabel = UIKit.label({
		Text = "",
		Font = Theme.FontBold,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 66),
		Size = UDim2.new(1, 0, 0, 26),
		Parent = card,
	})
	detailLabel = UIKit.label({
		Text = "",
		TextSize = 15,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 96),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = card,
	})
	UIKit.label({
		Text = "Click anywhere to close",
		TextColor3 = Theme.Muted,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 1, -14),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = card,
	})

	gui.Parent = playerGui
end

return PackRevealUI
