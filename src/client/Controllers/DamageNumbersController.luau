--!strict
-- Floating numbers above the enemy: your click damage when you click, and gold when an
-- enemy dies. Purely cosmetic (the real numbers come from the server snapshot).
-- At most a few numbers exist at once (GraphicsConfig damageNumbers: 12 on High, 6 on
-- Low) so mashing can't pile up hundreds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Controllers = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local BigNum = require(Shared:WaitForChild("BigNum"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local StateController = require(Controllers.StateController)
local InputController = require(Controllers.InputController)
local BattlefieldController = require(Controllers.BattlefieldController)
local Quality = require(script.Parent.Parent:WaitForChild("Visuals"):WaitForChild("Quality"))

type Snapshot = Types.Snapshot

local LIFETIME = 0.8
local CLICK_COLOR = Color3.fromRGB(255, 255, 255)
local GOLD_COLOR = Color3.fromRGB(255, 205, 70)

local active = 0
local anchor: Part? = nil

local DamageNumbersController = {}

local spawnText: (text: string, color: Color3, size: number) -> ()

-- Floats any text above the enemy (e.g. weak point hits).
function DamageNumbersController.show(text: string, color: Color3, size: number)
	spawnText(text, color, size)
end

spawnText = function(text: string, color: Color3, size: number)
	local enemy = BattlefieldController.getEnemyPosition()
	if enemy == nil or active >= Quality.get().damageNumbers then
		return
	end
	active += 1

	local part = anchor
	if part == nil then
		local newPart = Instance.new("Part")
		newPart.Name = "DamageNumberAnchor"
		newPart.Transparency = 1
		newPart.Anchored = true
		newPart.CanCollide = false
		newPart.CanQuery = false
		newPart.CanTouch = false
		newPart.Size = Vector3.one
		newPart.Parent = workspace
		anchor = newPart
		part = newPart
	end
	(part :: Part).Position = enemy

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 140, 0, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(math.random(-20, 20) / 10, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Adornee = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Font = Enum.Font.GothamBold
	label.TextSize = size
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = billboard
	billboard.Parent = part

	local info = TweenInfo.new(LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(billboard, info, {
		StudsOffsetWorldSpace = billboard.StudsOffsetWorldSpace + Vector3.new(0, 3, 0),
	}):Play()
	local fade = TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 })
	fade.Completed:Connect(function()
		billboard:Destroy()
		active -= 1
	end)
	fade:Play()
end

function DamageNumbersController.start()
	InputController.Tapped:Connect(function()
		local snapshot = StateController.get()
		if snapshot ~= nil then
			spawnText(NumberFormat.big(snapshot.tapDamage), CLICK_COLOR, 20)
		end
	end)
	StateController.Changed:Connect(function(snapshot: Snapshot, previous: Snapshot?)
		if previous == nil or snapshot.totalKills <= previous.totalKills then
			return
		end
		-- Gold gained since the last update (purchases can make this negative; skip those).
		if BigNum.gt(snapshot.gold, previous.gold) then
			spawnText("+" .. NumberFormat.big(BigNum.sub(snapshot.gold, previous.gold)) .. " gold", GOLD_COLOR, 24)
		end
	end)
end

return DamageNumbersController
