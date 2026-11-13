--!strict
-- "Are you sure?" popup before Ascending, since it wipes the current run.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared:WaitForChild("BigNum"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local UIKit = require(script.Parent.UIKit)

local Theme = UIKit.Theme

local overlay: Frame
local honorLabel: TextLabel
local onConfirm: (() -> ())? = nil

local AscendConfirmUI = {}

local function close()
	overlay.Visible = false
	onConfirm = nil
end

-- Opens the popup. `confirm` runs only if the player clicks ASCEND.
function AscendConfirmUI.show(honor: BigNum.BigNum, confirm: () -> ())
	honorLabel.Text = `+{NumberFormat.big(honor)} Honor`
	onConfirm = confirm
	UIKit.openModal(overlay, overlay:FindFirstChild("Card") :: Frame)
end

function AscendConfirmUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = UIKit.create("ScreenGui", {
		Name = "AscendConfirm",
		ResetOnSpawn = false,
		DisplayOrder = 25,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	overlay = UIKit.create("Frame", {
		Name = "Overlay",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Active = true, -- blocks clicks from reaching the battlefield
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = gui,
	}) :: Frame

	local card = UIKit.create("Frame", {
		Name = "Card",
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.45, 0),
		Size = UDim2.new(0, 420, 0, 250),
		Parent = overlay,
	}, { UIKit.corner(14), UIKit.padding(16) }) :: Frame
	UIKit.create("UIStroke", { Color = Theme.Gold, Thickness = 3, Parent = card })

	UIKit.label({
		Text = "Ascend?",
		Font = Theme.FontBold,
		TextSize = 28,
		TextColor3 = Theme.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 32),
		Parent = card,
	})
	honorLabel = UIKit.label({
		Text = "",
		Font = Theme.FontBold,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 36),
		Size = UDim2.new(1, 0, 0, 26),
		Parent = card,
	})
	UIKit.label({
		Text = "You will LOSE: gold, troops, gear (levels and rarity), and your stage.\n"
			.. "You KEEP: Honor, Honor upgrades, unlocked abilities, and unopened free packs.",
		TextColor3 = Theme.Muted,
		TextSize = 14,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 0, 0, 72),
		Size = UDim2.new(1, 0, 0, 80),
		Parent = card,
	})

	local cancel = UIKit.button({
		Name = "Cancel",
		Text = "Cancel",
		TextSize = 16,
		BackgroundColor3 = Theme.PanelLight,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(0.5, -6, 0, 44),
		Parent = card,
	})
	local confirm = UIKit.button({
		Name = "Confirm",
		Text = "ASCEND",
		TextSize = 18,
		BackgroundColor3 = Theme.Gold,
		TextColor3 = Theme.Panel,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(0.5, -6, 0, 44),
		Parent = card,
	})

	cancel.Activated:Connect(close)
	confirm.Activated:Connect(function()
		local callback = onConfirm
		close()
		if callback ~= nil then
			callback()
		end
	end)

	gui.Parent = playerGui
end

return AscendConfirmUI
