--!strict
-- Draws the battlefield: ground, the current enemy, and a few cosmetic troops.
-- Everything here is local to this player's screen and has no effect on gameplay.
-- No matter how many troops you own, at most MAX_VISIBLE_PER_TYPE are shown per type.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Controllers = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Config = Shared:WaitForChild("Config")
local TroopConfig = require(Config:WaitForChild("TroopConfig"))
local VisualConfig = require(Config:WaitForChild("VisualConfig"))
local StateController = require(Controllers.StateController)
local InputController = require(Controllers.InputController)

type Snapshot = Types.Snapshot

-- How far forward (toward the enemy) each troop row stands, and how they look.
local ROW_Z: { [string]: number } = { Swordsman = 4, Knight = 0, Archer = -4 }
local UNIT_SIZE: { [string]: Vector3 } = {
	Swordsman = Vector3.new(1.6, 3, 1.6),
	Archer = Vector3.new(1.3, 3, 1.3),
	Knight = Vector3.new(2.2, 3.6, 2.2),
}
local ATTACK_SPEED: { [string]: number } = { Swordsman = 6, Archer = 3, Knight = 4 }
local UNIT_SPACING = 3
local LUNGE_DISTANCE = 1.2
local ENEMY_SIZE = Vector3.new(7, 7, 7)

type Unit = { model: Model, home: CFrame, speed: number, phase: number }

local origin = VisualConfig.BATTLEFIELD_ORIGIN
local folder: Folder
local enemy: Part
local enemyBaseColor = Color3.new(1, 1, 1)
local unitsByType: { [string]: { Unit } } = {}
local visibleCounts: { [string]: number } = {}

local BattlefieldController = {}

local function makePart(props: { Name: string, Size: Vector3, Color: Color3, CFrame: CFrame }): Part
	local part = Instance.new("Part")
	part.Name = props.Name
	part.Size = props.Size
	part.Color = props.Color
	part.CFrame = props.CFrame
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function buildUnit(troopId: string, home: CFrame): Model
	local def = TroopConfig.TROOPS[troopId]
	local size = UNIT_SIZE[troopId] or Vector3.new(1.5, 3, 1.5)

	local model = Instance.new("Model")
	model.Name = troopId

	local body = makePart({ Name = "Body", Size = size, Color = def.color, CFrame = home })
	body.Parent = model
	local head = makePart({
		Name = "Head",
		Size = Vector3.new(size.X * 0.7, size.X * 0.7, size.X * 0.7),
		Color = Color3.fromRGB(235, 200, 160),
		CFrame = home * CFrame.new(0, size.Y / 2 + size.X * 0.35, 0),
	})
	head.Shape = Enum.PartType.Ball
	head.Parent = model

	model.PrimaryPart = body
	model.Parent = folder
	return model
end

local function setVisibleCount(troopId: string, count: number)
	local wanted = math.min(count, VisualConfig.MAX_VISIBLE_PER_TYPE)
	if visibleCounts[troopId] == wanted then
		return
	end
	visibleCounts[troopId] = wanted

	local units = unitsByType[troopId] or {}
	for _, unit in units do
		unit.model:Destroy()
	end
	units = {}

	local y = (UNIT_SIZE[troopId] or Vector3.new(0, 3, 0)).Y / 2 + 0.5
	for index = 1, wanted do
		local x = (index - (wanted + 1) / 2) * UNIT_SPACING
		local home = CFrame.new(origin + Vector3.new(x, y, ROW_Z[troopId] or 0))
		table.insert(units, {
			model = buildUnit(troopId, home),
			home = home,
			speed = ATTACK_SPEED[troopId] or 4,
			phase = math.random() * math.pi * 2,
		})
	end
	unitsByType[troopId] = units
end

local function stageColor(stage: number): Color3
	return Color3.fromHSV((stage * 0.137) % 1, 0.55, 0.85)
end

local function flashEnemy()
	enemy.Color = Color3.new(1, 1, 1)
	TweenService:Create(enemy, TweenInfo.new(0.15), { Color = enemyBaseColor }):Play()
end

local function popEnemy()
	enemy.Size = ENEMY_SIZE * 0.6
	TweenService:Create(enemy, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = ENEMY_SIZE,
	}):Play()
end

local function onStateChanged(snapshot: Snapshot, previous: Snapshot?)
	for _, troopId in TroopConfig.ORDER do
		setVisibleCount(troopId, snapshot.troops[troopId] or 0)
	end

	if previous == nil or previous.stage ~= snapshot.stage then
		enemyBaseColor = stageColor(snapshot.stage)
		enemy.Color = enemyBaseColor
	end
	if previous ~= nil and snapshot.totalKills > previous.totalKills then
		popEnemy()
	end
end

local function setupCamera()
	local camera = workspace.CurrentCamera
	local cameraCFrame = CFrame.lookAt(origin + VisualConfig.CAMERA_OFFSET, origin + VisualConfig.CAMERA_LOOK_OFFSET)
	local function apply()
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = cameraCFrame
	end
	apply()
	-- Roblox's default camera scripts can reset this on load; put it back if they do.
	camera:GetPropertyChangedSignal("CameraType"):Connect(function()
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			apply()
		end
	end)
end

local function animate()
	local now = os.clock()
	for _, units in unitsByType do
		for _, unit in units do
			-- Quick lunge toward the enemy, then back.
			local wave = math.max(0, math.sin(now * unit.speed + unit.phase))
			local lunge = (wave ^ 4) * LUNGE_DISTANCE
			unit.model:PivotTo(unit.home * CFrame.new(0, 0, lunge))
		end
	end
end

function BattlefieldController.start()
	folder = Instance.new("Folder")
	folder.Name = "Battlefield"

	local ground = makePart({
		Name = "Ground",
		Size = Vector3.new(70, 1, 36),
		Color = Color3.fromRGB(96, 140, 80),
		CFrame = CFrame.new(origin),
	})
	ground.Material = Enum.Material.Grass
	ground.Parent = folder

	enemy = makePart({
		Name = "Enemy",
		Size = ENEMY_SIZE,
		Color = enemyBaseColor,
		CFrame = CFrame.new(origin + Vector3.new(0, ENEMY_SIZE.Y / 2 + 0.5, 13)),
	})
	enemy.Parent = folder

	folder.Parent = workspace

	setupCamera()
	StateController.Changed:Connect(onStateChanged)
	InputController.Tapped:Connect(flashEnemy)
	RunService.RenderStepped:Connect(animate)
end

return BattlefieldController
