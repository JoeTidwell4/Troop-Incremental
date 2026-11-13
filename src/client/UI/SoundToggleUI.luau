--!strict
-- Small button under the gold panel that cycles sound: All -> Music off -> Muted.

local Players = game:GetService("Players")

local Client = script.Parent.Parent
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)
local AudioController = require(Client.Controllers.AudioController)

local Theme = UIKit.Theme

local LABELS: { [string]: string } = {
	All = "Sound: ON",
	SfxOnly = "Music: OFF",
	Off = "Sound: OFF",
}

local SoundToggleUI = {}

function SoundToggleUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = UIKit.create("ScreenGui", {
		Name = "SoundToggle",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	-- Left column, first menu row (Sound | Store).
	local position, size = Layout.rowSlot(Layout.ROW1_TOP, 1, 2)
	local button = UIKit.button({
		Name = "Sound",
		Text = LABELS[AudioController.getMode()],
		TextSize = 13,
		BackgroundColor3 = Theme.PanelLight,
		Position = position,
		Size = size,
		Parent = gui,
	})
	button.Activated:Connect(function()
		button.Text = LABELS[AudioController.cycleMode()]
	end)

	gui.Parent = playerGui
end

return SoundToggleUI
