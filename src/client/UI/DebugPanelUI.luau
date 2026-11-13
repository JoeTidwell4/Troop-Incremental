--!strict
-- STUDIO ONLY test panel: a small orange "TEST" button at the top left opens buttons
-- that jump to a stage, give currency, win or lose bosses, start a new day, and so on
-- (DebugConfig; the server side is DebugService). Never built in the live game, and the
-- server ignores these requests there anyway. Studio uses its own separate saves.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local DebugConfig = require(Shared:WaitForChild("Config"):WaitForChild("DebugConfig"))
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)

local Theme = UIKit.Theme
local TEST_COLOR = Color3.fromRGB(235, 130, 40)
local DANGER_COLOR = Color3.fromRGB(200, 60, 60)

local DebugPanelUI = {}

function DebugPanelUI.start()
	if not RunService:IsStudio() then
		return
	end
	local remote = Remotes.waitForFunction(Remotes.Functions.DebugCommand)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = UIKit.create("ScreenGui", {
		Name = "DebugPanel",
		ResetOnSpawn = false,
		DisplayOrder = 30, -- above everything, so it works even with a window open
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	local toggle = UIKit.button({
		Text = "TEST",
		TextSize = 14,
		BackgroundColor3 = TEST_COLOR,
		Position = UDim2.new(0, 8, 0, 6),
		Size = UDim2.fromOffset(64, 28),
		Parent = gui,
	})

	local window = UIKit.panel({
		Visible = false,
		Position = UDim2.new(0, 8, 0, 40),
		Size = UDim2.new(0, 340, 1, -60),
		BackgroundTransparency = 0.05,
		Parent = gui,
	})
	UIKit.create("UISizeConstraint", { MaxSize = Vector2.new(340, 560), Parent = window })
	UIKit.label({
		Text = "TEST PANEL (Studio only, test saves)",
		Font = Theme.FontBold,
		TextSize = 14,
		TextColor3 = TEST_COLOR,
		Size = UDim2.new(1, 0, 0, 18),
		Parent = window,
	})
	local status = UIKit.label({
		Text = "",
		TextSize = 12,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Position = UDim2.new(0, 0, 0, 18),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = window,
	})
	local list = UIKit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 50),
		Size = UDim2.new(1, 0, 1, -50),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = window,
	}, {
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		UIKit.create("UIPadding", { PaddingRight = UDim.new(0, 8) }),
	}) :: ScrollingFrame

	local busy = false
	local function send(action: string, arg: number?)
		if busy then
			return
		end
		busy = true
		status.Text = "..."
		task.spawn(function()
			local ok, result = pcall(function(): any
				return remote:InvokeServer(action, arg)
			end)
			busy = false
			if ok and typeof(result) == "table" then
				status.Text = tostring(result.message)
				status.TextColor3 = if result.ok then Theme.Good else DANGER_COLOR
			else
				status.Text = "No answer from the server."
				status.TextColor3 = DANGER_COLOR
			end
		end)
	end

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- Stage jump: type a number, press Go.
	UIKit.label({ LayoutOrder = nextOrder(), Text = "Go to stage", Font = Theme.FontBold, TextSize = 13, Size = UDim2.new(1, 0, 0, 16), Parent = list })
	local stageRow = UIKit.create("Frame", { LayoutOrder = nextOrder(), BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), Parent = list }) :: Frame
	local stageBox = UIKit.create("TextBox", {
		Text = "",
		PlaceholderText = "e.g. 100",
		ClearTextOnFocus = false,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.Muted,
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Font = Theme.Font,
		TextSize = 14,
		Size = UDim2.new(1, -76, 1, 0),
		Parent = stageRow,
	}, { UIKit.corner(6) }) :: TextBox
	local goButton = UIKit.button({
		Text = "Go",
		TextSize = 14,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 70, 1, 0),
		Parent = stageRow,
	})
	local function goToStage()
		local stage = tonumber(stageBox.Text)
		if stage == nil then
			status.Text = "Type a stage number first."
			status.TextColor3 = DANGER_COLOR
			return
		end
		send("Stage", stage)
	end
	goButton.Activated:Connect(goToStage)
	stageBox.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			goToStage()
		end
	end)

	for _, section in DebugConfig.SECTIONS do
		UIKit.label({ LayoutOrder = nextOrder(), Text = section.title, Font = Theme.FontBold, TextSize = 13, Size = UDim2.new(1, 0, 0, 18), Parent = list })
		local grid = UIKit.create("Frame", {
			LayoutOrder = nextOrder(),
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			Parent = list,
		}, {
			UIKit.create("UIGridLayout", { CellSize = UDim2.new(0.5, -3, 0, 30), CellPadding = UDim2.fromOffset(6, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		}) :: Frame
		for index, def in section.buttons do
			local danger = def.action == "Wipe"
			local button = UIKit.button({
				LayoutOrder = index,
				Text = def.label,
				TextSize = 12,
				TextWrapped = true,
				BackgroundColor3 = if danger then DANGER_COLOR else Theme.PanelLight,
				Parent = grid,
			})
			local armed = false
			button.Activated:Connect(function()
				if danger and not armed then
					-- Wiping needs a second click within 3 seconds.
					armed = true
					button.Text = "Click again to wipe"
					task.delay(3, function()
						armed = false
						button.Text = def.label
					end)
					return
				end
				armed = false
				button.Text = def.label
				send(def.action, def.arg)
			end)
		end
	end

	toggle.Activated:Connect(function()
		window.Visible = not window.Visible
	end)

	-- The compact (phone) layout has less room: start smaller there.
	if Layout.compact then
		window.Size = UDim2.new(0, 300, 1, -50)
	end
	gui.Parent = playerGui
	print("[DebugPanel] TEST button is in the top-left corner (Studio only).")
end

return DebugPanelUI
