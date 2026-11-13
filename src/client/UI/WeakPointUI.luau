--!strict
-- Draws weak points: a glowing target on the boss (or raid boss) with a ring that shrinks
-- as time runs out. Tap it before the ring closes for a burst of damage; hits in a row
-- build a streak. Lives on its own unscaled full-screen layer and follows the enemy on
-- screen every frame. It's a button, so tapping it never counts as a normal attack tap.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local WeakPointConfig = require(Shared:WaitForChild("Config"):WaitForChild("WeakPointConfig"))
local Layout = require(script.Parent.Layout)
local WeakPointController = require(Client.Controllers.WeakPointController)
local BattlefieldController = require(Client.Controllers.BattlefieldController)
local DamageNumbersController = require(Client.Controllers.DamageNumbersController)
local AudioController = require(Client.Controllers.AudioController)

type WeakPointEvent = Types.WeakPointEvent

local SIZE = if Layout.compact then 84 else 66 -- real pixels (this layer isn't scaled)
local CORE_COLOR = Color3.fromRGB(255, 70, 70)
local RING_COLOR = Color3.fromRGB(255, 215, 70)
local HIT_COLOR = Color3.fromRGB(255, 215, 70)

local WeakPointUI = {}

function WeakPointUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WeakPoints"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- screen coordinates match Camera:WorldToViewportPoint
	gui.DisplayOrder = 8 -- above the HUD and shop, below popups

	local button = Instance.new("TextButton")
	button.Name = "Target"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Size = UDim2.fromOffset(SIZE, SIZE)
	button.BackgroundColor3 = CORE_COLOR
	button.BackgroundTransparency = 0.1
	button.Text = "!"
	button.Font = Enum.Font.FredokaOne
	button.TextSize = math.floor(SIZE * 0.55)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextStrokeTransparency = 0.3
	button.AutoButtonColor = false
	button.Visible = false
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	local coreStroke = Instance.new("UIStroke")
	coreStroke.Color = Color3.new(1, 1, 1)
	coreStroke.Thickness = 3
	coreStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	coreStroke.Parent = button

	-- Countdown ring: starts big and closes in on the target.
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.Parent = button
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = RING_COLOR
	ringStroke.Thickness = 4
	ringStroke.Parent = ring

	local current: WeakPointEvent? = nil

	local function hide()
		current = nil
		button.Visible = false
	end

	WeakPointController.Spawned:Connect(function(event: WeakPointEvent)
		current = event
	end)
	WeakPointController.Cleared:Connect(hide)

	button.Activated:Connect(function()
		local event = current
		if event == nil then
			return
		end
		hide() -- right away, so it can't be tapped twice
		task.spawn(function()
			local result = WeakPointController.hit(event.id)
			if result.ok and result.damage ~= nil then
				AudioController.play("WeakPointHit")
				BattlefieldController.flinch()
				local streak = result.streak or 1
				local streakText = if streak >= 2 then `  x{streak} streak!` else ""
				DamageNumbersController.show(`WEAK POINT! {NumberFormat.big(result.damage)}{streakText}`, HIT_COLOR, 30)
			end
		end)
	end)

	RunService.RenderStepped:Connect(function()
		local event = current
		if event == nil then
			return
		end
		local remaining = event.expiresAt - workspace:GetServerTimeNow()
		local camera = workspace.CurrentCamera
		local world = BattlefieldController.getWeakPointPosition(event.x, event.y)
		if remaining <= 0 or camera == nil or world == nil then
			if remaining <= 0 then
				hide()
			end
			return
		end
		local screen, onScreen = camera:WorldToViewportPoint(world)
		if not onScreen then
			button.Visible = false
			return
		end
		button.Position = UDim2.fromOffset(screen.X, screen.Y)
		button.Visible = true
		-- Ring: 2.4x the target at the start, the target's size when time is up.
		local t = math.clamp(remaining / WeakPointConfig.WINDOW, 0, 1)
		local ringSize = SIZE * (1 + 1.4 * t)
		ring.Size = UDim2.fromOffset(ringSize, ringSize)
		-- Pulse the core a little so it catches the eye.
		button.BackgroundTransparency = 0.05 + 0.2 * (0.5 + 0.5 * math.sin(os.clock() * 12))
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return WeakPointUI
