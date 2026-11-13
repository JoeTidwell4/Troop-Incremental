--!strict
-- Draws the battlefield on this player's screen: the themed world around it
-- (Visuals/Environment), your troops (Visuals/TroopModels), the current enemy or boss
-- (Visuals/EnemyModels), and battle effects (Visuals/Effects). Everything here is local
-- and cosmetic; the real fight is simulated on the server.
--
-- At most MAX_VISIBLE_PER_TYPE troops are shown per type, however many you own.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local Controllers = script.Parent
local Visuals = Client:WaitForChild("Visuals")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local BigNum = require(Shared:WaitForChild("BigNum"))
local Areas = require(Shared:WaitForChild("Areas"))
local Plots = require(Shared:WaitForChild("Plots"))
local Config = Shared:WaitForChild("Config")
local TroopConfig = require(Config:WaitForChild("TroopConfig"))
local VisualConfig = require(Config:WaitForChild("VisualConfig"))
local RaidConfig = require(Config:WaitForChild("RaidConfig"))
local Environment = require(Visuals:WaitForChild("Environment"))
local TroopModels = require(Visuals:WaitForChild("TroopModels"))
local EnemyModels = require(Visuals:WaitForChild("EnemyModels"))
local Effects = require(Visuals:WaitForChild("Effects"))
local StateController = require(Controllers.StateController)
local InputController = require(Controllers.InputController)

type Snapshot = Types.Snapshot

-- Troop rows (distance toward the enemy) and how they attack.
local ROW_Z: { [string]: number } = { Cavalry = 8, Swordsman = 4, Knight = 0, Archer = -4, Mage = -7.5, Siege = -12 }
local ATTACK_SPEED: { [string]: number } = { Swordsman = 6, Archer = 3, Knight = 4, Mage = 2, Cavalry = 5, Siege = 1 }
-- Fewer of the big units on screen, spaced further apart.
local MAX_VISIBLE: { [string]: number } = { Mage = 6, Cavalry = 4, Siege = 2 }
local SPACING: { [string]: number } = { Cavalry = 4.5, Siege = 8 }

-- Ranged troops: what they shoot and how often (seconds, random between min and max).
type RangedStyle = { kind: "Arrow" | "Orb" | "Boulder", color: Color3, interval: NumberRange, from: Vector3 }
local RANGED: { [string]: RangedStyle } = {
	Archer = { kind = "Arrow", color = Color3.fromRGB(255, 220, 120), interval = NumberRange.new(1.2, 2.2), from = Vector3.new(-0.9, 2, 1) },
	Mage = { kind = "Orb", color = Color3.fromRGB(190, 140, 255), interval = NumberRange.new(1.5, 2.5), from = Vector3.new(0.9, 3.8, 0.3) },
	Siege = { kind = "Boulder", color = Color3.fromRGB(110, 105, 100), interval = NumberRange.new(3, 4.5), from = Vector3.new(0, 5.2, -2.6) },
}
local UNIT_SPACING = 3
local LUNGE_DISTANCE = 1.2
local ARENA_TOP = 0.5

local ENEMY_Z = 14
local ENEMY_SCALE = 1.25
local BOSS_SCALE = 2
local RAID_SCALE = 2.3
local BOSS_ATTACK_INTERVAL = 1.2
local POP_SECONDS = 0.25
local SHATTER_COOLDOWN = 0.25
local BARRAGE_ARROWS = 14

local HURT_COLOR = Color3.fromRGB(255, 60, 60)
local RALLY_COLOR = Color3.fromRGB(255, 205, 70)

type Unit = {
	troopId: string,
	model: Model,
	home: CFrame,
	speed: number,
	phase: number,
	nextShot: number, -- archers: when they fire their next arrow
	lastShot: number, -- archers: when they last fired (for the recoil)
}

local origin = Vector3.zero
local folder: Folder
local troopsModel: Model
local environment: Model? = nil
local currentArea = -1

local enemyModel: Model? = nil
local enemyKey = ""
local enemyHome = CFrame.new()
local enemyHeight = 6
local enemyScale = 1
local enemyFloats = false
local popStartedAt = -math.huge
local lastShatter = 0
local lungeStartedAt = -math.huge

local enemyHighlight: Highlight
local enrageHighlight: Highlight
local shieldBubble: Part? = nil
local minionModels: { Model } = {}
local minionKind = ""
local rallyHighlight: Highlight
local hurtHighlight: Highlight
local rallyAura: ParticleEmitter

local isBoss = false
local bossAttackTimer = 0
local shake = 0
local cameraBase = CFrame.new()

local unitsByType: { [string]: { Unit } } = {}
local visibleCounts: { [string]: number } = {}
local lastGear: Types.GearSet? = nil

local BattlefieldController = {}

-- Defined further down; declared here so the state handler can call them.
local updateShield: (on: boolean) -> ()
local updateMinions: (on: boolean, kind: string, color: Color3) -> ()

---------------------------------------------------------------- troops

local function setVisibleCount(troopId: string, count: number, gear: Types.GearSet?)
	local wanted = math.min(count, MAX_VISIBLE[troopId] or VisualConfig.MAX_VISIBLE_PER_TYPE)
	if visibleCounts[troopId] == wanted then
		return
	end
	visibleCounts[troopId] = wanted

	for _, unit in unitsByType[troopId] or {} do
		unit.model:Destroy()
	end
	local units: { Unit } = {}
	local def = TroopConfig.TROOPS[troopId]
	for index = 1, wanted do
		local x = (index - (wanted + 1) / 2) * (SPACING[troopId] or UNIT_SPACING)
		local home = CFrame.new(origin + Vector3.new(x, ARENA_TOP, ROW_Z[troopId] or 0))
		local model = TroopModels.build(troopId, def.color, home, troopsModel)
		TroopModels.applyGear(model, if gear ~= nil then gear[troopId] else nil)
		table.insert(units, {
			troopId = troopId,
			model = model,
			home = home,
			speed = ATTACK_SPEED[troopId] or 4,
			phase = math.random() * math.pi * 2,
			nextShot = os.clock() + math.random() * 2,
			lastShot = -math.huge,
		})
	end
	unitsByType[troopId] = units
end

local function applyGear(gear: Types.GearSet)
	for troopId, units in unitsByType do
		for _, unit in units do
			TroopModels.applyGear(unit.model, gear[troopId])
		end
	end
end

local function gearChanged(a: Types.GearSet?, b: Types.GearSet): boolean
	if a == nil then
		return true
	end
	for troopId, troopGear in b do
		local before = a[troopId]
		if before == nil or before.weapon.rarity ~= troopGear.weapon.rarity or before.armor.rarity ~= troopGear.armor.rarity then
			return true
		end
	end
	return false
end

---------------------------------------------------------------- enemy

-- Top of the current enemy, for floating numbers. Nil before the battlefield exists.
function BattlefieldController.getEnemyPosition(): Vector3?
	if enemyModel == nil then
		return nil
	end
	return enemyHome.Position + Vector3.new(0, enemyHeight, 0)
end

local function enemyCenter(): Vector3
	return enemyHome.Position + Vector3.new(0, enemyHeight * 0.55, 0)
end

-- A see-through glowing bubble around the boss while its shield is up.
updateShield = function(on: boolean)
	if on and shieldBubble == nil and enemyModel ~= nil then
		local bubble = Instance.new("Part")
		bubble.Name = "ShieldBubble"
		bubble.Shape = Enum.PartType.Ball
		bubble.Size = Vector3.one * (enemyHeight * 1.5)
		bubble.CFrame = CFrame.new(enemyCenter())
		bubble.Material = Enum.Material.ForceField
		bubble.Color = Color3.fromRGB(120, 190, 255)
		bubble.Transparency = 0.2
		bubble.Anchored = true
		bubble.CanCollide = false
		bubble.CanQuery = false
		bubble.CanTouch = false
		bubble.CastShadow = false
		bubble.Parent = folder
		shieldBubble = bubble
	elseif not on and shieldBubble ~= nil then
		shieldBubble:Destroy()
		shieldBubble = nil
	end
end

-- Small copies of the area's creature next to the boss while its minions are alive.
updateMinions = function(on: boolean, kind: string, color: Color3)
	if on and (#minionModels == 0 or minionKind ~= kind) then
		for _, minion in minionModels do
			minion:Destroy()
		end
		minionModels = {}
		minionKind = kind
		-- Two minions flanking the boss (kept clear of the Cavalry row in front).
		for _, side in { -1, 1 } do
			local offset = Vector3.new(side * 9, ARENA_TOP, ENEMY_Z - 2)
			local minion = EnemyModels.build(kind, color, 0.7, false, CFrame.new(origin + offset), folder)
			table.insert(minionModels, minion)
		end
	elseif not on and #minionModels > 0 then
		for _, minion in minionModels do
			Effects.shatter(minion, 6)
			minion:Destroy()
		end
		minionModels = {}
	end
end

local function setEnemy(kind: string, color: Color3, scale: number, crowned: boolean)
	local key = `{kind}:{color:ToHex()}:{scale}:{crowned}`
	if key == enemyKey and enemyModel ~= nil then
		return
	end
	enemyKey = key
	if enemyModel ~= nil then
		enemyModel:Destroy()
	end
	enemyHome = CFrame.new(origin + Vector3.new(0, ARENA_TOP, ENEMY_Z))
	local model, height = EnemyModels.build(kind, color, scale, crowned, enemyHome, folder)
	enemyModel = model
	enemyHeight = height
	enemyScale = scale
	enemyFloats = kind == "Wraith"
	enemyHighlight.Adornee = model
	enrageHighlight.Adornee = model
	popStartedAt = os.clock()
end

local function flashEnemy()
	enemyHighlight.FillTransparency = 0.35
	TweenService:Create(enemyHighlight, TweenInfo.new(0.15), { FillTransparency = 1 }):Play()
end

local function onTap()
	flashEnemy()
	Effects.hitSparks(enemyCenter() + Vector3.new(math.random(-10, 10) / 10, math.random(-10, 10) / 10, -1.5))
end

local function onKill()
	local now = os.clock()
	Effects.coinBurst(enemyCenter())
	if now - lastShatter >= SHATTER_COOLDOWN and enemyModel ~= nil then
		lastShatter = now
		Effects.shatter(enemyModel, 14)
	end
	popStartedAt = now -- the next enemy grows in
end

-- Boss slams the ground: lunges, troops flash red, camera shakes, dust flies.
local function bossAttack()
	lungeStartedAt = os.clock()
	hurtHighlight.FillTransparency = 0.4
	TweenService:Create(hurtHighlight, TweenInfo.new(0.35), { FillTransparency = 1 }):Play()
	shake = 0.6
	task.delay(0.12, function()
		Effects.dustRing(enemyHome.Position + Vector3.new(0, 0.5, -3))
	end)
end

---------------------------------------------------------------- abilities

local function playBarrage()
	local sources: { Vector3 } = {}
	for _, units in unitsByType do
		for _, unit in units do
			table.insert(sources, unit.home.Position + Vector3.new(0, 2.5, 0))
		end
	end
	if #sources == 0 then
		table.insert(sources, origin + Vector3.new(0, 3, -6))
	end
	for i = 1, BARRAGE_ARROWS do
		task.delay(i * 0.03, function()
			local from = sources[math.random(1, #sources)]
			local to = enemyCenter() + Vector3.new(math.random(-20, 20) / 10, math.random(-15, 15) / 10, 0)
			Effects.arrow(from, to, RALLY_COLOR, 0.35, flashEnemy)
		end)
	end
end

---------------------------------------------------------------- state

local function onStateChanged(snapshot: Snapshot, previous: Snapshot?)
	for _, troopId in TroopConfig.ORDER do
		setVisibleCount(troopId, snapshot.troops[troopId] or 0, snapshot.gear)
	end
	if gearChanged(lastGear, snapshot.gear) then
		applyGear(snapshot.gear)
	end
	lastGear = snapshot.gear

	local area = Areas.forStage(snapshot.stage)
	if area.number ~= currentArea then
		currentArea = area.number
		if environment ~= nil then
			environment:Destroy()
		end
		environment = Environment.build(area.theme, origin, area.number, folder)
		Environment.applyLighting(area.theme)
	end

	isBoss = snapshot.encounter == "Boss"
	if snapshot.encounter == "Raid" then
		setEnemy("Colossus", RaidConfig.BOSS_COLOR, RAID_SCALE, false)
	elseif isBoss then
		setEnemy(area.theme.enemyKind, area.theme.bossColor, BOSS_SCALE, true)
	else
		setEnemy(area.theme.enemyKind, area.theme.enemyColor, ENEMY_SCALE, false)
	end
	if previous ~= nil and previous.encounter ~= snapshot.encounter then
		bossAttackTimer = 0
	end

	if previous ~= nil and snapshot.totalKills > previous.totalKills then
		onKill()
	end

	local rallying = snapshot.damageMultiplier > 1
	rallyHighlight.Enabled = rallying
	rallyAura.Enabled = rallying

	-- Boss moves: shield bubble, red enrage glow, summoned minions.
	local serverNow = workspace:GetServerTimeNow()
	local shielded = snapshot.encounter == "Boss" and serverNow < snapshot.bossShieldUntil
	updateShield(shielded)
	enrageHighlight.Enabled = snapshot.encounter == "Boss" and snapshot.bossEnraged
	local minionsUp = snapshot.encounter == "Boss" and not BigNum.isZero(snapshot.minionHp)
	updateMinions(minionsUp, area.theme.enemyKind, area.theme.enemyColor)

	if previous ~= nil then
		local before = previous.abilities.Barrage
		local after = snapshot.abilities.Barrage
		if after ~= nil and (before == nil or after.readyAt > before.readyAt) then
			playBarrage()
		end
	end
end

---------------------------------------------------------------- camera + animation

local function setupCamera()
	local camera = workspace.CurrentCamera
	cameraBase = CFrame.lookAt(origin + VisualConfig.CAMERA_OFFSET, origin + VisualConfig.CAMERA_LOOK_OFFSET)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = cameraBase
	-- Roblox's default camera scripts can reset this on load; put it back if they do.
	camera:GetPropertyChangedSignal("CameraType"):Connect(function()
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
	end)
end

local function animate(dt: number)
	local now = os.clock()

	-- Troops: melee units lunge, archers hold position and loose arrows.
	for _, units in unitsByType do
		for _, unit in units do
			local ranged = RANGED[unit.troopId]
			if ranged ~= nil then
				local recoil = math.max(0, 1 - (now - unit.lastShot) * 6) * 0.3
				unit.model:PivotTo(unit.home * CFrame.new(0, 0, -recoil))
				if now >= unit.nextShot then
					unit.lastShot = now
					unit.nextShot = now + math.random() * (ranged.interval.Max - ranged.interval.Min) + ranged.interval.Min
					if enemyModel ~= nil then
						local from = unit.home.Position + ranged.from
						if ranged.kind == "Arrow" then
							Effects.arrow(from, enemyCenter(), ranged.color, 0.45, nil)
						elseif ranged.kind == "Orb" then
							Effects.orb(from, enemyCenter(), ranged.color, 0.7, 0.5, true, flashEnemy)
						else
							Effects.orb(from, enemyCenter(), ranged.color, 1.4, 0.9, false, flashEnemy)
						end
					end
				end
			else
				local wave = math.max(0, math.sin(now * unit.speed + unit.phase))
				local lunge = (wave ^ 4) * LUNGE_DISTANCE
				local hop = (wave ^ 4) * 0.25
				unit.model:PivotTo(unit.home * CFrame.new(0, hop, lunge))
			end
		end
	end

	-- Enemy: grows in after spawning, idles (wraiths float), and lunges when a boss slams.
	local model = enemyModel
	if model ~= nil then
		local popT = math.clamp((now - popStartedAt) / POP_SECONDS, 0, 1)
		local popScale = 0.35 + 0.65 * (1 - (1 - popT) ^ 3)
		if popT < 1 or math.abs(model:GetScale() - enemyScale) > 0.001 then
			model:ScaleTo(enemyScale * popScale)
		end
		local bob = math.sin(now * 2.2) * (if enemyFloats then 0.5 else 0.12) * enemyScale
		local float = if enemyFloats then 0.8 * enemyScale else 0
		local lungeT = (now - lungeStartedAt) / 0.3
		local lunge = if lungeT >= 0 and lungeT < 1 then math.sin(lungeT * math.pi) * 3 else 0
		model:PivotTo(enemyHome * CFrame.new(0, bob + float, -lunge))
	end

	if isBoss then
		bossAttackTimer += dt
		if bossAttackTimer >= BOSS_ATTACK_INTERVAL then
			bossAttackTimer = 0
			bossAttack()
		end
	end

	-- Camera shake fades out quickly.
	local camera = workspace.CurrentCamera
	if shake > 0.01 then
		shake *= math.exp(-dt * 8)
		local offset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * shake
		camera.CFrame = cameraBase * CFrame.new(offset)
	else
		shake = 0
		camera.CFrame = cameraBase
	end
end

---------------------------------------------------------------- setup

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

local function makeHighlight(color: Color3, fill: number, adornee: Instance?): Highlight
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = fill
	highlight.OutlineTransparency = if fill >= 1 then 1 else 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = adornee
	highlight.Parent = folder
	return highlight
end

function BattlefieldController.start()
	origin = Plots.origin(waitForPlot())

	folder = Instance.new("Folder")
	folder.Name = "Battlefield"
	folder.Parent = workspace

	troopsModel = Instance.new("Model")
	troopsModel.Name = "Troops"
	troopsModel.Parent = folder

	Effects.init(folder)

	-- Golden glow on the whole army while Rally is active, plus rising sparkles.
	rallyHighlight = makeHighlight(RALLY_COLOR, 0.65, troopsModel)
	rallyHighlight.Enabled = false
	local auraPart = Instance.new("Part")
	auraPart.Name = "RallyAura"
	auraPart.Anchored = true
	auraPart.CanCollide = false
	auraPart.CanQuery = false
	auraPart.CanTouch = false
	auraPart.Transparency = 1
	auraPart.Size = Vector3.new(26, 1, 12)
	auraPart.CFrame = CFrame.new(origin + Vector3.new(0, ARENA_TOP + 0.5, 0))
	auraPart.Parent = folder
	rallyAura = Instance.new("ParticleEmitter")
	rallyAura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	rallyAura.Color = ColorSequence.new(RALLY_COLOR)
	rallyAura.LightEmission = 1
	rallyAura.Size = NumberSequence.new(0.5, 0)
	rallyAura.Rate = 40
	rallyAura.Lifetime = NumberRange.new(0.8, 1.2)
	rallyAura.Speed = NumberRange.new(3, 6)
	rallyAura.EmissionDirection = Enum.NormalId.Top
	rallyAura.Enabled = false
	rallyAura.Parent = auraPart

	-- Red flash on the army when a boss hits it; white flash on the enemy when you hit it.
	hurtHighlight = makeHighlight(HURT_COLOR, 1, troopsModel)
	enemyHighlight = makeHighlight(Color3.new(1, 1, 1), 1, nil)
	enrageHighlight = makeHighlight(Color3.fromRGB(255, 40, 40), 0.55, nil)
	enrageHighlight.Enabled = false

	setupCamera()
	StateController.Changed:Connect(onStateChanged)
	InputController.Tapped:Connect(onTap)
	RunService.RenderStepped:Connect(animate)
end

return BattlefieldController
