--!strict
-- Small button under the gold panel that cycles sound: All -> Music off -> Muted.

local Players = game:GetService("Players")

local Client = script.Parent.Parent
local UIKit = require(script.Parent.UIKit)
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

	-- Below the gold panel (12 + 134) and the Ascend button slot (6 + 34).
	local button = UIKit.button({
		Name = "Sound",
		Text = LABELS[AudioController.getMode()],
		TextSize = 12,
		BackgroundColor3 = Theme.PanelLight,
		Position = UDim2.new(0, 12, 0, 12 + 134 + 6 + 34 + 6),
		Size = UDim2.new(0, 102, 0, 26),
		Parent = gui,
	})
	button.Activated:Connect(function()
		button.Text = LABELS[AudioController.cycleMode()]
	end)

	gui.Parent = playerGui
end

return SoundToggleUI
