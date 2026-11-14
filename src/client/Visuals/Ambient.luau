--!strict
-- Background life around the battlefield (client only, cosmetic): small skirmishes far
-- behind the arena (your kinds of troops vs the area's creatures, lunging, shooting,
-- falling and being replaced), a column of troops marching along a road, and creatures
-- roaming the flanks. Spots in AmbientConfig, counts in the graphics profile.
--
-- BattlefieldController builds it together with the environment (new area or graphics
-- change) and calls `update` every frame. Units are anchored part models moved with
-- PivotTo; nothing here touches the server or the real fight.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Config = Shared:WaitForChild("Config")
local AmbientConfig = require(Config:WaitForChild("AmbientConfig"))
local TroopConfig = require(Config:WaitForChild("TroopConfig"))
local Parts = require(script.Parent.Parts)
local Quality = require(script.Parent.Quality)
local Effects = require(script.Parent.Effects)
local TroopModels = require(script.Parent.TroopModels)
local EnemyModels = require(script.Parent.EnemyModels)

type State = "Fight" | "Fall" | "Sink" | "Walk" | "Pause"

type Unit = {
	model: Model,
	troop: boolean, -- troop models face +Z, creatures face -Z
	troopId: string,
	floats: boolean,
	pos: Vector3, -- feet
	facing: Vector3, -- flat unit vector
	phase: number,
	state: State,
	stateAt: number,
	station: Vector3, -- where it stands in a skirmish
	target: Vector3, -- walking toward (skirmish replacements, roamers)
	nextShot: number,
	lastShot: number,
	area: number, -- roamers: index into ROAM_AREAS
}

type Skirmish = {
	centre: Vector3,
	troops: { Unit },
	enemies: { Unit },
	nextFall: number,
}

export type Handle = {
	update: (dt: number) -> (),
	destroy: () -> (),
}

local GROUND_TOP = 0.3 -- same as Environment
local FALL_SECONDS = 0.45
local SINK_SECONDS = 1.2
local RANGED: { [string]: { kind: string, color: Color3 } } = {
	Archer = { kind = "Arrow", color = Color3.fromRGB(255, 240, 200) },
	Mage = { kind = "Orb", color = Color3.fromRGB(150, 120, 255) },
	Siege = { kind = "Boulder", color = Color3.fromRGB(120, 110, 100) },
}

local Ambient = {}

local function between(rng: Random, range: NumberRange): number
	return rng:NextNumber(range.Min, range.Max)
end

local function place(unit: Unit, extra: CFrame?)
	local look = if unit.troop then -unit.facing else unit.facing
	local cframe = CFrame.lookAt(unit.pos, unit.pos + look)
	if extra ~= nil then
		cframe *= extra
	end
	unit.model:PivotTo(cframe)
end

local function newUnit(model: Model, troop: boolean, troopId: string, floats: boolean, pos: Vector3, facing: Vector3, rng: Random): Unit
	return {
		model = model,
		troop = troop,
		troopId = troopId,
		floats = floats,
		pos = pos,
		facing = facing,
		phase = rng:NextNumber(0, math.pi * 2),
		state = "Fight",
		stateAt = 0,
		station = pos,
		target = pos,
		nextShot = os.clock() + rng:NextNumber(0.5, 3),
		lastShot = -math.huge,
		area = 0,
	}
end

function Ambient.build(theme: Types.AreaTheme, origin: Vector3, parent: Instance, troopIds: { string }): Handle
	local profile = Quality.get()
	local rng = Random.new()
	local folder = Instance.new("Folder")
	folder.Name = "Ambient"
	folder.Parent = parent
	local ground = origin + Vector3.new(0, GROUND_TOP, 0)
	local scale = AmbientConfig.UNIT_SCALE
	local kinds = if #theme.enemyKinds > 0 then theme.enemyKinds else { theme.enemyKind }
	if #troopIds == 0 then
		troopIds = { "Swordsman" }
	end

	local function makeTroop(troopId: string, pos: Vector3, facing: Vector3): Unit
		local def = TroopConfig.TROOPS[troopId]
		local model = TroopModels.build(troopId, def.color, CFrame.new(pos), folder)
		model:ScaleTo(scale)
		local unit = newUnit(model, true, troopId, false, pos, facing, rng)
		place(unit)
		return unit
	end
	local function makeEnemy(pos: Vector3, facing: Vector3): Unit
		local kind = kinds[rng:NextInteger(1, #kinds)]
		local model = EnemyModels.build(kind, theme.enemyColor, scale, false, CFrame.new(pos), folder)
		local unit = newUnit(model, false, kind, EnemyModels.floats(kind), pos, facing, rng)
		place(unit)
		return unit
	end

	-- Skirmishes: troops on the +X side facing -X, creatures on the -X side facing +X
	-- (the camera sees them side on).
	local skirmishes: { Skirmish } = {}
	for i = 1, math.min(profile.ambientSkirmishes, #AmbientConfig.SKIRMISHES) do
		local centre = ground + AmbientConfig.SKIRMISHES[i]
		local skirmish: Skirmish = { centre = centre, troops = {}, enemies = {}, nextFall = os.clock() + between(rng, AmbientConfig.FALL_EVERY) }
		for k = 1, AmbientConfig.SKIRMISH_SIZE do
			local z = (k - (AmbientConfig.SKIRMISH_SIZE + 1) / 2) * AmbientConfig.SKIRMISH_GAP
			local troopId = troopIds[rng:NextInteger(1, #troopIds)]
			table.insert(skirmish.troops, makeTroop(troopId, centre + Vector3.new(AmbientConfig.SKIRMISH_WIDTH, 0, z), Vector3.new(-1, 0, 0)))
			table.insert(skirmish.enemies, makeEnemy(centre + Vector3.new(-AmbientConfig.SKIRMISH_WIDTH, 0, z + 0.8), Vector3.new(1, 0, 0)))
		end
		table.insert(skirmishes, skirmish)
	end

	-- The road and the marching column (walking toward +X).
	local marchers: { Unit } = {}
	local roadLength = AmbientConfig.ROAD_HALF_LENGTH * 2
	if profile.ambientMarchers > 0 then
		Parts.block(
			Vector3.new(roadLength + 10, 0.1, AmbientConfig.ROAD_WIDTH),
			theme.arenaColor,
			CFrame.new(ground + Vector3.new(0, 0.05, AmbientConfig.ROAD_Z)),
			folder,
			{ material = theme.arenaMaterial, name = "Road" }
		)
		for i = 1, profile.ambientMarchers do
			local troopId = troopIds[(i - 1) % #troopIds + 1]
			table.insert(marchers, makeTroop(troopId, ground + Vector3.new(0, 0, AmbientConfig.ROAD_Z), Vector3.new(1, 0, 0)))
		end
	end

	-- Roamers.
	local roamers: { Unit } = {}
	local function roamTarget(unit: Unit): Vector3
		local box = AmbientConfig.ROAM_AREAS[unit.area]
		return ground + Vector3.new(rng:NextNumber(box.min.X, box.max.X), 0, rng:NextNumber(box.min.Z, box.max.Z))
	end
	for i = 1, profile.ambientRoamers do
		local area = (i - 1) % #AmbientConfig.ROAM_AREAS + 1
		local box = AmbientConfig.ROAM_AREAS[area]
		local pos = ground + Vector3.new(rng:NextNumber(box.min.X, box.max.X), 0, rng:NextNumber(box.min.Z, box.max.Z))
		local unit = makeEnemy(pos, Vector3.new(0, 0, -1))
		unit.area = area
		unit.state = "Pause"
		unit.stateAt = os.clock() + rng:NextNumber(0, 2)
		table.insert(roamers, unit)
	end

	-- Walks `unit` toward its target; true when it got there.
	local function walk(unit: Unit, speed: number, dt: number, now: number): boolean
		local offset = unit.target - unit.pos
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local distance = flat.Magnitude
		if distance < 0.2 then
			unit.pos = unit.target
			return true
		end
		unit.facing = flat.Unit
		unit.pos += unit.facing * math.min(distance, speed * dt)
		local hop = if unit.floats then 1.5 + math.sin(now * 3 + unit.phase) * 0.4 else math.abs(math.sin(now * 8 + unit.phase)) * 0.35
		place(unit, CFrame.new(0, hop, 0))
		return false
	end

	local function fightPose(unit: Unit, foe: Unit?, now: number)
		local ranged = RANGED[unit.troopId]
		if unit.troop and ranged ~= nil then
			-- Ranged troops hold still and shoot every couple of seconds.
			local recoil = math.max(0, 1 - (now - unit.lastShot) * 6) * 0.3
			place(unit, CFrame.new(0, 0, -recoil))
			if now >= unit.nextShot then
				unit.lastShot = now
				unit.nextShot = now + rng:NextNumber(1.8, 3.2)
				if foe ~= nil and foe.state == "Fight" then
					local from = unit.pos + Vector3.new(0, 3, 0)
					local to = foe.pos + Vector3.new(0, 2.5, 0)
					if ranged.kind == "Arrow" then
						Effects.arrow(from, to, ranged.color, 0.4, nil)
					else
						Effects.orb(from, to, ranged.color, if ranged.kind == "Orb" then 0.7 else 1.2, 0.6, ranged.kind == "Orb", nil)
					end
				end
			end
			return
		end
		-- Melee: lunge toward the foe; sparks now and then at the peak.
		local wave = math.max(0, math.sin(now * 5 + unit.phase))
		local lift = if unit.floats then 1.5 + math.sin(now * 3 + unit.phase) * 0.4 else 0
		local forward = wave * 1.1
		-- Troop models face +Z locally, creatures -Z.
		place(unit, CFrame.new(0, lift, if unit.troop then forward else -forward))
		if now >= unit.nextShot and wave > 0.95 and foe ~= nil and foe.state == "Fight" then
			unit.nextShot = now + rng:NextNumber(1.5, 3.5)
			Effects.hitSparks((unit.pos + foe.pos) / 2 + Vector3.new(0, 2.5, 0))
		end
	end

	-- One unit of a skirmish drops: tips over, sinks, and a fresh one walks back in.
	local function updateSkirmishUnit(unit: Unit, foe: Unit?, side: number, now: number, dt: number)
		if unit.state == "Fight" then
			fightPose(unit, foe, now)
		elseif unit.state == "Fall" then
			local t = math.min(1, (now - unit.stateAt) / FALL_SECONDS)
			place(unit, CFrame.Angles(t * t * math.rad(85) * side, 0, 0))
			if t >= 1 then
				unit.state = "Sink"
				unit.stateAt = now
			end
		elseif unit.state == "Sink" then
			local t = math.min(1, (now - unit.stateAt) / SINK_SECONDS)
			place(unit, CFrame.new(0, -t * 4, 0) * CFrame.Angles(math.rad(85) * side, 0, 0))
			if t >= 1 then
				-- Back in from behind its own side.
				unit.pos = unit.station - unit.facing * AmbientConfig.RESPAWN_DISTANCE
				unit.target = unit.station
				unit.state = "Walk"
			end
		elseif unit.state == "Walk" then
			if walk(unit, AmbientConfig.WALK_SPEED, dt, now) then
				unit.facing = if unit.troop then Vector3.new(-1, 0, 0) else Vector3.new(1, 0, 0)
				unit.state = "Fight"
				place(unit)
			end
		end
	end

	local destroyed = false
	local function update(dt: number)
		if destroyed then
			return
		end
		local now = os.clock()
		for _, skirmish in skirmishes do
			if now >= skirmish.nextFall then
				skirmish.nextFall = now + between(rng, AmbientConfig.FALL_EVERY)
				-- Mostly the creatures lose; sometimes a troop goes down.
				local side = if rng:NextNumber() < 0.7 then skirmish.enemies else skirmish.troops
				local unit = side[rng:NextInteger(1, #side)]
				if unit.state == "Fight" then
					unit.state = "Fall"
					unit.stateAt = now
					Effects.hitSparks(unit.pos + Vector3.new(0, 2.5, 0))
				end
			end
			for k, unit in skirmish.troops do
				updateSkirmishUnit(unit, skirmish.enemies[k], 1, now, dt)
			end
			for k, unit in skirmish.enemies do
				updateSkirmishUnit(unit, skirmish.troops[k], -1, now, dt)
			end
		end

		-- Marchers: evenly spaced along the road, wrapping around at the end.
		local loop = roadLength + AmbientConfig.MARCH_GAP * 4
		for i, unit in marchers do
			local x = (now * AmbientConfig.MARCH_SPEED + (i - 1) * AmbientConfig.MARCH_GAP) % loop - AmbientConfig.ROAD_HALF_LENGTH
			unit.pos = ground + Vector3.new(x, 0, AmbientConfig.ROAD_Z + (if i % 2 == 0 then 1 else -1))
			local step = math.abs(math.sin(now * 7 + i))
			place(unit, CFrame.new(0, step * 0.35, 0) * CFrame.Angles(0, 0, math.sin(now * 7 + i) * 0.05))
		end

		for _, unit in roamers do
			if unit.state == "Pause" then
				local lift = if unit.floats then 1.5 + math.sin(now * 3 + unit.phase) * 0.4 else 0
				place(unit, CFrame.new(0, lift, 0) * CFrame.Angles(0, math.sin(now * 1.5 + unit.phase) * 0.15, 0))
				if now >= unit.stateAt then
					unit.target = roamTarget(unit)
					unit.state = "Walk"
				end
			elseif walk(unit, AmbientConfig.ROAM_SPEED, dt, now) then
				unit.state = "Pause"
				unit.stateAt = now + between(rng, AmbientConfig.ROAM_PAUSE)
			end
		end
	end

	return {
		update = update,
		destroy = function()
			destroyed = true
			folder:Destroy()
		end,
	}
end

return Ambient
