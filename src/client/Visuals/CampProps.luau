--!strict
-- Part-built camp structures for the menu signs (CampConfig). Cosmetic only. Each model
-- is built around `at` (its feet), front = local -Z (turned toward the camera by the
-- caller). Returns the model and its height.

local Parts = require(script.Parent.Parts)

local CampProps = {}

local WOOD = Color3.fromRGB(120, 85, 55)
local DARK_WOOD = Color3.fromRGB(85, 60, 40)
local PAPER = Color3.fromRGB(240, 230, 205)
local METAL = Color3.fromRGB(170, 175, 185)

local function noticeBoard(model: Model, at: CFrame, color: Color3): number
	for _, side in { -1, 1 } do
		Parts.block(Vector3.new(0.6, 6, 0.6), DARK_WOOD, at * CFrame.new(side * 3.2, 3, 0), model, { material = Enum.Material.Wood, shadow = true })
	end
	Parts.block(Vector3.new(6.4, 4, 0.4), color, at * CFrame.new(0, 3.6, 0), model, { material = Enum.Material.WoodPlanks, shadow = true })
	-- roof
	-- (wedges: the tall face is at local +Z, the slope runs down toward -Z)
	Parts.wedge(Vector3.new(7.4, 0.9, 1.1), DARK_WOOD, at * CFrame.new(0, 6.05, -0.55), model, { material = Enum.Material.Wood })
	Parts.wedge(Vector3.new(7.4, 0.9, 1.1), DARK_WOOD, at * CFrame.new(0, 6.05, 0.55) * CFrame.Angles(0, math.pi, 0), model, { material = Enum.Material.Wood })
	-- pinned papers
	local papers = { { -2, 4.4, 0.08 }, { -0.4, 4.6, -0.05 }, { 1.6, 4.3, 0.1 }, { -1.3, 2.7, -0.08 }, { 1, 2.6, 0.06 } }
	for _, p in papers do
		Parts.block(Vector3.new(1.3, 1.5, 0.05), PAPER, at * CFrame.new(p[1], p[2], -0.24) * CFrame.Angles(0, 0, p[3]), model)
		Parts.ball(0.25, Color3.fromRGB(210, 50, 50), at * CFrame.new(p[1], p[2] + 0.6, -0.3), model)
	end
	return 6.5
end

local function tent(model: Model, at: CFrame, color: Color3): number
	-- two sloped sides meeting at the ridge (front faces -Z)
	Parts.wedge(Vector3.new(6, 4.5, 3), color, at * CFrame.new(0, 2.25, -1.5), model, { material = Enum.Material.Fabric, shadow = true })
	Parts.wedge(Vector3.new(6, 4.5, 3), color, at * CFrame.new(0, 2.25, 1.5) * CFrame.Angles(0, math.pi, 0), model, { material = Enum.Material.Fabric, shadow = true })
	-- end caps (the tent's ends face the sides) and a dark doorway on the front slope
	Parts.block(Vector3.new(2, 2.2, 0.2), Color3.fromRGB(30, 28, 35), at * CFrame.new(0, 1.1, -2.35), model)
	-- pole + pennant on the ridge
	Parts.cylinder(2.4, 0.25, DARK_WOOD, at * CFrame.new(0, 5.6, 0), model)
	Parts.wedge(Vector3.new(0.1, 0.9, 1.6), Color3.fromRGB(240, 200, 70), at * CFrame.new(0, 6.3, -0.8) * CFrame.Angles(0, math.pi / 2, math.pi / 2), model)
	-- crates by the door
	Parts.block(Vector3.new(1.4, 1.4, 1.4), WOOD, at * CFrame.new(3.6, 0.7, -1.8) * CFrame.Angles(0, 0.3, 0), model, { material = Enum.Material.WoodPlanks, shadow = true })
	Parts.block(Vector3.new(1, 1, 1), WOOD, at * CFrame.new(3.6, 1.9, -1.8) * CFrame.Angles(0, -0.2, 0), model, { material = Enum.Material.WoodPlanks })
	return 6.8
end

local function signpost(model: Model, at: CFrame, color: Color3): number
	Parts.cylinder(7.5, 0.6, DARK_WOOD, at * CFrame.new(0, 3.75, 0), model, { material = Enum.Material.Wood, shadow = true })
	local arrows = { { 6.4, 0.25, color }, { 5.2, -0.5, Color3.fromRGB(90, 170, 120) }, { 4, 0.9, Color3.fromRGB(150, 110, 220) } }
	for i, a in arrows do
		local dir = if i % 2 == 1 then 1 else -1
		local plank = at * CFrame.new(0, a[1], 0) * CFrame.Angles(0, a[2], 0)
		Parts.block(Vector3.new(3.2, 0.8, 0.25), a[3], plank * CFrame.new(dir * 1.5, 0, 0), model, { material = Enum.Material.WoodPlanks, shadow = true })
		Parts.wedge(Vector3.new(0.25, 0.8, 0.7), a[3], plank * CFrame.new(dir * 3.45, 0, 0) * CFrame.Angles(0, dir * math.pi / 2, 0), model)
	end
	-- lantern on top
	Parts.block(Vector3.new(0.9, 0.2, 0.9), DARK_WOOD, at * CFrame.new(0, 7.6, 0), model)
	local lamp = Parts.ball(0.8, Color3.fromRGB(255, 200, 90), at * CFrame.new(0, 8.1, 0), model, { material = Enum.Material.Neon })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 90)
	light.Range = 10
	light.Brightness = 1.2
	light.Parent = lamp
	-- a rolled map at the foot
	Parts.cylinderZ(1.6, 0.5, PAPER, at * CFrame.new(1.2, 0.3, -0.8) * CFrame.Angles(0, 0.6, 0), model)
	return 8.5
end

local function armorRack(model: Model, at: CFrame, color: Color3): number
	-- stand
	Parts.block(Vector3.new(2.6, 0.4, 1.6), DARK_WOOD, at * CFrame.new(0, 0.2, 0), model, { material = Enum.Material.Wood, shadow = true })
	Parts.block(Vector3.new(0.4, 5.6, 0.4), DARK_WOOD, at * CFrame.new(0, 3, 0), model, { material = Enum.Material.Wood })
	Parts.block(Vector3.new(3, 0.35, 0.35), DARK_WOOD, at * CFrame.new(0, 4.9, 0), model, { material = Enum.Material.Wood })
	-- breastplate, helmet, cape
	Parts.block(Vector3.new(2.3, 2.4, 1.1), METAL, at * CFrame.new(0, 3.6, -0.1), model, { material = Enum.Material.Metal, shadow = true })
	Parts.block(Vector3.new(2.5, 0.5, 1.2), color, at * CFrame.new(0, 2.5, -0.1), model, { material = Enum.Material.Fabric })
	Parts.ball(1.5, METAL, at * CFrame.new(0, 5.8, 0), model, { material = Enum.Material.Metal, shadow = true })
	Parts.block(Vector3.new(0.25, 1, 0.25), color, at * CFrame.new(0, 6.7, 0), model, { material = Enum.Material.Neon })
	Parts.block(Vector3.new(2.6, 3.4, 0.15), color, at * CFrame.new(0, 3.3, 0.6), model, { material = Enum.Material.Fabric })
	-- shield and sword leaning on it
	Parts.cylinderZ(0.3, 2.2, color, at * CFrame.new(-2.1, 1.3, -0.3) * CFrame.Angles(0, 0, 0.15), model, { material = Enum.Material.Metal, shadow = true })
	Parts.block(Vector3.new(0.2, 3.2, 0.5), METAL, at * CFrame.new(2, 1.7, -0.2) * CFrame.Angles(0, 0, -0.2), model, { material = Enum.Material.Metal })
	Parts.block(Vector3.new(0.9, 0.2, 0.3), Color3.fromRGB(200, 160, 60), at * CFrame.new(1.7, 3.2, -0.2) * CFrame.Angles(0, 0, -0.2), model)
	return 7
end

local BUILDERS: { [string]: (Model, CFrame, Color3) -> number } = {
	Board = noticeBoard,
	Tent = tent,
	Signpost = signpost,
	Rack = armorRack,
}

function CampProps.build(kind: string, color: Color3, at: CFrame, parent: Instance): (Model, number)
	local model = Parts.model(`Camp_{kind}`, parent)
	local builder = BUILDERS[kind] or noticeBoard
	local height = builder(model, at, color)
	return model, height
end

return CampProps
