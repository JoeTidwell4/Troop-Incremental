--!strict
-- Full-screen loading cover shown from the moment the client starts until the first
-- snapshot (your save) arrives, so players never see empty panels and blank buttons.
-- If it takes a while (usually the save system waiting for your last server to let go
-- of your save), it says so instead of looking frozen. Built from plain instances so it
-- shows up before the rest of the UI loads.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local StateController = require(Client.Controllers.StateController)

local SLOW_AFTER = 8 -- seconds before the "taking a while" message
local BACKGROUND = Color3.fromRGB(22, 24, 34)
local GOLD = Color3.fromRGB(255, 205, 70)
local MUTED = Color3.fromRGB(160, 165, 185)

local LoadingUI = {}

local function label(parent: Instance, text: string, font: Enum.Font, size: number, color: Color3, y: number): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	item.Position = UDim2.new(0.5, 0, 0.5, y)
	item.Size = UDim2.new(0.9, 0, 0, size + 10)
	item.Font = font
	item.TextSize = size
	item.TextColor3 = color
	item.TextWrapped = true
	item.Text = text
	item.Parent = parent
	return item
end

function LoadingUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Loading"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100 -- above everything

	local cover = Instance.new("Frame")
	cover.Name = "Cover"
	cover.BackgroundColor3 = BACKGROUND
	cover.BorderSizePixel = 0
	cover.Active = true -- swallows taps so they don't attack while loading
	cover.Size = UDim2.fromScale(1, 1)
	cover.Parent = gui

	local title = label(cover, "TROOP INCREMENTAL", Enum.Font.FredokaOne, 44, GOLD, -50)
	local status = label(cover, "Loading your army", Enum.Font.GothamMedium, 20, Color3.new(1, 1, 1), 10)
	local hint = label(cover, "", Enum.Font.GothamMedium, 15, MUTED, 50)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local started = os.clock()
	local done = false
	local stepConnection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - started
		status.Text = "Loading your army" .. string.rep(".", 1 + math.floor(elapsed * 2) % 3)
		if elapsed > SLOW_AFTER then
			hint.Text = "Still loading your save. This can take a little longer if you just left another game."
		end
	end)

	local function finish()
		if done then
			return
		end
		done = true
		stepConnection:Disconnect()
		local fade = TweenInfo.new(0.35)
		for _, item in { title, status, hint } do
			TweenService:Create(item, fade, { TextTransparency = 1 }):Play()
		end
		local tween = TweenService:Create(cover, fade, { BackgroundTransparency = 1 })
		tween.Completed:Connect(function()
			gui:Destroy()
		end)
		tween:Play()
	end

	if StateController.get() ~= nil then
		finish()
	else
		StateController.Changed:Connect(function()
			-- One more frame so the world and panels get built under the cover first.
			task.defer(finish)
		end)
	end
end

return LoadingUI
