--!strict
-- Low-poly enemy models, one creature per area theme (AreaConfig enemyKind), plus the
-- clan raid boss. Each faces -Z (toward your troops) and its pivot is at its feet.
-- Bosses are the same creature, bigger, in the boss color, with a crown.
--
-- Parts tagged "Body" take the main color; everything else keeps its own color.

local Parts = require(script.Parent.Parts)

local EnemyModels = {}

type Builder = (model: Model, at: CFrame, color: Color3) -> number -- returns the creature's height

local EYE_YELLOW = Color3.fromRGB(255, 230, 80)

local function eyes(model: Model, at: CFrame, y: number, spacing: number, z: number, size: number, color: Color3)
	for side = -1, 1, 2 do
		Parts.ball(size, color, at * CFrame.new(side * spacing, y, z), model, { material = Enum.Material.Neon })
	end
end

local function goblin(model: Model, at: CFrame, color: Color3): number
	local body = { name = "Body" }
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(0.7, 1.4, 0.8), Color3.fromRGB(90, 70, 50), at * CFrame.new(side * 0.5, 0.7, 0), model)
	end
	Parts.block(Vector3.new(1.9, 1.8, 1.3), Color3.fromRGB(110, 80, 50), at * CFrame.new(0, 2.2, 0) * CFrame.Angles(math.rad(-10), 0, 0), model)
	local head = at * CFrame.new(0, 3.7, -0.3)
	Parts.ball(1.9, color, head, model, body)
	for side = -1, 1, 2 do
		Parts.wedge(Vector3.new(0.2, 0.7, 1.2), color, head * CFrame.new(side * 1.1, 0.3, 0.2) * CFrame.Angles(0, side * math.rad(70), 0), model, body)
	end
	eyes(model, head, 0.15, 0.4, -0.85, 0.35, EYE_YELLOW)
	-- Club.
	Parts.cylinder(2.4, 0.4, Color3.fromRGB(100, 70, 45), at * CFrame.new(1.4, 2.6, -0.4) * CFrame.Angles(math.rad(-30), 0, 0), model, {
		material = Enum.Material.Wood,
	})
	Parts.ball(0.9, Color3.fromRGB(100, 70, 45), at * CFrame.new(1.4, 3.6, -1), model, { material = Enum.Material.Wood })
	return 4.7
end

local function scorpion(model: Model, at: CFrame, color: Color3): number
	local body = { name = "Body" }
	Parts.block(Vector3.new(2.6, 1.2, 3.2), color, at * CFrame.new(0, 1.2, 0), model, body)
	Parts.block(Vector3.new(2, 1, 1.4), color, at * CFrame.new(0, 1.3, -2), model, body) -- head
	eyes(model, at, 1.6, 0.5, -2.7, 0.3, Color3.fromRGB(30, 30, 30))
	for side = -1, 1, 2 do
		for leg = 0, 2 do
			Parts.block(Vector3.new(1.6, 0.25, 0.25), color, at * CFrame.new(side * 1.9, 0.6, -0.8 + leg * 0.9) * CFrame.Angles(0, 0, side * math.rad(-30)), model)
		end
		-- Pincers.
		Parts.block(Vector3.new(0.5, 0.5, 1.6), color, at * CFrame.new(side * 1.4, 1.3, -3.2), model, body)
		Parts.wedge(Vector3.new(0.5, 0.8, 1), color, at * CFrame.new(side * 1.4, 1.5, -4.3), model, body)
	end
	-- Tail curling up and over.
	local segments = { Vector3.new(0, 1.8, 1.9), Vector3.new(0, 2.9, 2.3), Vector3.new(0, 4, 1.9), Vector3.new(0, 4.6, 1) }
	for _, offset in segments do
		Parts.ball(1, color, at * CFrame.new(offset), model, body)
	end
	Parts.wedge(Vector3.new(0.4, 0.8, 0.8), Color3.fromRGB(255, 80, 60), at * CFrame.new(0, 4.4, 0.2) * CFrame.Angles(math.rad(180), 0, 0), model, {
		material = Enum.Material.Neon,
	})
	return 5
end

local function yeti(model: Model, at: CFrame, color: Color3): number
	local body = { name = "Body", material = Enum.Material.Fabric }
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(1, 1.5, 1.1), color, at * CFrame.new(side * 0.8, 0.75, 0), model, body)
		Parts.block(Vector3.new(0.9, 2.6, 0.9), color, at * CFrame.new(side * 1.85, 2.4, -0.2) * CFrame.Angles(math.rad(-15), 0, side * math.rad(-8)), model, body)
	end
	Parts.block(Vector3.new(2.8, 2.6, 2), color, at * CFrame.new(0, 2.8, 0), model, body)
	local head = at * CFrame.new(0, 4.6, -0.3)
	Parts.block(Vector3.new(1.7, 1.4, 1.5), color, head, model, body)
	Parts.block(Vector3.new(1.3, 0.8, 0.2), Color3.fromRGB(120, 140, 170), head * CFrame.new(0, -0.15, -0.76), model) -- face
	eyes(model, head, 0, 0.35, -0.86, 0.3, Color3.fromRGB(110, 200, 255))
	for side = -1, 1, 2 do
		Parts.wedge(Vector3.new(0.3, 0.9, 0.6), Color3.fromRGB(230, 230, 220), head * CFrame.new(side * 0.6, 0.9, 0), model) -- horns
	end
	return 5.4
end

local function bogling(model: Model, at: CFrame, color: Color3): number
	local body = { name = "Body", material = Enum.Material.SmoothPlastic, transparency = 0.05 }
	Parts.ball(4, color, at * CFrame.new(0, 1.8, 0), model, body)
	Parts.ball(2.6, color, at * CFrame.new(0, 3.6, -0.2), model, body)
	for side = -1, 1, 2 do
		Parts.ball(1.4, color, at * CFrame.new(side * 1.9, 1.2, -0.6), model, body)
	end
	eyes(model, at, 3.9, 0.55, -1.25, 0.55, Color3.fromRGB(240, 255, 120))
	-- Drips.
	for i = 1, 4 do
		Parts.ball(0.5, color, at * CFrame.new(math.cos(i) * 1.6, 0.25, math.sin(i) * 1.6), model)
	end
	return 4.9
end

local function golem(model: Model, at: CFrame, color: Color3): number
	local rock = { name = "Body", material = Enum.Material.Basalt }
	local lava = { material = Enum.Material.Neon }
	local glow = Color3.fromRGB(255, 120, 40)
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(1.2, 1.6, 1.2), color, at * CFrame.new(side * 0.85, 0.8, 0), model, rock)
		Parts.block(Vector3.new(1.1, 2.8, 1.1), color, at * CFrame.new(side * 2.1, 2.6, -0.2) * CFrame.Angles(0, 0, side * math.rad(-6)), model, rock)
		Parts.block(Vector3.new(1.4, 1.2, 1.4), color, at * CFrame.new(side * 2.25, 1, -0.3), model, rock) -- fists
	end
	Parts.block(Vector3.new(3, 2.8, 2), color, at * CFrame.new(0, 3, 0), model, rock)
	Parts.block(Vector3.new(0.3, 2, 0.1), glow, at * CFrame.new(0.4, 3, -1.02) * CFrame.Angles(0, 0, math.rad(20)), model, lava) -- cracks
	Parts.block(Vector3.new(0.3, 1.4, 0.1), glow, at * CFrame.new(-0.6, 2.6, -1.02) * CFrame.Angles(0, 0, math.rad(-25)), model, lava)
	local head = at * CFrame.new(0, 4.9, -0.2)
	Parts.block(Vector3.new(1.6, 1.3, 1.5), color, head, model, rock)
	eyes(model, head, 0.1, 0.38, -0.78, 0.32, glow)
	return 5.6
end

local function wraith(model: Model, at: CFrame, color: Color3): number
	local cloth = { name = "Body", material = Enum.Material.Fabric }
	-- A floating cloak that narrows toward the ground.
	for i = 0, 3 do
		local d = 1.4 + i * 0.55
		Parts.cylinder(1.1, d, color, at * CFrame.new(0, 1 + (3 - i) * 0.95, 0), model, cloth)
	end
	local head = at * CFrame.new(0, 5, -0.1)
	Parts.ball(1.9, color, head, model, cloth) -- hood
	Parts.ball(1.4, Color3.fromRGB(15, 10, 25), head * CFrame.new(0, -0.1, -0.35), model) -- dark face
	eyes(model, head, 0, 0.3, -0.95, 0.3, Color3.fromRGB(200, 120, 255))
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(0.6, 2.2, 0.6), color, at * CFrame.new(side * 1.6, 3.6, -0.6) * CFrame.Angles(math.rad(-40), 0, side * math.rad(-15)), model, cloth)
		Parts.ball(0.6, Color3.fromRGB(200, 190, 220), at * CFrame.new(side * 1.75, 3.1, -1.6), model)
	end
	return 5.9
end

local function colossus(model: Model, at: CFrame, color: Color3): number
	local metal = { name = "Body", material = Enum.Material.DiamondPlate }
	local glow = Color3.fromRGB(255, 150, 60)
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(1.3, 1.8, 1.3), color, at * CFrame.new(side * 0.9, 0.9, 0), model, metal)
		Parts.block(Vector3.new(1.2, 3, 1.2), color, at * CFrame.new(side * 2.3, 2.9, 0), model, metal)
		Parts.ball(1.4, Color3.fromRGB(80, 80, 90), at * CFrame.new(side * 2.3, 4.5, 0), model, { material = Enum.Material.Metal }) -- shoulders
	end
	Parts.block(Vector3.new(3.4, 3, 2.2), color, at * CFrame.new(0, 3.3, 0), model, metal)
	Parts.cylinderZ(0.2, 1.2, glow, at * CFrame.new(0, 3.5, -1.15), model, { material = Enum.Material.Neon }) -- core
	local head = at * CFrame.new(0, 5.5, 0)
	Parts.block(Vector3.new(1.8, 1.4, 1.6), color, head, model, metal)
	Parts.block(Vector3.new(1.4, 0.25, 0.1), glow, head * CFrame.new(0, 0.1, -0.82), model, { material = Enum.Material.Neon }) -- visor
	return 6.3
end

local BUILDERS: { [string]: Builder } = {
	Goblin = goblin,
	Scorpion = scorpion,
	Yeti = yeti,
	Bogling = bogling,
	Golem = golem,
	Wraith = wraith,
	Colossus = colossus,
}

local function crown(model: Model, at: CFrame, height: number)
	local gold = Color3.fromRGB(255, 200, 60)
	local top = at * CFrame.new(0, height + 0.3, 0)
	Parts.cylinder(0.5, 1.8, gold, top, model, { material = Enum.Material.Neon })
	for i = 0, 4 do
		local angle = i / 5 * math.pi * 2
		Parts.wedge(Vector3.new(0.3, 0.7, 0.4), gold, top * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.55, -0.75), model, {
			material = Enum.Material.Neon,
		})
	end
end

-- Builds a creature. `scale` 1 is a normal enemy (~5 studs tall); bosses use more.
-- Returns the model (pivot at its feet, facing -Z) and its height in studs.
function EnemyModels.build(kind: string, color: Color3, scale: number, withCrown: boolean, home: CFrame, parent: Instance): (Model, number)
	local model = Instance.new("Model")
	model.Name = kind
	-- Built at the origin facing -Z, then scaled and moved into place.
	local at = CFrame.new()
	local root = Parts.block(Vector3.new(0.2, 0.2, 0.2), Color3.new(), at, model, { transparency = 1, name = "Root" })
	model.PrimaryPart = root
	local builder = BUILDERS[kind] or goblin
	local height = builder(model, at, color)
	if withCrown then
		crown(model, at, height)
	end
	model:ScaleTo(scale)
	model:PivotTo(home)
	model.Parent = parent
	return model, height * scale
end

return table.freeze(EnemyModels)
