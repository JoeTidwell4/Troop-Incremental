--!strict
-- Extra detail for every creature, added on top of its builder (EnemyModels.build calls
-- `Details.add` before scaling): teeth, claws, horns, spikes, manes, armor plates.
-- Coordinates match each builder in this folder / EnemyModels (built at `at`, facing -Z,
-- feet at y 0). Kept as a separate pass so the base shapes stay easy to read.
--
-- `Details.finish` then gives every creature a soft ground shadow (not floaters: the shadow
-- would rise with them) and bosses a glowing aura + light.

local Parts = require(script.Parent.Parent.Parts)
local Quality = require(script.Parent.Parent.Quality)
local Common = require(script.Parent.Common)

local shade = Common.shade

local WHITE = Color3.fromRGB(245, 240, 225)
local DARK = Color3.fromRGB(30, 22, 25)
local CLAW = Color3.fromRGB(235, 225, 200)
local NEON = { material = Enum.Material.Neon }

type Detail = (model: Model, at: CFrame, color: Color3) -> ()

-- A small pointed tooth/claw hanging down (point at the bottom front).
local function fang(model: Model, cf: CFrame, w: number, h: number, color: Color3?)
	Parts.wedge(Vector3.new(w, h, w), color or WHITE, cf * CFrame.Angles(math.pi, 0, 0), model)
end

-- A spike pointing up.
local function spike(model: Model, cf: CFrame, w: number, h: number, d: number, color: Color3, options: Parts.Options?)
	Parts.wedge(Vector3.new(w, h, d), color, cf, model, options)
end

local D: { [string]: Detail } = {}

---------------------------------------------------------------- first six + raid boss

D.Goblin = function(m, at, color)
	local body = { name = "Body" }
	-- Arms (one on the club), pointy nose, teeth, loincloth, studs on the club.
	Parts.block(Vector3.new(0.45, 1.3, 0.45), color, at * CFrame.new(1.15, 2.4, -0.1) * CFrame.Angles(0, 0, math.rad(15)), m, body)
	Parts.ball(0.55, color, at * CFrame.new(1.4, 1.75, 0.05), m, body)
	Parts.block(Vector3.new(0.45, 1.3, 0.45), color, at * CFrame.new(-1.15, 2.3, -0.1) * CFrame.Angles(0, 0, math.rad(-12)), m, body)
	Parts.ball(0.55, color, at * CFrame.new(-1.3, 1.6, -0.15), m, body)
	local head = at * CFrame.new(0, 3.7, -0.3)
	Parts.wedge(Vector3.new(0.3, 0.35, 0.5), shade(color, -0.15), head * CFrame.new(0, -0.15, -1.05) * CFrame.Angles(0, math.pi, 0), m)
	for side = -1, 1, 2 do
		fang(m, head * CFrame.new(side * 0.32, -0.55, -0.85), 0.18, 0.3)
	end
	Parts.block(Vector3.new(1.0, 0.8, 0.12), Color3.fromRGB(150, 60, 50), at * CFrame.new(0, 1.15, -0.7), m) -- loincloth
	for i = 0, 2 do
		local angle = i * 2.1
		spike(m, at * CFrame.new(1.4 + math.cos(angle) * 0.4, 3.75, -1 + math.sin(angle) * 0.4), 0.15, 0.4, 0.15, Color3.fromRGB(150, 150, 160))
	end
end

D.Scorpion = function(m, at, color)
	for i = 0, 2 do
		Parts.block(Vector3.new(2.7, 0.2, 0.6), shade(color, -0.2), at * CFrame.new(0, 1.85, -0.9 + i * 1.0), m) -- back plates
	end
	for side = -1, 1, 2 do
		fang(m, at * CFrame.new(side * 0.35, 0.95, -2.75), 0.2, 0.45, shade(color, -0.3)) -- mandibles
		Parts.block(Vector3.new(0.25, 0.25, 0.25), CLAW, at * CFrame.new(side * 1.4, 1.2, -4.85), m) -- pincer tips
	end
end

D.Yeti = function(m, at, color)
	local head = at * CFrame.new(0, 4.6, -0.3)
	Parts.block(Vector3.new(0.9, 0.22, 0.1), DARK, head * CFrame.new(0, -0.42, -0.82), m) -- mouth
	for side = -1, 1, 2 do
		fang(m, head * CFrame.new(side * 0.3, -0.48, -0.86), 0.16, 0.3)
		spike(m, at * CFrame.new(side * 1.5, 4.25, 0), 0.6, 0.7, 0.9, shade(color, 0.1), { material = Enum.Material.Fabric }) -- fur tufts
		for c = -1, 1 do
			fang(m, at * CFrame.new(side * 1.85 + c * 0.25, 0.95, -0.15), 0.16, 0.35, CLAW) -- claws
		end
	end
end

D.Bogling = function(m, at, color)
	Parts.block(Vector3.new(1.0, 0.3, 0.2), DARK, at * CFrame.new(0, 3.15, -1.4), m) -- mouth
	Parts.ball(0.7, Color3.new(1, 1, 1), at * CFrame.new(-0.5, 4.5, -0.6), m, { transparency = 0.5 }) -- shine
	for i = 0, 3 do
		Parts.ball(0.35, shade(color, 0.25), at * CFrame.new(math.cos(i * 1.7) * 1.2, 1.4 + i * 0.4, -1.5 + i * 0.1), m) -- bubbles
	end
end

D.Golem = function(m, at, color)
	local glow = Color3.fromRGB(255, 120, 40)
	for side = -1, 1, 2 do
		for i = 0, 1 do
			spike(m, at * CFrame.new(side * (1.9 + i * 0.35), 4.1 + i * 0.1, 0.1), 0.45, 0.9 - i * 0.2, 0.6, shade(color, -0.15), { material = Enum.Material.Basalt })
		end
		Parts.block(Vector3.new(0.1, 0.8, 0.1), glow, at * CFrame.new(side * 2.1, 2.5, -0.78), m, NEON) -- arm cracks
	end
	Parts.block(Vector3.new(1.2, 0.25, 0.1), glow, at * CFrame.new(0, 4.55, -0.97), m, NEON) -- glowing mouth
end

D.Wraith = function(m, at, color)
	for i = 0, 5 do
		local angle = i / 6 * math.pi * 2
		fang(m, at * CFrame.new(math.cos(angle) * 1.3, 0.55, math.sin(angle) * 1.3) * CFrame.Angles(0, -angle, 0), 0.5, 0.8, shade(color, -0.2)) -- tattered hem
	end
	Parts.ball(1.0, Color3.fromRGB(200, 140, 255), at * CFrame.new(0, 3.4, -0.9), m, { material = Enum.Material.Neon, transparency = 0.4 }) -- soul glow
end

D.Colossus = function(m, at, color)
	local glow = Color3.fromRGB(255, 150, 60)
	for side = -1, 1, 2 do
		for i = 0, 2 do
			spike(m, at * CFrame.new(side * (2.0 + i * 0.3), 5.1, 0), 0.3, 0.8, 0.5, Color3.fromRGB(70, 70, 80), { material = Enum.Material.Metal })
		end
		Parts.ball(0.5, glow, at * CFrame.new(side * 0.9, 1.9, -0.6), m, NEON) -- knee joints
		Parts.block(Vector3.new(0.12, 1.2, 0.12), Color3.fromRGB(90, 90, 100), at * CFrame.new(side * 0.5, 6.7, 0), m, { material = Enum.Material.Metal }) -- antennae
		Parts.ball(0.3, glow, at * CFrame.new(side * 0.5, 7.3, 0), m, NEON)
	end
	Parts.block(Vector3.new(3.5, 0.3, 2.3), shade(color, -0.2), at * CFrame.new(0, 2.0, 0), m, { material = Enum.Material.Metal }) -- belt
end

---------------------------------------------------------------- beasts

D.Wolf = function(m, at, color)
	local head = at * CFrame.new(0, 2.8, -1.9)
	Parts.ball(0.3, DARK, head * CFrame.new(0, -0.05, -1.4), m) -- nose
	for side = -1, 1, 2 do
		fang(m, head * CFrame.new(side * 0.25, -0.62, -1.25), 0.14, 0.28)
		for _, z in { -1.2, 1.4 } do
			Parts.block(Vector3.new(0.6, 0.18, 0.3), CLAW, at * CFrame.new(side * 0.55, 0.09, z - 0.3), m) -- paws
		end
	end
	for i = 0, 3 do
		spike(m, at * CFrame.new(0, 2.75, -1.2 + i * 0.7), 0.5, 0.6, 0.6, shade(color, -0.12)) -- mane
	end
end

D.Beetle = function(m, at, color)
	local head = at * CFrame.new(0, 1.4, -1.8)
	Parts.ball(1.2, Color3.new(1, 1, 1), at * CFrame.new(-0.5, 2.8, 0.3), m, { transparency = 0.6 }) -- shell shine
	for side = -1, 1, 2 do
		fang(m, head * CFrame.new(side * 0.35, -0.35, -0.7) * CFrame.Angles(0, side * 0.4, 0), 0.18, 0.5, shade(color, -0.35)) -- mandibles
		spike(m, head * CFrame.new(side * 0.45, 0.6, -0.1), 0.2, 0.6, 0.3, shade(color, 0.15)) -- small horns
	end
end

D.Toad = function(m, at, color)
	for i = 0, 5 do
		Parts.ball(0.35, shade(color, -0.15), at * CFrame.new(math.cos(i * 1.3) * 1.3, 2.4 + math.sin(i * 2.1) * 0.5, 0.6 + math.sin(i) * 0.5), m) -- warts
	end
	Parts.block(Vector3.new(0.3, 0.12, 0.9), Color3.fromRGB(230, 90, 110), at * CFrame.new(0, 1.82, -1.9), m) -- tongue tip
	for side = -1, 1, 2 do
		Parts.ball(0.5, shade(color, 0.15), at * CFrame.new(side * 0.9, 0.3, -1.2), m) -- front feet
	end
end

D.Salamander = function(m, at, color)
	local glow = Color3.fromRGB(255, 140, 40)
	for i = 0, 3 do
		Parts.ball(0.3, glow, at * CFrame.new((i % 2 - 0.5) * 0.9, 1.45, -0.4 + i * 1.1), m, NEON) -- glowing spots
	end
	local head = at * CFrame.new(0, 1.2, -1.9)
	for side = -1, 1, 2 do
		fang(m, head * CFrame.new(side * 0.35, -0.5, -0.65), 0.14, 0.25)
	end
	Parts.block(Vector3.new(0.35, 0.35, 1.6), color, at * CFrame.new(0, 0.6, 3.2) * CFrame.Angles(math.rad(10), 0, 0), m, { name = "Body" }) -- tail
end

D.Serpent = function(m, at, color)
	local head = at * CFrame.new(0, 5, -1.2)
	for side = -1, 1, 2 do
		fang(m, head * CFrame.new(side * 0.32, -0.55, -0.8), 0.15, 0.4)
	end
	for i = 0, 4 do
		Parts.block(Vector3.new(0.9, 0.12, 0.25), shade(color, 0.25), at * CFrame.new(0, 2.6 + i * 0.6, -0.75 - i * 0.12), m) -- belly scales
	end
	Parts.block(Vector3.new(1.0, 0.4, 0.15), shade(color, -0.25), head * CFrame.new(0, 0.5, 0.95), m) -- hood pattern
end

D.Ape = function(m, at, color)
	local head = at * CFrame.new(0, 4.4, -0.4)
	Parts.block(Vector3.new(1.15, 0.25, 0.3), shade(color, -0.3), head * CFrame.new(0, 0.42, -0.85), m) -- brow
	Parts.block(Vector3.new(0.6, 0.15, 0.1), DARK, head * CFrame.new(0, -0.45, -0.98), m) -- mouth
	for side = -1, 1, 2 do
		fang(m, head * CFrame.new(side * 0.2, -0.5, -0.98), 0.12, 0.22)
		Parts.block(Vector3.new(0.15, 0.6, 0.1), shade(color, 0.1), at * CFrame.new(side * 0.4, 2.5, -1.7), m) -- chest stripes
	end
end

D.Crab = function(m, at, color)
	for i = 0, 4 do
		local x = (i - 2) * 0.55
		spike(m, at * CFrame.new(x, 2.75 - math.abs(i - 2) * 0.2, 0.3), 0.3, 0.5, 0.4, shade(color, 0.2))
	end
	Parts.block(Vector3.new(0.8, 0.15, 0.1), DARK, at * CFrame.new(0, 1.3, -1.62), m) -- mouth
	for i = 0, 2 do
		Parts.ball(0.25, Color3.fromRGB(220, 240, 255), at * CFrame.new(-0.2 + i * 0.2, 1.6 + i * 0.35, -1.75), m, { transparency = 0.3 }) -- bubbles
	end
end

D.Shark = function(m, at, color)
	for side = -1, 1, 2 do
		for i = 0, 2 do
			Parts.block(Vector3.new(0.05, 0.6, 0.1), shade(color, -0.3), at * CFrame.new(side * 0.98, 2.3, -0.3 + i * 0.25), m) -- gills
		end
	end
	Parts.block(Vector3.new(0.12, 0.6, 0.1), shade(color, 0.35), at * CFrame.new(0.5, 2.9, -1.5) * CFrame.Angles(0, 0, 0.6), m) -- scar
end

D.CrystalSpider = function(m, at, color)
	for side = -1, 1, 2 do
		fang(m, at * CFrame.new(side * 0.25, 1.0, -1.5), 0.18, 0.5, shade(color, 0.3))
	end
	for i = 0, 1 do
		Parts.block(Vector3.new(0.3, 0.9, 0.3), shade(color, 0.35), at * CFrame.new((i - 0.5) * 1.4, 2.6, 1.5) * CFrame.Angles(0.3, 0, (i - 0.5) * 0.9), m, NEON)
	end
end

---------------------------------------------------------------- spirits

D.Shroomling = function(m, at, color)
	Parts.cylinder(0.2, 2.6, shade(color, -0.3), at * CFrame.new(0, 2.15, 0), m) -- gills under the cap
	Parts.block(Vector3.new(0.5, 0.12, 0.1), DARK, at * CFrame.new(0, 1.2, -0.76), m) -- mouth
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(0.3, 0.8, 0.3), Color3.fromRGB(225, 215, 190), at * CFrame.new(side * 0.85, 1.3, -0.2) * CFrame.Angles(0, 0, side * 0.5), m) -- arms
	end
end

D.Mummy = function(m, at, color)
	for i = 0, 2 do
		Parts.block(Vector3.new(0.25, 0.9, 0.06), shade(color, -0.1), at * CFrame.new(-0.6 + i * 0.6, 1.6 - i * 0.1, -0.62) * CFrame.Angles(0, 0, (i - 1) * 0.3), m, { material = Enum.Material.Fabric }) -- loose wraps
	end
	Parts.ball(0.5, Color3.fromRGB(120, 255, 160), at * CFrame.new(0, 3.1, -0.62), m, NEON) -- cursed gem
	Parts.block(Vector3.new(1.32, 0.15, 1.22), shade(color, -0.2), at * CFrame.new(0, 4.35, 0), m) -- head wrap line
end

D.Sprite = function(m, at, color)
	for i = 0, 2 do
		local angle = i / 3 * math.pi * 2
		Parts.ball(0.35, shade(color, 0.3), at * CFrame.new(math.cos(angle) * 1.8, 2.6 + math.sin(angle * 2) * 0.4, math.sin(angle) * 1.8), m, NEON) -- orbiting motes
	end
	Parts.block(Vector3.new(0.4, 0.1, 0.1), Color3.fromRGB(40, 40, 60), at * CFrame.new(0, 2.2, -0.88), m) -- tiny mouth
end
D.FrostSprite = D.Sprite
D.Wisp = D.Sprite

D.FireImp = function(m, at, color)
	local head = at * CFrame.new(0, 3.2, -0.1)
	for side = -1, 1, 2 do
		fang(m, head * CFrame.new(side * 0.2, -0.45, -0.55), 0.12, 0.22)
	end
	Parts.block(Vector3.new(0.2, 0.2, 1.4), color, at * CFrame.new(0, 1.2, 0.9) * CFrame.Angles(math.rad(-30), 0, 0), m, { name = "Body" }) -- tail
	spike(m, at * CFrame.new(0, 1.65, 1.65), 0.35, 0.4, 0.35, Color3.fromRGB(255, 170, 50), NEON) -- tail flame
end

D.Skeleton = function(m, at, _color)
	local head = at * CFrame.new(0, 4.3, 0)
	Parts.block(Vector3.new(0.8, 0.3, 0.7), Color3.fromRGB(225, 220, 200), head * CFrame.new(0, -0.65, -0.1), m) -- jaw
	Parts.block(Vector3.new(0.12, 0.25, 0.1), DARK, head * CFrame.new(0, -0.15, -0.62), m) -- nose hole
	Parts.cylinder(0.35, 1.4, Color3.fromRGB(120, 100, 80), head * CFrame.new(0, 0.45, 0), m, { material = Enum.Material.CorrodedMetal }) -- rusty helmet
	Parts.cylinderZ(0.15, 1.3, Color3.fromRGB(110, 90, 70), at * CFrame.new(-1.15, 2.5, -0.5), m, { material = Enum.Material.CorrodedMetal }) -- shield
end

D.Bat = function(m, at, color)
	for side = -1, 1, 2 do
		fang(m, at * CFrame.new(side * 0.18, 2.6, -0.7), 0.1, 0.25)
		Parts.block(Vector3.new(0.12, 0.5, 0.12), shade(color, -0.2), at * CFrame.new(side * 0.3, 2.05, 0.1), m) -- feet
		Parts.block(Vector3.new(0.08, 0.08, 2.0), shade(color, -0.3), at * CFrame.new(side * 2.2, 3.55, 0) * CFrame.Angles(0, side * math.rad(90), side * math.rad(-15)), m) -- wing finger
	end
end

D.Jellyfish = function(m, at, color)
	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2
		fang(m, at * CFrame.new(math.cos(angle) * 1.45, 2.7, math.sin(angle) * 1.45) * CFrame.Angles(0, -angle, 0), 0.5, 0.4, shade(color, 0.2)) -- frill
	end
	for i = 0, 3 do
		local angle = i / 4 * math.pi * 2 + 0.4
		Parts.block(Vector3.new(0.3, 1.6, 0.3), shade(color, 0.3), at * CFrame.new(math.cos(angle) * 0.5, 2.0, math.sin(angle) * 0.5), m, { material = Enum.Material.Glass, transparency = 0.3 }) -- oral arms
	end
end

D.Harpy = function(m, at, color)
	for side = -1, 1, 2 do
		for c = -1, 1 do
			fang(m, at * CFrame.new(side * 0.4 + c * 0.12, 0.6, -0.15), 0.1, 0.3, CLAW) -- talons
		end
	end
	for i = -1, 1 do
		Parts.wedge(Vector3.new(0.2, 1.4, 0.5), shade(color, -0.15), at * CFrame.new(i * 0.35, 1.6, 0.6) * CFrame.Angles(math.rad(150), 0, i * 0.3), m, { material = Enum.Material.Fabric }) -- tail feathers
	end
end

D.Gargoyle = function(m, at, color)
	local head = at * CFrame.new(0, 4, -0.5)
	for side = -1, 1, 2 do
		fang(m, head * CFrame.new(side * 0.3, -0.55, -0.66), 0.15, 0.3)
		for c = -1, 1 do
			fang(m, at * CFrame.new(side * 1.75 + c * 0.2, 1.05, -1.0), 0.14, 0.3, shade(color, -0.3)) -- claws
		end
	end
	Parts.block(Vector3.new(0.3, 0.3, 1.8), color, at * CFrame.new(0, 1.2, 1.4) * CFrame.Angles(math.rad(25), 0, 0), m, { name = "Body", material = Enum.Material.Slate }) -- tail
	spike(m, at * CFrame.new(0, 0.85, 2.3), 0.35, 0.5, 0.35, shade(color, -0.2)) -- tail tip
end

---------------------------------------------------------------- bosses

D.Treant = function(m, at, color)
	local bark = Color3.fromRGB(70, 50, 32)
	for i = 0, 3 do
		local angle = (i / 4 - 0.4) * math.pi
		Parts.block(Vector3.new(0.18, 3.4, 0.2), bark, at * CFrame.new(math.sin(angle) * 1.25, 3.5, -math.cos(angle) * 1.25), m) -- bark ridges
	end
	for i = -1, 1 do
		fang(m, at * CFrame.new(i * 0.35, 3.55, -1.95), 0.25, 0.45, Color3.fromRGB(150, 120, 80)) -- wooden teeth
	end
	for i = 0, 2 do
		Parts.ball(0.55, Color3.fromRGB(230, 70, 60), at * CFrame.new(-1.1 + i * 0.3, 2.2 + i * 0.6, -1.0), m) -- mushrooms
	end
	Parts.block(Vector3.new(0.15, 0.9, 0.1), Color3.fromRGB(180, 255, 90), at * CFrame.new(0.7, 2.6, -1.32) * CFrame.Angles(0, 0, 0.4), m, NEON) -- glowing rune
end

D.Sandworm = function(m, at, color)
	local mouth = at * CFrame.new(0, 6.6, -1.4)
	Parts.ball(1.3, Color3.fromRGB(255, 80, 40), mouth * CFrame.new(0, 0, 0.4), m, NEON) -- burning throat
	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2 + 0.3
		Parts.wedge(Vector3.new(0.2, 0.4, 0.2), WHITE, mouth * CFrame.new(math.cos(angle) * 0.55, math.sin(angle) * 0.55, -0.2), m) -- inner teeth
	end
	for i = 0, 3 do
		spike(m, at * CFrame.new(0, 2 + i * 1.2, 1.7 - i * 0.2), 0.4, 0.9, 0.7, shade(color, -0.25)) -- back plates
	end
end

D.FrostWyrm = function(m, at, color)
	for i = 0, 4 do
		local t = i / 6
		spike(m, at * CFrame.new(math.sin(t * 5) * 1.2, 2.9 + t * 1.5, 2.5 - t * 3.6), 0.25, 0.9, 0.5, Color3.fromRGB(230, 250, 255), { material = Enum.Material.Ice }) -- icicles
	end
	local head = at * CFrame.new(0, 4.2, -1.9)
	for side = -1, 1, 2 do
		fang(m, head * CFrame.new(side * 0.45, -0.75, -1.0), 0.18, 0.4)
	end
end

D.BogHag = function(m, at, color)
	local head = at * CFrame.new(0, 5.4, -0.3)
	for i = -2, 2 do
		Parts.block(Vector3.new(0.2, 1.4, 0.15), Color3.fromRGB(90, 110, 80), head * CFrame.new(i * 0.32, -0.6, 0.55), m) -- stringy hair
	end
	for side = -1, 1, 2 do
		Parts.ball(0.5, Color3.fromRGB(140, 160, 110), at * CFrame.new(side * 1.5, 3.3, -0.9), m) -- hands
	end
	Parts.wedge(Vector3.new(0.25, 0.3, 0.3), Color3.fromRGB(90, 70, 50), head * CFrame.new(0.25, 0.05, -1.25), m) -- wart
	for i = 0, 2 do
		Parts.block(Vector3.new(0.1, 0.7, 0.1), Color3.fromRGB(150, 255, 90), at * CFrame.new(2 + (i - 1) * 0.3, 6.8, -0.6) * CFrame.Angles(0, 0, (i - 1) * 0.5), m, NEON) -- skull flames
	end
end

D.MagmaTitan = function(m, at, color)
	local lava = Color3.fromRGB(255, 120, 30)
	for i = 0, 3 do
		Parts.block(Vector3.new(0.15, 1.2, 0.1), lava, at * CFrame.new(-1.4 + i * 0.9, 3.5 + (i % 2) * 0.6, -1.32) * CFrame.Angles(0, 0, (i % 2 - 0.5) * 0.8), m, NEON) -- lava veins
	end
	for side = -1, 1, 2 do
		for i = 0, 1 do
			spike(m, at * CFrame.new(side * (2.6 + i * 0.5), 6.2, 0.2), 0.5, 1.1, 0.7, shade(color, -0.1), { material = Enum.Material.Basalt })
		end
		Parts.block(Vector3.new(0.6, 0.6, 0.1), lava, at * CFrame.new(side * 3, 1.4, -1.42), m, NEON) -- glowing knuckles
	end
	Parts.block(Vector3.new(1.2, 0.25, 0.1), lava, at * CFrame.new(0, 6.15, -1.02), m, NEON) -- mouth
end

D.HollowKing = function(m, at, color)
	local gold = Color3.fromRGB(255, 200, 60)
	Parts.block(Vector3.new(0.9, 0.9, 0.1), gold, at * CFrame.new(0, 4.1, -0.82) * CFrame.Angles(0, 0, math.rad(45)), m, { material = Enum.Material.Metal }) -- chest emblem
	Parts.block(Vector3.new(2.7, 0.35, 1.7), shade(color, -0.2), at * CFrame.new(0, 2.5, 0), m, { material = Enum.Material.Metal }) -- belt
	for side = -1, 1, 2 do
		for i = 0, 1 do
			spike(m, at * CFrame.new(side * (1.6 + i * 0.4), 5.65, 0), 0.25, 0.8, 0.4, shade(color, -0.3), { material = Enum.Material.Metal }) -- pauldron spikes
		end
	end
	Parts.ball(0.6, Color3.fromRGB(190, 120, 255), at * CFrame.new(0, 4.75, -1.4), m, NEON) -- sword gem
end

D.JadeIdol = function(m, at, color)
	local gold = Color3.fromRGB(255, 200, 60)
	for i = 0, 2 do
		Parts.block(Vector3.new(2.85, 0.15, 2.25), gold, at * CFrame.new(0, 1.8 + i * 0.8, 0), m, { material = Enum.Material.Metal }) -- carved bands
	end
	local head = at * CFrame.new(0, 5.4, 0)
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(0.35, 0.9, 0.3), gold, head * CFrame.new(side * 1.3, -0.3, 0), m, { material = Enum.Material.Metal }) -- ear plugs
		fang(m, head * CFrame.new(side * 0.5, -0.85, -1.05), 0.3, 0.45, WHITE)
	end
	Parts.ball(0.7, Color3.fromRGB(120, 255, 170), at * CFrame.new(0, 3.2, -1.15), m, NEON) -- heart gem
end

D.PrismQueen = function(m, at, color)
	for i = 0, 4 do
		local angle = (i / 4 - 0.5) * math.pi
		Parts.block(Vector3.new(0.4, 1.3, 0.4), shade(color, 0.35), at * CFrame.new(math.sin(angle) * 1.1, 3.5, 1.1 + math.cos(angle) * 0.8) * CFrame.Angles(0, 0, -angle * 0.5), m, NEON) -- abdomen crystals
	end
	local head = at * CFrame.new(0, 5.8, -0.6)
	for side = -1, 1, 2 do
		fang(m, head * CFrame.new(side * 0.25, -0.7, -0.4), 0.15, 0.4, shade(color, 0.3))
		Parts.block(Vector3.new(0.3, 1.6, 0.3), shade(color, 0.2), at * CFrame.new(side * 1.0, 4.4, -1.0) * CFrame.Angles(math.rad(-40), 0, side * 0.4), m, { material = Enum.Material.Glass }) -- arms
	end
end

D.Kraken = function(m, at, color)
	for i = 0, 5 do
		local angle = (i / 5 - 0.5) * math.pi * 1.2
		for s = 0, 2 do
			local t = s / 3
			local base = Vector3.new(math.sin(angle) * 3, 0, -math.cos(angle) * 1.5)
			local offset = base + Vector3.new(math.sin(angle) * t * 0.8, 0.5 + t * 3, -t * 0.6 - (0.55 - t * 0.2))
			Parts.ball(0.3, shade(color, 0.35), at * CFrame.new(offset), m) -- suckers
		end
	end
	Parts.wedge(Vector3.new(0.7, 0.8, 0.7), Color3.fromRGB(40, 30, 30), at * CFrame.new(0, 3.2, -2.1) * CFrame.Angles(math.pi, 0, 0), m) -- beak
	for i = 0, 4 do
		Parts.ball(0.5, shade(color, -0.2), at * CFrame.new(math.cos(i * 1.4) * 1.3, 6.6 + math.sin(i * 1.4) * 0.6, -0.1), m) -- mantle spots
	end
end

D.Griffin = function(m, at, color)
	local head = at * CFrame.new(0, 4.6, -1.8)
	for i = -1, 1 do
		spike(m, head * CFrame.new(i * 0.3, 0.9, 0.4) * CFrame.Angles(math.rad(-20), 0, i * 0.3), 0.2, 0.9, 0.4, shade(color, 0.2), { material = Enum.Material.Fabric }) -- crest
	end
	for side = -1, 1, 2 do
		for c = -1, 1 do
			fang(m, at * CFrame.new(side * 0.8 + c * 0.15, 0.15, -1.3), 0.12, 0.3, Color3.fromRGB(60, 50, 40)) -- talons
		end
	end
	for i = 0, 1 do
		Parts.block(Vector3.new(0.12, 0.8, 0.12), Color3.fromRGB(160, 220, 255), head * CFrame.new(-0.4 + i * 0.8, 2.3, 0) * CFrame.Angles(0, 0, (i - 0.5) * 1.2), m, NEON) -- sparks off the storm orb
	end
	spike(m, at * CFrame.new(0, 3.5, 3.5), 0.5, 0.7, 0.5, Color3.fromRGB(170, 130, 70)) -- tail tuft
end

local Details = {}

-- Adds the extra parts for `kind` (nothing if it has none).
function Details.add(kind: string, model: Model, at: CFrame, color: Color3)
	local detail = D[kind]
	if detail ~= nil then
		detail(model, at, color)
	end
end

-- Ground shadow (walkers) and, for bosses, an aura + light. Call after building, before
-- scaling (sizes are in unscaled studs).
function Details.finish(model: Model, at: CFrame, color: Color3, height: number, floats: boolean, boss: boolean)
	if not floats then
		local _, size = model:GetBoundingBox()
		local width = math.clamp(math.max(size.X, size.Z) * 0.8, 2, 8)
		-- An invisible part with a painted round shadow: invisible parts are skipped by the
		-- enemy's hit-flash / outline Highlight and by Effects.shatter.
		local shadow = Parts.block(Vector3.new(width, 0.05, width), Color3.new(0, 0, 0), at * CFrame.new(0, 0.04, 0), model, { transparency = 1, name = "Shadow" })
		shadow:SetAttribute("NoShatter", true)
		local surface = Instance.new("SurfaceGui")
		surface.Face = Enum.NormalId.Top
		surface.LightInfluence = 0
		surface.CanvasSize = Vector2.new(64, 64)
		surface.Parent = shadow
		local disc = Instance.new("Frame")
		disc.Size = UDim2.fromScale(1, 1)
		disc.BackgroundColor3 = Color3.new(0, 0, 0)
		disc.BackgroundTransparency = 0.6
		disc.BorderSizePixel = 0
		disc.Parent = surface
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = disc
	end
	if boss then
		local core = Parts.block(Vector3.new(0.2, 0.2, 0.2), color, at * CFrame.new(0, height * 0.5, 0), model, { transparency = 1, name = "Aura" })
		local light = Instance.new("PointLight")
		light.Color = shade(color, 0.3)
		light.Brightness = 1.5
		light.Range = 14
		light.Parent = core
		local rate = 10 * Quality.get().particleRate
		if rate > 0 then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Color = ColorSequence.new(shade(color, 0.35))
			emitter.LightEmission = 0.8
			emitter.Size = NumberSequence.new(0.5, 0)
			emitter.Transparency = NumberSequence.new(0.2, 1)
			emitter.Lifetime = NumberRange.new(1, 1.8)
			emitter.Speed = NumberRange.new(1, 3)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Rate = rate
			emitter.Shape = Enum.ParticleEmitterShape.Box
			emitter.Parent = core
			core.Size = Vector3.new(height * 0.5, height * 0.8, height * 0.5)
		end
	end
end

return table.freeze(Details)
