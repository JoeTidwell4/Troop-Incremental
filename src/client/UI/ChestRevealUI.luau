--!strict
-- Full-screen Wardrobe Chest opening:
--   1. the screen dims and a chest drops in,
--   2. it shakes harder and harder while the glow behind it flickers through the rarity
--      colors (teasing what's inside),
--   3. the lid bursts open: flash, spinning light rays and sparks in the rarity's color,
--   4. the item card pops up (name, rarity, bonus, NEW or duplicate refund).
-- Legendary pulls get gold rays, a second spark wave and a bigger shake. Tap anywhere to
-- skip to the result. Cosmetic only: the server already decided what you got.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local GearInfo = require(Shared:WaitForChild("GearInfo"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local CommanderConfig = require(Shared:WaitForChild("Config"):WaitForChild("CommanderConfig"))
local UIKit = require(script.Parent.UIKit)
local AudioController = require(Client.Controllers.AudioController)

type ItemDef = Types.CommanderItemDef
type ChestResult = Types.ChestResult

local Theme = UIKit.Theme
local WOOD = Color3.fromRGB(120, 75, 40)
local WOOD_DARK = Color3.fromRGB(85, 50, 25)
local TRIM = Color3.fromRGB(255, 200, 60)
local LEGENDARY = 5

local ChestRevealUI = {}

local gui: ScreenGui? = nil
local playing = false

local function corner(radius: number): UICorner
	return UIKit.create("UICorner", { CornerRadius = UDim.new(0, radius) }) :: UICorner
end

local function frame(props: { [string]: any }): Frame
	props.BorderSizePixel = 0
	return UIKit.create("Frame", props) :: Frame
end

local function tween(target: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	TweenService:Create(target, info, goal):Play()
end

local function statText(def: ItemDef): string
	if def.multiplier == nil then
		return "Looks only"
	end
	local stat = CommanderConfig.STAT_NAMES[CommanderConfig.SLOT_STATS[def.slot]] or ""
	return `+{math.floor((def.multiplier - 1) * 100 + 0.5)}% {stat}`
end

local function getGui(): ScreenGui
	if gui ~= nil then
		return gui
	end
	local newGui = UIKit.create("ScreenGui", {
		Name = "ChestReveal",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 21, -- above the Wardrobe window
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui
	newGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = newGui
	return newGui
end

-- True while an opening is on screen (don't start another purchase meanwhile).
function ChestRevealUI.isPlaying(): boolean
	return playing
end

-- Plays the opening for `def` (what the chest gave). Returns right away; the animation
-- runs on its own and removes itself when the player presses OK.
function ChestRevealUI.play(chestName: string, def: ItemDef, result: ChestResult)
	if playing then
		return
	end
	playing = true
	local rarity = GearInfo.rarity(def.rarity)
	local legendary = def.rarity >= LEGENDARY
	local color = rarity.color

	local overlay = frame({
		Name = "Overlay",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Active = true,
		Size = UDim2.fromScale(1, 1),
		Parent = getGui(),
	})
	tween(overlay, 0.25, { BackgroundTransparency = 0.35 })

	local stage = frame({
		Name = "Stage",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(320, 320),
		Parent = overlay,
	})

	-- Light rays: thin bars through the centre (each makes two rays), spinning later.
	local rays = frame({
		Name = "Rays",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(320, 320),
		Visible = false,
		Parent = stage,
	})
	local rayColor = if legendary then TRIM else color
	for i = 0, 5 do
		local ray = frame({
			BackgroundColor3 = rayColor,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(18, 340),
			Rotation = i * 30,
			Parent = rays,
		})
		UIKit.create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.25),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Rotation = 90,
			Parent = ray,
		})
	end

	-- Glow behind the chest (flickers through rarity colors while it shakes).
	local glow = frame({
		Name = "Glow",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.6,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(150, 150),
		Parent = stage,
	})
	corner(999).Parent = glow

	-- The chest: base, metal bands, lid, lock.
	local chest = frame({
		Name = "Chest",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.55, -400), -- starts above the screen, drops in
		Size = UDim2.fromOffset(170, 130),
		Parent = stage,
	})
	local base = frame({ BackgroundColor3 = WOOD, Position = UDim2.fromOffset(5, 50), Size = UDim2.fromOffset(160, 80), Parent = chest })
	corner(8).Parent = base
	UIKit.create("UIStroke", { Color = TRIM, Thickness = 3, Parent = base })
	for _, x in { 30, 115 } do
		frame({ BackgroundColor3 = WOOD_DARK, Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(14, 80), Parent = base })
	end
	local lid = frame({ BackgroundColor3 = WOOD, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(85, 54), Size = UDim2.fromOffset(170, 48), Parent = chest })
	corner(14).Parent = lid
	UIKit.create("UIStroke", { Color = TRIM, Thickness = 3, Parent = lid })
	for _, x in { 34, 122 } do
		frame({ BackgroundColor3 = WOOD_DARK, Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(14, 48), Parent = lid })
	end
	local lock = frame({ BackgroundColor3 = TRIM, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(85, 56), Size = UDim2.fromOffset(26, 30), Parent = chest })
	corner(6).Parent = lock

	local nameLabel = UIKit.label({
		Text = chestName,
		Font = Theme.FontBold,
		TextSize = 22,
		TextColor3 = TRIM,
		TextStrokeTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.fromOffset(320, 26),
		Parent = stage,
	})

	local flash = frame({
		Name = "Flash",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = overlay,
	})

	-- Result card (hidden until the chest opens).
	local card = frame({
		Name = "Card",
		BackgroundColor3 = Theme.Panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(320, 170),
		Visible = false,
		ZIndex = 5,
		Parent = overlay,
	})
	corner(14).Parent = card
	UIKit.create("UIStroke", { Color = color, Thickness = 4, Parent = card })
	local cardScale = UIKit.create("UIScale", { Scale = 0, Parent = card }) :: UIScale
	local function cardLabel(text: string, y: number, size: number, textColor: Color3, bold: boolean): TextLabel
		return UIKit.label({
			Text = text,
			Font = if bold then Theme.FontBold else Theme.Font,
			TextSize = size,
			TextColor3 = textColor,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = if bold then 0.5 else 1,
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, size + 6),
			ZIndex = 6,
			Parent = card,
		})
	end
	local rarityLabel = cardLabel(string.upper(rarity.name) .. "!", 12, 26, color, true)
	cardLabel(def.displayName, 46, 20, Theme.Text, true)
	cardLabel(`{def.slot}  |  {statText(def)}`, 74, 14, Theme.Muted, false)
	local statusText = if result.duplicate and result.refund ~= nil
		then `Already owned: +{NumberFormat.big(result.refund)} gold back`
		else `NEW! Wear it in the {def.slot} tab.`
	cardLabel(statusText, 96, 14, if result.duplicate then Theme.Muted else Theme.Good, true)
	local okButton = UIKit.button({
		Text = "OK",
		TextSize = 16,
		BackgroundColor3 = Theme.Accent,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(140, 36),
		ZIndex = 6,
		Parent = card,
	})

	-- Tap to skip: the waits below end early once `skipping` is set.
	local skipping = false
	overlay.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			skipping = true
		end
	end)
	local function wait(seconds: number)
		local untilTime = os.clock() + seconds
		while os.clock() < untilTime and not skipping do
			task.wait()
		end
	end

	-- Per-frame motion: chest shake (grows with `intensity`), ray spin, glow pulse.
	local intensity = 0
	local raySpeed = if legendary then 70 else 40
	local started = os.clock()
	local step = RunService.RenderStepped:Connect(function(dt: number)
		local t = os.clock() - started
		if intensity > 0 then
			chest.Position = UDim2.new(0.5, (math.random() - 0.5) * 2 * intensity, 0.55, (math.random() - 0.5) * intensity)
			chest.Rotation = (math.random() - 0.5) * intensity * 0.8
		end
		rays.Rotation += raySpeed * dt
		glow.Size = UDim2.fromOffset(150 + math.sin(t * 8) * 10 + intensity * 4, 150 + math.sin(t * 8) * 10 + intensity * 4)
	end)

	local function sparks(count: number, sparkColor: Color3, distance: number)
		for _ = 1, count do
			local spark = frame({
				BackgroundColor3 = sparkColor,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(10, 10),
				ZIndex = 4,
				Parent = stage,
			})
			corner(999).Parent = spark
			local angle = math.random() * math.pi * 2
			local reach = distance * (0.6 + math.random() * 0.6)
			local info = TweenInfo.new(0.7 + math.random() * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(spark, info, {
				Position = UDim2.new(0.5, math.cos(angle) * reach, 0.5, math.sin(angle) * reach),
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(4, 4),
			}):Play()
			task.delay(1.2, function()
				spark:Destroy()
			end)
		end
	end

	task.spawn(function()
		AudioController.play("PackOpen")
		-- 1. Drop in with a bounce.
		tween(chest, 0.45, { Position = UDim2.fromScale(0.5, 0.55) }, Enum.EasingStyle.Bounce)
		wait(0.55)

		-- 2. Shake harder and harder; the glow flickers through the rarities, then settles.
		local teaseColors = { GearInfo.rarity(1).color, GearInfo.rarity(3).color, GearInfo.rarity(4).color, GearInfo.rarity(5).color }
		local shakeTime = if legendary then 1.6 else 1.2
		local shakeStart = os.clock()
		local flicker = 0
		while os.clock() - shakeStart < shakeTime and not skipping do
			local progress = (os.clock() - shakeStart) / shakeTime
			intensity = 2 + progress * (if legendary then 16 else 10)
			flicker += 1
			glow.BackgroundColor3 = teaseColors[(flicker % #teaseColors) + 1]
			glow.BackgroundTransparency = 0.55 - progress * 0.25
			task.wait(0.08 + (1 - progress) * 0.07)
		end
		intensity = 0
		chest.Position = UDim2.fromScale(0.5, 0.55)
		chest.Rotation = 0

		-- 3. Burst open: flash, lid flies off, rays and sparks in the rarity color.
		AudioController.play(if def.rarity >= 3 then "PackRare" else "PackCommon")
		glow.BackgroundColor3 = color
		glow.BackgroundTransparency = 0.25
		flash.BackgroundTransparency = if legendary then 0.05 else 0.35
		tween(flash, 0.5, { BackgroundTransparency = 1 })
		tween(lid, 0.4, { Position = UDim2.fromOffset(150, -60), Rotation = 35, BackgroundTransparency = 1 })
		tween(lock, 0.3, { BackgroundTransparency = 1 })
		rays.Visible = true
		sparks(if legendary then 40 else 22, color, 170)
		if legendary then
			task.delay(0.25, function()
				sparks(30, TRIM, 220)
			end)
		end
		wait(if legendary then 0.9 else 0.6)

		-- 4. The item card pops up over the chest.
		tween(chest, 0.25, { Position = UDim2.fromScale(0.5, 0.9) })
		for _, item in chest:GetDescendants() do
			if item:IsA("Frame") then
				tween(item, 0.25, { BackgroundTransparency = 1 })
			end
		end
		nameLabel.Visible = false
		card.Visible = true
		TweenService:Create(cardScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		if legendary then
			task.delay(0.35, function()
				UIKit.bump(rarityLabel, 0.35)
			end)
		end
	end)

	okButton.Activated:Connect(function()
		step:Disconnect()
		tween(overlay, 0.2, { BackgroundTransparency = 1 })
		tween(cardScale, 0.15, { Scale = 0 })
		task.delay(0.22, function()
			overlay:Destroy()
			playing = false
		end)
	end)
end

return ChestRevealUI
