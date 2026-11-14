--!strict
-- MENU: the fallback for the camp (CampController). One screen button that opens a small
-- list of every camp sign; picking one does exactly what clicking the sign does (camera
-- glide, then the window). Red dot when any sign has a "!". Handy on small screens and
-- whenever a sign is hard to reach.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)
local Spotlight = require(script.Parent.Spotlight)
local CampController = require(Client.Controllers.CampController)

local Theme = UIKit.Theme
local ROW = if Layout.compact then 44 else 38

local MenuUI = {}

function MenuUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = UIKit.create("ScreenGui", {
		Name = "Menu",
		ResetOnSpawn = false,
		DisplayOrder = 15,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	local position, size = Layout.menuSlot("Menu")
	local menuButton = UIKit.button({
		Name = "MenuButton",
		Text = "MENU",
		TextSize = Layout.MENU_TEXT_SIZE,
		BackgroundColor3 = Theme.PanelLight,
		Position = position,
		Size = size,
		Parent = gui,
	})
	Spotlight.register("Menu:Menu", menuButton)
	local dot = UIKit.create("Frame", {
		Name = "Dot",
		BackgroundColor3 = Color3.fromRGB(230, 60, 60),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(14, 14),
		Visible = false,
		ZIndex = 5,
		Parent = menuButton,
	}, { UIKit.corner(7) }) :: Frame

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
	local window = UIKit.create("Frame", {
		Name = "Window",
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(300, 60),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = overlay,
	}, { UIKit.corner(14), UIKit.padding(14) }) :: Frame
	UIKit.label({ Text = "Camp", Font = Theme.FontBold, TextSize = 22, TextColor3 = Theme.Gold, Size = UDim2.new(1, -50, 0, 28), Parent = window })
	local closeButton = UIKit.button({
		Text = "X",
		TextSize = 16,
		BackgroundColor3 = Theme.PanelLight,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(Layout.CLOSE_SIZE, Layout.CLOSE_SIZE),
		Parent = window,
	})
	local list = UIKit.create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = window,
	}, { UIKit.create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) }) :: Frame

	local function fill()
		for _, child in list:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		for index, entry in CampController.list() do
			local button = UIKit.button({
				Text = if entry.badge then `{entry.label}  (!)` else entry.label,
				TextSize = 16,
				LayoutOrder = index,
				BackgroundColor3 = if entry.badge then Color3.fromRGB(150, 70, 60) else Theme.PanelLight,
				Size = UDim2.new(1, 0, 0, ROW),
				Parent = list,
			})
			button.Activated:Connect(function()
				overlay.Visible = false
				CampController.visitKey(entry.key)
			end)
		end
	end

	menuButton.Activated:Connect(function()
		fill()
		UIKit.openModal(overlay, window)
	end)
	closeButton.Activated:Connect(function()
		overlay.Visible = false
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < 0.5 then
			return
		end
		elapsed = 0
		local any = false
		for _, entry in CampController.list() do
			any = any or entry.badge
		end
		dot.Visible = any
	end)

	gui.Parent = playerGui
end

return MenuUI
