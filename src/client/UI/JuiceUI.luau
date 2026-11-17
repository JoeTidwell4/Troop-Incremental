--!strict
-- Small "game feel" effects that don't belong to one window:
--   * a soft full-screen flash on big moments (boss kill, level up, chapter clear, Ascend)
--   * a title card that sweeps across the screen when you reach a new land
--     (skipped while a story scene plays or waits: the arrival scene introduces the land)
--   * a big floating "<TROOP> DAMAGE x2!" when a troop type reaches a damage milestone
-- Purely cosmetic; everything here reads the snapshot / notices.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Areas = require(Shared:WaitForChild("Areas"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local TroopConfig = require(Shared:WaitForChild("Config"):WaitForChild("TroopConfig"))
local UIKit = require(script.Parent.UIKit)
local StateController = require(Client.Controllers.StateController)
local DamageNumbersController = require(Client.Controllers.DamageNumbersController)
local Cinematic = require(Client.Controllers.Cinematic)
local StoryController = require(Client.Controllers.StoryController)

type Snapshot = Types.Snapshot

local Theme = UIKit.Theme
local MILESTONE_COLOR = Color3.fromRGB(255, 220, 90)

local JuiceUI = {}

local flashFrame: Frame? = nil
local cardLayer: Frame? = nil
local cardPlaying = false

-- A quick full-screen flash that fades out.
function JuiceUI.flash(color: Color3, strength: number?, seconds: number?)
	local frame = flashFrame
	if frame == nil then
		return
	end
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 1 - (strength or 0.3)
	TweenService:Create(frame, TweenInfo.new(seconds or 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

-- "AREA 3 / Scorched Desert / trait" sweeps in from the left, holds, leaves to the right.
local function titleCard(snapshot: Snapshot)
	local layer = cardLayer
	if layer == nil or cardPlaying then
		return
	end
	cardPlaying = true
	local area = Areas.forStage(snapshot.stage)
	local trait = area.theme.trait
	local card = UIKit.create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(-0.5, 0, 0.3, 0),
		Size = UDim2.new(0, 520, 0, 110),
		Parent = layer,
	}) :: Frame
	-- Dark band behind the text, fading out at both ends.
	UIKit.create("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = card,
	}, {
		UIKit.create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0),
				NumberSequenceKeypoint.new(0.8, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	UIKit.label({
		Text = `AREA {area.number}`,
		Font = Theme.FontBold,
		TextSize = 16,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 8),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = card,
	})
	local name = UIKit.label({
		Text = string.upper(area.displayName),
		Font = Theme.FontBold,
		TextSize = 40,
		TextColor3 = Theme.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 28),
		Size = UDim2.new(1, 0, 0, 46),
		Parent = card,
	})
	name.TextStrokeTransparency = 0.2
	-- Gold rule under the name that grows out from the middle.
	local rule = UIKit.create("Frame", {
		BackgroundColor3 = Theme.Gold,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 76),
		Size = UDim2.new(0, 0, 0, 2),
		Parent = card,
	}) :: Frame
	local troopName = if trait ~= nil and TroopConfig.TROOPS[trait.troopId] ~= nil then TroopConfig.TROOPS[trait.troopId].displayName else nil
	UIKit.label({
		Text = if trait ~= nil and troopName ~= nil
			then `{trait.name}: {troopName}s deal -{math.floor((1 - trait.damageMultiplier) * 100 + 0.5)}% here`
			else "",
		TextSize = 14,
		TextColor3 = Color3.fromRGB(255, 150, 140),
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 82),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = card,
	})

	local slideIn = TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0.3, 0) })
	slideIn:Play()
	TweenService:Create(rule, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.3), { Size = UDim2.new(0.6, 0, 0, 2) }):Play()
	task.delay(2.4, function()
		local slideOut = TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(1.5, 0, 0.3, 0) })
		slideOut.Completed:Connect(function()
			card:Destroy()
			cardPlaying = false
		end)
		slideOut:Play()
	end)
end

local function onChanged(snapshot: Snapshot, previous: Snapshot?)
	if previous == nil then
		return
	end
	-- A new land (only going forward, and not in a raid / Tower floor / the final battle).
	if snapshot.encounter ~= "Raid" and snapshot.towerFloor == 0 and not snapshot.finalBattle then
		local before = Areas.numberForStage(previous.stage)
		local now = Areas.numberForStage(snapshot.stage)
		if now > before and snapshot.ascensions == previous.ascensions then
			-- Give a story arrival scene the chance to queue first.
			task.delay(0.4, function()
				if not Cinematic.active and not StoryController.busy() then
					titleCard(snapshot)
				end
			end)
		end
	end
	-- Damage milestones (x2 each).
	for _, troopId in TroopConfig.ORDER do
		local was, count = previous.troops[troopId] or 0, snapshot.troops[troopId] or 0
		if count > was and was > 0 and Formulas.milestonesReached(count) > Formulas.milestonesReached(was) then
			local def = TroopConfig.TROOPS[troopId]
			DamageNumbersController.show(`{string.upper(def.displayName)} DAMAGE x{TroopConfig.MILESTONE_MULTIPLIER}!`, MILESTONE_COLOR, 34)
		end
	end
	if snapshot.ascensions > previous.ascensions then
		JuiceUI.flash(Theme.Gold, 0.55, 0.8)
	end
end

function JuiceUI.start()
	local gui = UIKit.create("ScreenGui", {
		Name = "Juice",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 19, -- above windows, below tutorial cards / chest reveals
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui
	flashFrame = UIKit.create("Frame", {
		Name = "Flash",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = gui,
	}) :: Frame
	cardLayer = UIKit.create("Frame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = gui,
	}) :: Frame

	StateController.Changed:Connect(onChanged)
	StateController.Notice:Connect(function(notice: Types.Notice)
		if notice.kind == "BossDefeated" then
			JuiceUI.flash(Color3.fromRGB(255, 235, 170), 0.35)
		elseif notice.kind == "LevelUp" or notice.kind == "StoryChapter" then
			JuiceUI.flash(Theme.Gold, 0.3, 0.6)
		end
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return JuiceUI
