--!strict
-- Draws the battlefield: ground themed per area, the current enemy or boss, and a few
-- cosmetic troops. Everything here is local to this player's screen and has no effect
-- on gameplay. At most MAX_VISIBLE_PER_TYPE troops are shown per type.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Controllers = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Areas = require(Shared:WaitForChild("Areas"))
local Plots = require(Shared:WaitForChild("Plots"))
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
local ENEMY_Z = 13
local ENEMY_SIZE = 7
local BOSS_SIZE = 12
local BOSS_ATTACK_INTERVAL = 1.2
local BARRAGE_ARROWS = 14
local HURT_COLOR = Color3.fromRGB(255, 60, 60)
local RALLY_COLOR = Color3.fromRGB(255, 205, 70)

type Unit = { model: Model, body: Part, color: Color3, home: CFrame, speed: number, phase: number }

-- Center of this player's plot; set in start() from the PlotIndex the server assigns.
local origin = Vector3.zero
local folder: Folder
local troopsModel: Model
local effects: Folder
local ground: Part
local enemy: Part
local rallyHighlight: Highlight
local areaTint: ColorCorrectionEffect

local enemyBaseColor = Color3.new(1, 1, 1)
local enemyBaseSize = Vector3.one * ENEMY_SIZE
local enemyHome = CFrame.new()
local isBoss = false
-- Running enemy tweens, cancelled when the enemy changes so old values don't stick.
local enemyColorTween: Tween? = nil
local enemyMoveTween: Tween? = nil
local bossAttackTimer = 0
local unitsByType: { [string]: { Unit } } = {}
local visibleCounts: { [string]: number } = {}

local BattlefieldController = {}

local function makePart(name: string, size: Vector3, color: Color3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.CFrame = cframe
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

---------------------------------------------------------------- troops

local function buildUnit(troopId: string, home: CFrame): (Model, Part)
	local def = TroopConfig.TROOPS[troopId]
	local size = UNIT_SIZE[troopId] or Vector3.new(1.5, 3, 1.5)

	local model = Instance.new("Model")
	model.Name = troopId

	local body = makePart("Body", size, def.color, home)
	body.Parent = model
	local headSize = size.X * 0.7
	local head = makePart(
		"Head",
		Vector3.one * headSize,
		Color3.fromRGB(235, 200, 160),
		home * CFrame.new(0, size.Y / 2 + headSize / 2, 0)
	)
	head.Shape = Enum.PartType.Ball
	head.Parent = model

	model.PrimaryPart = body
	model.Parent = troopsModel
	return model, body
end

local function setVisibleCount(troopId: string, count: number)
	local wanted = math.min(count, VisualConfig.MAX_VISIBLE_PER_TYPE)
	if visibleCounts[troopId] == wanted then
		return
	end
	visibleCounts[troopId] = wanted

	for _, unit in unitsByType[troopId] or {} do
		unit.model:Destroy()
	end
	local units: { Unit } = {}

	local def = TroopConfig.TROOPS[troopId]
	local y = (UNIT_SIZE[troopId] or Vector3.new(0, 3, 0)).Y / 2 + 0.5
	for index = 1, wanted do
		local x = (index - (wanted + 1) / 2) * UNIT_SPACING
		local home = CFrame.new(origin + Vector3.new(x, y, ROW_Z[troopId] or 0))
		local model, body = buildUnit(troopId, home)
		table.insert(units, {
			model = model,
			body = body,
			color = def.color,
			home = home,
			speed = ATTACK_SPEED[troopId] or 4,
			phase = math.random() * math.pi * 2,
		})
	end
	unitsByType[troopId] = units
end

---------------------------------------------------------------- enemy

-- Cylinders in Roblox lie on their side, so stand them up.
local function shapeRotation(shape: Enum.PartType): CFrame
	if shape == Enum.PartType.Cylinder then
		return CFrame.Angles(0, 0, math.rad(90))
	end
	return CFrame.identity
end

local function setEnemyLook(shape: Enum.PartType, size: number, color: Color3)
	if enemyColorTween ~= nil then
		enemyColorTween:Cancel()
	end
	if enemyMoveTween ~= nil then
		enemyMoveTween:Cancel()
	end
	enemy.Shape = shape
	enemyBaseSize = Vector3.one * size
	enemyBaseColor = color
	enemyHome = CFrame.new(origin + Vector3.new(0, size / 2 + 0.5, ENEMY_Z)) * shapeRotation(shape)
	enemy.Size = enemyBaseSize
	enemy.Color = color
	enemy.CFrame = enemyHome
end

local function flashEnemy()
	enemy.Color = Color3.new(1, 1, 1)
	local tween = TweenService:Create(enemy, TweenInfo.new(0.15), { Color = enemyBaseColor })
	enemyColorTween = tween
	tween:Play()
end

local function popEnemy()
	enemy.Size = enemyBaseSize * 0.6
	TweenService:Create(enemy, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = enemyBaseSize,
	}):Play()
end

-- Boss lunges at the troops and they flash red.
local function bossAttack()
	local lunge = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
	local tween = TweenService:Create(enemy, lunge, { CFrame = enemyHome - Vector3.new(0, 0, 3) })
	enemyMoveTween = tween
	tween:Play()
	for _, units in unitsByType do
		for _, unit in units do
			unit.body.Color = HURT_COLOR
			TweenService:Create(unit.body, TweenInfo.new(0.35), { Color = unit.color }):Play()
		end
	end
end

---------------------------------------------------------------- effects

local function playBarrage()
	local sources: { Vector3 } = {}
	for _, units in unitsByType do
		for _, unit in units do
			table.insert(sources, unit.home.Position)
		end
	end
	if #sources == 0 then
		table.insert(sources, origin + Vector3.new(0, 3, -6))
	end
	local target = enemyHome.Position
	for i = 1, BARRAGE_ARROWS do
		task.delay(i * 0.03, function()
			local from = sources[math.random(1, #sources)] + Vector3.new(0, 2, 0)
			local to = target + Vector3.new(math.random(-20, 20) / 10, math.random(-15, 15) / 10, 0)
			local arrow = makePart("Arrow", Vector3.new(0.3, 0.3, 2.5), RALLY_COLOR, CFrame.lookAt(from, to))
			arrow.Material = Enum.Material.Neon
			arrow.Parent = effects
			local tween = TweenService:Create(arrow, TweenInfo.new(0.3, Enum.EasingStyle.Linear), {
				CFrame = CFrame.lookAt(to, to + (to - from).Unit),
			})
			tween.Completed:Connect(function()
				arrow:Destroy()
				flashEnemy()
			end)
			tween:Play()
		end)
	end
end

local function applyArea(stage: number)
	local theme = Areas.forStage(stage).theme
	ground.Color = theme.groundColor
	ground.Material = theme.groundMaterial
	Lighting.ClockTime = theme.clockTime
	areaTint.TintColor = theme.tint
end

---------------------------------------------------------------- state

local function onStateChanged(snapshot: Snapshot, previous: Snapshot?)
	for _, troopId in TroopConfig.ORDER do
		setVisibleCount(troopId, snapshot.troops[troopId] or 0)
	end

	local stageChanged = previous == nil or previous.stage ~= snapshot.stage
	local encounterChanged = previous == nil or previous.encounter ~= snapshot.encounter
	if stageChanged or encounterChanged then
		local theme = Areas.forStage(snapshot.stage).theme
		isBoss = snapshot.encounter == "Boss"
		if isBoss then
			setEnemyLook(theme.enemyShape, BOSS_SIZE, theme.bossColor)
			bossAttackTimer = 0
		else
			setEnemyLook(theme.enemyShape, ENEMY_SIZE, theme.enemyColor)
		end
		applyArea(snapshot.stage)
	end

	if previous ~= nil and snapshot.totalKills > previous.totalKills then
		popEnemy()
	end

	rallyHighlight.Enabled = snapshot.damageMultiplier > 1

	if previous ~= nil then
		local before = previous.abilities.Barrage
		local after = snapshot.abilities.Barrage
		if after ~= nil and (before == nil or after.readyAt > before.readyAt) then
			playBarrage()
		end
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

local function animate(dt: number)
	local now = os.clock()
	for _, units in unitsByType do
		for _, unit in units do
			-- Quick lunge toward the enemy, then back.
			local wave = math.max(0, math.sin(now * unit.speed + unit.phase))
			local lunge = (wave ^ 4) * LUNGE_DISTANCE
			unit.model:PivotTo(unit.home * CFrame.new(0, 0, lunge))
		end
	end

	if isBoss then
		bossAttackTimer += dt
		if bossAttackTimer >= BOSS_ATTACK_INTERVAL then
			bossAttackTimer = 0
			bossAttack()
		end
	end
end

-- Waits until the server has assigned this player a plot.
local function waitForPlot(): number
	local player = Players.LocalPlayer
	local index = player:GetAttribute(Plots.ATTRIBUTE)
	while typeof(index) ~= "number" do
		player:GetAttributeChangedSignal(Plots.ATTRIBUTE):Wait()
		index = player:GetAttribute(Plots.ATTRIBUTE)
	end
	return index :: number
end

function BattlefieldController.start()
	origin = Plots.origin(waitForPlot())

	folder = Instance.new("Folder")
	folder.Name = "Battlefield"

	troopsModel = Instance.new("Model")
	troopsModel.Name = "Troops"
	troopsModel.Parent = folder

	effects = Instance.new("Folder")
	effects.Name = "Effects"
	effects.Parent = folder

	ground = makePart("Ground", Vector3.new(70, 1, 36), Color3.fromRGB(96, 140, 80), CFrame.new(origin))
	ground.Material = Enum.Material.Grass
	ground.Parent = folder

	enemy = makePart("Enemy", enemyBaseSize, enemyBaseColor, CFrame.new())
	enemy.Parent = folder

	-- Golden glow on every troop while Rally is active (one Highlight for the whole army).
	rallyHighlight = Instance.new("Highlight")
	rallyHighlight.Adornee = troopsModel
	rallyHighlight.FillColor = RALLY_COLOR
	rallyHighlight.FillTransparency = 0.6
	rallyHighlight.OutlineColor = RALLY_COLOR
	rallyHighlight.Enabled = false
	rallyHighlight.Parent = folder

	areaTint = Instance.new("ColorCorrectionEffect")
	areaTint.Name = "AreaTint"
	areaTint.Parent = Lighting

	folder.Parent = workspace

	setupCamera()
	StateController.Changed:Connect(onStateChanged)
	InputController.Tapped:Connect(flashEnemy)
	RunService.RenderStepped:Connect(animate)
end

return BattlefieldController
