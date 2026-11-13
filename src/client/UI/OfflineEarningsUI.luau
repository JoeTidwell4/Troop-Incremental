--!strict
-- "Welcome back!" popup showing what your army earned while you were away.
-- The gold was already added by the server; this is just the message.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local UIKit = require(script.Parent.UIKit)
local StateController = require(Client.Controllers.StateController)

type Notice = Types.Notice

local Theme = UIKit.Theme

local OfflineEarningsUI = {}

-- 11520 -> "3h 12m", 300 -> "5m"
local function duration(seconds: number): string
	local totalMinutes = math.floor(seconds / 60)
	local hours = totalMinutes // 60
	local minutes = totalMinutes % 60
	if hours <= 0 then
		return `{minutes}m`
	end
	return `{hours}h {minutes}m`
end

function OfflineEarningsUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = UIKit.create("ScreenGui", {
		Name = "OfflineEarnings",
		ResetOnSpawn = false,
		DisplayOrder = 22,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	local overlay = UIKit.create("Frame", {
		Name = "Overlay",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Active = true,
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
		Size = UDim2.new(0, 380, 0, 230),
		Parent = overlay,
	}, { UIKit.corner(14), UIKit.padding(16) }) :: Frame
	UIKit.create("UIStroke", { Color = Theme.Gold, Thickness = 3, Parent = card })

	UIKit.label({
		Text = "Welcome back, Commander!",
		Font = Theme.FontBold,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 28),
		Parent = card,
	})
	local awayLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = card,
	})
	local goldLabel = UIKit.label({
		Text = "",
		Font = Theme.FontBold,
		TextSize = 30,
		TextColor3 = Theme.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 60),
		Size = UDim2.new(1, 0, 0, 36),
		Parent = card,
	})
	local detailLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 13,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 100),
		Size = UDim2.new(1, 0, 0, 36),
		Parent = card,
	})
	local collect = UIKit.button({
		Name = "Collect",
		Text = "Collect",
		TextSize = 18,
		BackgroundColor3 = Theme.Good,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0.6, 0, 0, 44),
		Parent = card,
	})
	collect.Activated:Connect(function()
		overlay.Visible = false
	end)

	StateController.Notice:Connect(function(notice: Notice)
		if notice.kind ~= "OfflineEarnings" or notice.gold == nil then
			return
		end
		local away = notice.awaySeconds or 0
		local counted = notice.seconds or 0
		awayLabel.Text = `You were away for {duration(away)}.`
		goldLabel.Text = `+{NumberFormat.big(notice.gold)} gold`
		local capped = if counted < away then ` (capped at {duration(counted)})` else ""
		detailLabel.Text = `Your army kept fighting on stage {notice.stage}{capped}.`
		overlay.Visible = true
	end)

	gui.Parent = playerGui
end

return OfflineEarningsUI
