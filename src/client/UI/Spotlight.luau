--!strict
-- Points new players at the button the current starter tip is talking about: a gold
-- ring pulses around it. UI modules register their buttons by key ("Tab:Gear",
-- "Buy:Swordsman", "Ability:Rally", "FightBoss"...); HudUI picks which one to light.
-- Only one spotlight at a time.
--
-- The ring lives on its own unscaled overlay and follows the button's on-screen
-- position every frame, so buttons that clip their children (ability buttons) or sit
-- in list layouts still get a ring. It hides while the button itself is hidden (e.g.
-- the shop drawer is closed).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Spotlight = {}

local targets: { [string]: GuiObject } = {}
local openers: { [string]: () -> () } = {}
local currentKey: string? = nil
local overrideKey: string? = nil -- a tutorial lesson's target wins over HudUI's tips
local ring: Frame? = nil
local ringGui: ScreenGui? = nil

local function shownOnScreen(target: GuiObject): boolean
	local node: Instance? = target
	while node ~= nil do
		if node:IsA("GuiObject") and not (node :: GuiObject).Visible then
			return false
		elseif node:IsA("ScreenGui") then
			return (node :: ScreenGui).Enabled and node.Parent ~= nil
		end
		node = node.Parent
	end
	return false
end

local function getRing(): Frame
	if ring ~= nil then
		return ring
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "Spotlight"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 9 -- above the HUD and shop, below popup windows (tutorials lift it)
	ringGui = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "Ring"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Visible = false
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 215, 70)
	stroke.Thickness = 3
	stroke.Parent = frame

	-- Follow the target and pulse: grow a little and fade, over and over.
	RunService.RenderStepped:Connect(function()
		local key = overrideKey or currentKey
		local target = if key ~= nil then targets[key] else nil
		if target == nil or not shownOnScreen(target) then
			frame.Visible = false
			return
		end
		local t = (os.clock() * 1.6) % 1
		local grow = 8 + t * 14
		local size = target.AbsoluteSize
		frame.Position = UDim2.fromOffset(target.AbsolutePosition.X + size.X / 2, target.AbsolutePosition.Y + size.Y / 2)
		frame.Size = UDim2.fromOffset(size.X + grow, size.Y + grow)
		stroke.Transparency = t * 0.9
		frame.Visible = true
	end)
	ring = frame
	return frame
end

-- Lets HudUI point at this button later.
function Spotlight.register(key: string, target: GuiObject)
	targets[key] = target
end

-- How to open the window behind a key (e.g. "Menu:Quests", "Army:Relics", "Tab:Gear").
-- Tutorial lessons use these so they can open the right window without requiring it.
function Spotlight.registerOpener(key: string, open: () -> ())
	openers[key] = open
end

-- Opens the window registered as `key`; false if nothing is registered.
function Spotlight.open(key: string): boolean
	local open = openers[key]
	if open == nil then
		return false
	end
	open()
	return true
end

-- The button registered as `key`, if it is on screen right now.
function Spotlight.targetOf(key: string): GuiObject?
	local target = targets[key]
	if target ~= nil and shownOnScreen(target) then
		return target
	end
	return nil
end

-- The tutorial's own target: shown instead of the tip's while set (nil = back to tips).
-- While a lesson points at something the ring is drawn above popup windows too, since
-- lessons point at tabs inside windows they open.
function Spotlight.override(key: string?)
	overrideKey = key
	if key ~= nil then
		getRing()
	end
	if ringGui ~= nil then
		ringGui.DisplayOrder = if key ~= nil then 20 else 9
	end
end

-- Lights up the button registered as `key` (nil = turn the spotlight off).
function Spotlight.show(key: string?)
	if key == currentKey then
		return
	end
	currentKey = key
	if key ~= nil then
		getRing()
	end
end

return Spotlight
