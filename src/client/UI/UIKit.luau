--!strict
-- Small helpers for building UI in code, plus the shared color theme.
--   local label = UIKit.create("TextLabel", { Text = "Hi", Parent = frame }) :: TextLabel

local UIKit = {}

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
	FontBold = Enum.Font.GothamBold,
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
	if props.Parent ~= nil then
		instance.Parent = props.Parent
	end
	return instance
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
	return UIKit.create("Frame", defaults, { UIKit.corner(10), UIKit.padding(8) }) :: Frame
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
	local button = UIKit.create("TextButton", defaults, { UIKit.corner(8) }) :: TextButton
	button.Activated:Connect(function()
		local hook = UIKit.hooks.onButtonClick
		if hook ~= nil then
			hook()
		end
	end)
	return button
end

return table.freeze(UIKit)
