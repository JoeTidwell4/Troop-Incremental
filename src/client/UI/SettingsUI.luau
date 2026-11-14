--!strict
-- "SETTINGS" menu button and window: graphics quality (Auto / Low / High) and sound
-- (On / Music off / Off). Saved between sessions (SettingsController). The GUIDE button
-- opens GuideUI (replay tutorial lessons). Also shows the game version, handy when
-- reporting bugs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GroupService = game:GetService("GroupService")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Version = require(Shared:WaitForChild("Version")) :: string
local Remotes = require(Shared:WaitForChild("Remotes"))
local CommunityConfig = require(Shared:WaitForChild("Config"):WaitForChild("CommunityConfig"))
local UIKit = require(script.Parent.UIKit)
local Spotlight = require(script.Parent.Spotlight)
local Layout = require(script.Parent.Layout)
local SettingsController = require(Client.Controllers.SettingsController)
local StateController = require(Client.Controllers.StateController)
local GuideUI = require(script.Parent.GuideUI)

local Theme = UIKit.Theme

type Choice = { value: string, label: string }

local GRAPHICS: { Choice } = {
	{ value = "Auto", label = "Auto" },
	{ value = "Low", label = "Low" },
	{ value = "High", label = "High" },
}
local SOUND: { Choice } = {
	{ value = "All", label = "On" },
	{ value = "SfxOnly", label = "Music off" },
	{ value = "Off", label = "Off" },
}

local ROW_HEIGHT = if Layout.compact then 44 else 36

local SettingsUI = {}

function SettingsUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = UIKit.create("ScreenGui", {
		Name = "Settings",
		ResetOnSpawn = false,
		DisplayOrder = 19,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	local menuPosition, menuSize = Layout.menuSlot("Settings")
	local menuButton = UIKit.button({
		Name = "SettingsButton",
		Text = "SETTINGS",
		TextSize = Layout.MENU_TEXT_SIZE,
		BackgroundColor3 = Theme.PanelLight,
		Position = menuPosition,
		Size = menuSize,
		Parent = gui,
	})

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
	local windowHeight = 14 + 34 + 2 * (22 + ROW_HEIGHT + 22 + 8) + 2 * (ROW_HEIGHT + 8) + 18 + 14
	local window = UIKit.create("Frame", {
		Name = "Window",
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 400, 0, windowHeight),
		Parent = overlay,
	}, {
		UIKit.corner(14),
		UIKit.padding(14),
	}) :: Frame
	UIKit.label({
		Text = "Settings",
		Font = Theme.FontBold,
		TextSize = 22,
		TextColor3 = Theme.Gold,
		Size = UDim2.new(1, -50, 0, 28),
		Parent = window,
	})
	local closeButton = UIKit.button({
		Text = "X",
		TextSize = 16,
		BackgroundColor3 = Theme.PanelLight,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(Layout.CLOSE_SIZE, Layout.CLOSE_SIZE),
		Parent = window,
	})

	local refreshers: { () -> () } = {}

	-- One setting: a title, a row of choice buttons, and a hint line under them.
	local function section(top: number, title: string, key: string, choices: { Choice }, hint: () -> string)
		UIKit.label({
			Text = title,
			Font = Theme.FontBold,
			TextSize = 16,
			Position = UDim2.new(0, 0, 0, top),
			Size = UDim2.new(1, 0, 0, 20),
			Parent = window,
		})
		local buttons: { [string]: TextButton } = {}
		local count = #choices
		for index, choice in choices do
			local button = UIKit.button({
				Text = choice.label,
				TextSize = 15,
				BackgroundColor3 = Theme.PanelLight,
				Position = UDim2.new((index - 1) / count, if index == 1 then 0 else 3, 0, top + 22),
				Size = UDim2.new(1 / count, -6, 0, ROW_HEIGHT),
				Parent = window,
			})
			button.Activated:Connect(function()
				SettingsController.set(key, choice.value)
			end)
			buttons[choice.value] = button
		end
		local hintLabel = UIKit.label({
			Text = "",
			TextColor3 = Theme.Muted,
			TextSize = 12,
			Position = UDim2.new(0, 0, 0, top + 22 + ROW_HEIGHT + 2),
			Size = UDim2.new(1, 0, 0, 18),
			Parent = window,
		})
		table.insert(refreshers, function()
			local selected = SettingsController.get(key)
			for value, button in buttons do
				button.BackgroundColor3 = if value == selected then Theme.Accent else Theme.PanelLight
			end
			hintLabel.Text = hint()
		end)
	end

	local sectionHeight = 22 + ROW_HEIGHT + 22 + 8
	section(38, "Graphics", "graphics", GRAPHICS, function(): string
		local quality = SettingsController.graphicsQuality()
		local note = if quality == "Low" then "fewer props and effects, no shadows" else "full detail"
		return `Using {quality}: {note}. Try Low if the game lags.`
	end)
	section(38 + sectionHeight, "Sound", "sound", SOUND, function(): string
		return "Sounds play once the game's audio is added."
	end)
	local guideButton = UIKit.button({
		Text = "GUIDE: replay tutorials",
		TextSize = 15,
		BackgroundColor3 = Theme.Accent,
		Position = UDim2.new(0, 0, 0, 38 + 2 * sectionHeight),
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		Parent = window,
	})
	guideButton.Activated:Connect(function()
		overlay.Visible = false
		GuideUI.open()
	end)
	Spotlight.register("Settings:Guide", guideButton)
	-- The game's Roblox group: Roblox's own join prompt, then the server re-checks.
	local groupButton = UIKit.button({
		Text = "JOIN OUR GROUP: +10% gold + free packs",
		TextSize = 14,
		BackgroundColor3 = Color3.fromRGB(200, 150, 50),
		Position = UDim2.new(0, 0, 0, 38 + 2 * sectionHeight + ROW_HEIGHT + 8),
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		Parent = window,
	})
	local checkRemote = Remotes.waitForEvent(Remotes.Events.CommunityCheck)
	local prompting = false
	groupButton.Activated:Connect(function()
		local snapshot = StateController.get()
		if prompting or (snapshot ~= nil and snapshot.groupMember) then
			return
		end
		prompting = true
		task.spawn(function()
			pcall(function()
				GroupService:PromptJoinAsync(CommunityConfig.GROUP_ID)
			end)
			prompting = false
			checkRemote:FireServer()
		end)
	end)
	table.insert(refreshers, function()
		local snapshot = StateController.get()
		local member = snapshot ~= nil and snapshot.groupMember
		groupButton.Text = if member then "Group member: +10% gold active!" else "JOIN OUR GROUP: +10% gold + free packs"
		groupButton.BackgroundColor3 = if member then Theme.PanelLight else Color3.fromRGB(200, 150, 50)
		groupButton.AutoButtonColor = not member
	end)
	Spotlight.register("Settings:Group", groupButton)
	UIKit.label({
		Text = `Version {Version}`,
		TextColor3 = Theme.Muted,
		TextSize = 11,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = window,
	})

	local function refresh()
		for _, refresher in refreshers do
			refresher()
		end
	end
	SettingsController.Changed:Connect(refresh)
	StateController.Changed:Connect(function()
		if overlay.Visible then
			refresh()
		end
	end)
	refresh()

	local function openSettings()
		refresh()
		UIKit.openModal(overlay, window)
	end
	menuButton.Activated:Connect(openSettings)
	Spotlight.register("Menu:Settings", menuButton)
	Spotlight.registerOpener("Menu:Settings", openSettings)
	closeButton.Activated:Connect(function()
		overlay.Visible = false
	end)

	gui.Parent = playerGui
end

return SettingsUI
