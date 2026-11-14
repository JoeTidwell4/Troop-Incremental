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

local GOLD = Color3.fromRGB(240, 195, 70)

local function cart(model: Model, at: CFrame, color: Color3): number
	-- bed + wheels
	Parts.block(Vector3.new(5, 1.4, 2.8), WOOD, at * CFrame.new(0, 1.9, 0), model, { material = Enum.Material.WoodPlanks, shadow = true })
	for _, side in { -1, 1 } do
		local wheel = at * CFrame.new(side * 1.6, 1.1, -1.55)
		Parts.cylinderZ(0.3, 2.2, DARK_WOOD, wheel, model, { material = Enum.Material.Wood, shadow = true })
		Parts.cylinderZ(0.35, 0.5, METAL, wheel, model, { material = Enum.Material.Metal })
	end
	-- striped awning on four posts
	for _, x in { -2.3, 2.3 } do
		for _, z in { -1.2, 1.2 } do
			Parts.block(Vector3.new(0.25, 3, 0.25), DARK_WOOD, at * CFrame.new(x, 4.1, z), model)
		end
	end
	for i = 0, 4 do
		local stripe = if i % 2 == 0 then color else Color3.fromRGB(245, 240, 225)
		Parts.block(Vector3.new(1, 0.25, 3.2), stripe, at * CFrame.new(-2 + i, 5.7, 0) * CFrame.Angles(math.rad(-8), 0, 0), model, { material = Enum.Material.Fabric, shadow = true })
	end
	-- goods: gold pile, sacks, a gem
	Parts.ball(1.1, GOLD, at * CFrame.new(-1.2, 2.9, -0.3), model, { material = Enum.Material.Metal })
	Parts.ball(0.8, GOLD, at * CFrame.new(-0.6, 2.8, 0.4), model, { material = Enum.Material.Metal })
	Parts.ball(1.2, Color3.fromRGB(190, 160, 110), at * CFrame.new(1.2, 3, 0.2), model, { material = Enum.Material.Fabric })
	Parts.ball(0.6, Color3.fromRGB(80, 220, 255), at * CFrame.new(0.2, 2.9, -0.8), model, { material = Enum.Material.Neon })
	return 6
end

local function trophy(model: Model, at: CFrame, _color: Color3): number
	-- stepped stone pedestal
	Parts.block(Vector3.new(3.6, 0.8, 3.6), Color3.fromRGB(150, 150, 160), at * CFrame.new(0, 0.4, 0), model, { material = Enum.Material.Slate, shadow = true })
	Parts.block(Vector3.new(2.6, 1.6, 2.6), Color3.fromRGB(175, 175, 185), at * CFrame.new(0, 1.6, 0), model, { material = Enum.Material.Marble, shadow = true })
	Parts.block(Vector3.new(2.8, 0.25, 0.1), GOLD, at * CFrame.new(0, 1.6, -1.32), model, { material = Enum.Material.Metal })
	-- cup
	Parts.cylinder(0.3, 1.4, GOLD, at * CFrame.new(0, 2.55, 0), model, { material = Enum.Material.Metal })
	Parts.cylinder(1, 0.35, GOLD, at * CFrame.new(0, 3.2, 0), model, { material = Enum.Material.Metal })
	local cup = Parts.cylinder(1.4, 1.8, GOLD, at * CFrame.new(0, 4.4, 0), model, { material = Enum.Material.Metal, shadow = true })
	for _, side in { -1, 1 } do
		Parts.block(Vector3.new(0.25, 1, 0.25), GOLD, at * CFrame.new(side * 1.05, 4.5, 0), model, { material = Enum.Material.Metal })
	end
	Parts.ball(0.5, Color3.fromRGB(255, 240, 160), at * CFrame.new(0, 5.25, 0), model, { material = Enum.Material.Neon })
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 8
	light.Brightness = 1
	light.Parent = cup
	return 5.6
end

local function warDrum(model: Model, at: CFrame, color: Color3): number
	-- drum on a stand, two crossed banners behind it
	for _, side in { -1, 1 } do
		Parts.block(Vector3.new(0.3, 1.8, 0.3), DARK_WOOD, at * CFrame.new(side * 1.2, 0.9, 0) * CFrame.Angles(0, 0, side * 0.25), model)
	end
	Parts.cylinder(2, 2.8, Color3.fromRGB(150, 60, 50), at * CFrame.new(0, 2.6, 0), model, { material = Enum.Material.Wood, shadow = true })
	Parts.cylinder(0.12, 2.9, Color3.fromRGB(230, 215, 185), at * CFrame.new(0, 3.62, 0), model, { material = Enum.Material.Fabric })
	for _, y in { 1.75, 3.45 } do
		Parts.cylinder(0.15, 2.95, GOLD, at * CFrame.new(0, y, 0), model, { material = Enum.Material.Metal })
	end
	for _, side in { -1, 1 } do
		local pole = at * CFrame.new(side * 0.8, 0, 1.2) * CFrame.Angles(0, 0, side * -0.35)
		Parts.block(Vector3.new(0.25, 7, 0.25), DARK_WOOD, pole * CFrame.new(0, 3.5, 0), model)
		Parts.block(Vector3.new(1.6, 2.2, 0.1), color, pole * CFrame.new(side * -0.9, 5.6, 0), model, { material = Enum.Material.Fabric, shadow = true })
	end
	-- drumsticks
	Parts.block(Vector3.new(0.18, 1.6, 0.18), WOOD, at * CFrame.new(-0.5, 4.2, -0.3) * CFrame.Angles(0.4, 0, 0.5), model)
	Parts.block(Vector3.new(0.18, 1.6, 0.18), WOOD, at * CFrame.new(0.5, 4.2, -0.3) * CFrame.Angles(0.4, 0, -0.5), model)
	return 7
end

-- Where the clan banner stands: a stone base, a pole and a plain cloth that says "join a
-- clan". Hidden while you're in a clan (your real banner stands here then).
local function clanStand(model: Model, at: CFrame, color: Color3): number
	Parts.block(Vector3.new(2.4, 0.8, 2.4), Color3.fromRGB(110, 110, 115), at * CFrame.new(0, 0.4, 0), model, { material = Enum.Material.Slate, shadow = true })
	-- (as tall as the real clan banner's pole, so the label sits above either)
	Parts.cylinder(14, 0.35, Color3.fromRGB(95, 70, 45), at * CFrame.new(0, 7.8, 0), model, { material = Enum.Material.Wood })
	Parts.block(Vector3.new(3.2, 0.2, 0.2), DARK_WOOD, at * CFrame.new(1.6, 14.2, 0), model)
	Parts.block(Vector3.new(2.8, 3.4, 0.08), color, at * CFrame.new(1.6, 12.4, 0), model, { material = Enum.Material.Fabric, shadow = true })
	return 15
end

local BUILDERS: { [string]: (Model, CFrame, Color3) -> number } = {
	Cart = cart,
	Trophy = trophy,
	Drum = warDrum,
	ClanStand = clanStand,
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
