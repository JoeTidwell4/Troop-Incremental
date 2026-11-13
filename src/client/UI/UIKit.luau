--!strict
-- Small helpers for building UI in code, plus the shared color theme.
--   local label = UIKit.create("TextLabel", { Text = "Hi", Parent = frame }) :: TextLabel

local TweenService = game:GetService("TweenService")

local UIKit = {}

-- UI is designed for roughly this screen size; smaller screens (phones) scale it down.
local DESIGN_WIDTH = 1000
local DESIGN_HEIGHT = 620
local MIN_SCALE = 0.6

-- Hooks other modules can fill in (e.g. AudioController sets onButtonClick for click sounds).
-- This table stays writable even though UIKit itself is frozen.
UIKit.hooks = {
	onButtonClick = nil :: (() -> ())?,
}

UIKit.Theme = table.freeze({
	Panel = Color3.fromRGB(28, 30, 40),
	PanelLight = Color3.fromRGB(44, 47, 62),
	Text = Color3.fromRGB(240, 240, 245),
	Muted = Color3.fromRGB(160, 165, 185),
	Gold = Color3.fromRGB(255, 205, 70),
	Accent = Color3.fromRGB(90, 140, 255),
	Good = Color3.fromRGB(60, 170, 90),
	Disabled = Color3.fromRGB(70, 72, 85),
	HpBack = Color3.fromRGB(60, 20, 25),
	HpFill = Color3.fromRGB(220, 60, 60),
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.FredokaOne, -- chunky game-style font for titles, numbers and buttons
	PanelTransparency = 0.15,
})

-- Creates an instance and sets its properties. "Parent" is applied last, after
-- children are added, which is faster and avoids flicker.
function UIKit.create(className: string, props: { [string]: any }, children: { Instance }?): Instance
	local instance = (Instance.new :: any)(className) :: Instance
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if children ~= nil then
		for _, child in children do
			child.Parent = instance
		end
	end
	if className == "ScreenGui" then
		UIKit.autoScale(instance :: ScreenGui)
	end
	if props.Parent ~= nil then
		instance.Parent = props.Parent
	end
	return instance
end

-- Scales a whole ScreenGui down on small screens (phones), and keeps it updated if the
-- window is resized. Every ScreenGui made with UIKit.create gets this automatically.
function UIKit.autoScale(gui: ScreenGui)
	local scale = Instance.new("UIScale")
	scale.Name = "AutoScale"
	scale.Parent = gui
	local function update()
		local camera = workspace.CurrentCamera
		if camera == nil then
			return
		end
		local size = camera.ViewportSize
		scale.Scale = math.clamp(math.min(size.X / DESIGN_WIDTH, size.Y / DESIGN_HEIGHT), MIN_SCALE, 1)
	end
	update()
	if workspace.CurrentCamera ~= nil then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
end

-- Shows a full-screen popup (overlay) and makes its window pop in.
function UIKit.openModal(overlay: GuiObject, window: GuiObject)
	overlay.Visible = true
	local pop = window:FindFirstChild("PopScale") :: UIScale?
	if pop == nil then
		local newScale = Instance.new("UIScale")
		newScale.Name = "PopScale"
		newScale.Parent = window
		pop = newScale
	end
	local scale = pop :: UIScale
	scale.Scale = 0.85
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Quick "pop" on any GUI element (e.g. the gold counter when gold comes in).
function UIKit.bump(target: GuiObject, amount: number?)
	local bumpScale = target:FindFirstChild("BumpScale") :: UIScale?
	if bumpScale == nil then
		local newScale = Instance.new("UIScale")
		newScale.Name = "BumpScale"
		newScale.Parent = target
		bumpScale = newScale
	end
	local scale = bumpScale :: UIScale
	scale.Scale = 1 + (amount or 0.12)
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function UIKit.corner(radius: number): UICorner
	return UIKit.create("UICorner", { CornerRadius = UDim.new(0, radius) }) :: UICorner
end

function UIKit.padding(pixels: number): UIPadding
	local p = UDim.new(0, pixels)
	return UIKit.create("UIPadding", {
		PaddingTop = p,
		PaddingBottom = p,
		PaddingLeft = p,
		PaddingRight = p,
	}) :: UIPadding
end

-- A rounded, slightly see-through background panel.
function UIKit.panel(props: { [string]: any }): Frame
	local defaults: { [string]: any } = {
		BackgroundColor3 = UIKit.Theme.Panel,
		BackgroundTransparency = UIKit.Theme.PanelTransparency,
		BorderSizePixel = 0,
	}
	for key, value in props do
		defaults[key] = value
	end
	return UIKit.create("Frame", defaults, {
		UIKit.corner(10),
		UIKit.padding(8),
		-- Soft top-to-bottom shading and a thin light border.
		UIKit.create("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 215)),
			Rotation = 90,
		}),
		UIKit.create("UIStroke", {
			Color = Color3.fromRGB(120, 125, 150),
			Transparency = 0.55,
			Thickness = 1.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	}) :: Frame
end

-- Text with no background.
function UIKit.label(props: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		TextColor3 = UIKit.Theme.Text,
		Font = UIKit.Theme.Font,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for key, value in props do
		defaults[key] = value
	end
	return UIKit.create("TextLabel", defaults) :: TextLabel
end

function UIKit.button(props: { [string]: any }): TextButton
	local defaults: { [string]: any } = {
		BackgroundColor3 = UIKit.Theme.Accent,
		BorderSizePixel = 0,
		TextColor3 = UIKit.Theme.Text,
		Font = UIKit.Theme.FontBold,
		TextSize = 15,
		AutoButtonColor = true,
	}
	for key, value in props do
		defaults[key] = value
	end
	local pressScale = UIKit.create("UIScale", { Name = "PressScale" }) :: UIScale
	local button = UIKit.create("TextButton", defaults, {
		UIKit.corner(8),
		pressScale,
		-- Lighter at the top, like a raised button.
		UIKit.create("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 205)),
			Rotation = 90,
		}),
		UIKit.create("UIStroke", {
			Color = Color3.new(0, 0, 0),
			Transparency = 0.7,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	}) :: TextButton
	button.TextStrokeTransparency = 0.75

	-- Squish slightly while pressed.
	local pressInfo = TweenInfo.new(0.08)
	button.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			TweenService:Create(pressScale, pressInfo, { Scale = 0.94 }):Play()
		end
	end)
	button.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			TweenService:Create(pressScale, pressInfo, { Scale = 1 }):Play()
		end
	end)

	button.Activated:Connect(function()
		local hook = UIKit.hooks.onButtonClick
		if hook ~= nil then
			hook()
		end
	end)
	return button
end

return table.freeze(UIKit)
