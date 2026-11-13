--!strict
-- One unique boss per biome (AreaConfig bossKind): Treant, Sandworm, FrostWyrm, BogHag,
-- MagmaTitan, HollowKing, JadeIdol, PrismQueen, Kraken, Griffin. Built at about normal
-- enemy size; BattlefieldController scales bosses up. See Common for the builder rules.

local Parts = require(script.Parent.Parent.Parts)
local Common = require(script.Parent.Common)

type Builder = Common.Builder

local BODY = Common.BODY
local eyes = Common.eyes
local shade = Common.shade

local NEON = { material = Enum.Material.Neon }
local GOLD = Color3.fromRGB(255, 200, 60)

local function treant(model: Model, at: CFrame, color: Color3): number
	local bark = Color3.fromRGB(95, 70, 45)
	local wood = { material = Enum.Material.Wood }
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(1.3, 2, 1.3), bark, at * CFrame.new(side * 0.9, 1, 0) * CFrame.Angles(0, 0, side * 0.15), model, wood) -- roots/legs
		Parts.block(Vector3.new(0.9, 3.2, 0.9), bark, at * CFrame.new(side * 2.1, 3.8, -0.3) * CFrame.Angles(math.rad(-20), 0, side * math.rad(-25)), model, wood) -- branch arms
		Parts.ball(1.6, color, at * CFrame.new(side * 2.9, 5.2, -0.8), model, { name = "Body", material = Enum.Material.Grass })
	end
	Parts.cylinder(4, 2.6, bark, at * CFrame.new(0, 3.5, 0), model, wood) -- trunk
	Parts.ball(2, Color3.fromRGB(40, 25, 15), at * CFrame.new(0, 4, -1.05), model) -- face hollow
	eyes(model, at, 4.4, 0.45, -1.6, 0.4, Color3.fromRGB(180, 255, 90))
	for i = 1, 3 do
		Parts.ball(3.4 - i * 0.4, color, at * CFrame.new((i - 2) * 1.1, 5.6 + i * 0.5, 0.3), model, { name = "Body", material = Enum.Material.Grass }) -- crown of leaves
	end
	return 7.4
end

local function sandworm(model: Model, at: CFrame, color: Color3): number
	-- Bursting up out of the sand, curving toward you.
	Parts.cylinder(0.4, 4.4, shade(color, -0.25), at * CFrame.new(0, 0.2, 0.6), model, { material = Enum.Material.Sand }) -- sand mound
	local segments = 6
	for i = 0, segments - 1 do
		local t = i / (segments - 1)
		local y = 0.9 + t * 5.4
		local z = 0.8 - math.sin(t * math.pi * 0.6) * 1.8
		Parts.ball(2.8 - t * 0.6, color, at * CFrame.new(0, y, z), model, BODY)
		Parts.cylinder(0.3, 2.9 - t * 0.6, shade(color, -0.15), at * CFrame.new(0, y - 0.4, z), model) -- ridges
	end
	local mouth = at * CFrame.new(0, 6.6, -1.4)
	Parts.cylinderZ(0.6, 2.4, Color3.fromRGB(120, 40, 40), mouth, model) -- open maw
	for i = 0, 5 do
		local angle = i / 6 * math.pi * 2
		Parts.wedge(Vector3.new(0.3, 0.6, 0.3), Color3.fromRGB(250, 245, 230), mouth * CFrame.new(math.cos(angle) * 0.9, math.sin(angle) * 0.9, -0.3), model) -- teeth
	end
	return 7.8
end

local function frostWyrm(model: Model, at: CFrame, color: Color3): number
	local ice = { name = "Body", material = Enum.Material.Ice }
	-- Long body curling in the air, wings, horned head breathing frost.
	for i = 0, 6 do
		local t = i / 6
		Parts.ball(1.8 - t * 0.6, color, at * CFrame.new(math.sin(t * 5) * 1.2, 2 + t * 1.5, 2.5 - t * 3.6), model, ice)
	end
	for side = -1, 1, 2 do
		Parts.wedge(Vector3.new(0.2, 3, 3.4), shade(color, 0.15), at * CFrame.new(side * 2.4, 4.6, 0.6) * CFrame.Angles(0, side * math.rad(80), side * math.rad(-25)), model, {
			material = Enum.Material.Glass,
			transparency = 0.2,
		})
	end
	local head = at * CFrame.new(0, 4.2, -1.9)
	Parts.block(Vector3.new(1.6, 1.2, 2.2), color, head, model, ice)
	for side = -1, 1, 2 do
		Parts.wedge(Vector3.new(0.25, 1.2, 0.5), Color3.fromRGB(240, 250, 255), head * CFrame.new(side * 0.6, 1, 0.6) * CFrame.Angles(math.rad(-30), 0, 0), model) -- horns
	end
	eyes(model, head, 0.3, 0.45, -1.1, 0.3, Color3.fromRGB(120, 220, 255))
	Parts.ball(0.9, Color3.fromRGB(190, 240, 255), head * CFrame.new(0, -0.3, -1.4), model, NEON) -- frost breath
	return 6.4
end

local function bogHag(model: Model, at: CFrame, color: Color3): number
	local rag = { name = "Body", material = Enum.Material.Fabric }
	for i = 0, 3 do
		Parts.cylinder(1.2, 3.6 - i * 0.6, color, at * CFrame.new(0, 0.6 + i * 1.1, 0), model, rag) -- ragged robe
	end
	local head = at * CFrame.new(0, 5.4, -0.3)
	Parts.ball(1.6, Color3.fromRGB(140, 160, 110), head, model)
	Parts.cylinder(1.6, 2.6, shade(color, -0.2), head * CFrame.new(0, 0.9, 0.1), model, rag) -- hat brim
	Parts.wedge(Vector3.new(1.4, 2.4, 1.4), shade(color, -0.2), head * CFrame.new(0, 2.4, 0.3) * CFrame.Angles(math.rad(-15), 0, 0), model, rag) -- pointy hat
	Parts.wedge(Vector3.new(0.3, 0.6, 0.8), Color3.fromRGB(120, 140, 95), head * CFrame.new(0, -0.1, -0.9), model) -- long nose
	eyes(model, head, 0.15, 0.32, -0.7, 0.25, Color3.fromRGB(200, 255, 80))
	-- Staff with a glowing skull.
	Parts.cylinder(6, 0.3, Color3.fromRGB(80, 60, 40), at * CFrame.new(2, 3, -0.6), model, { material = Enum.Material.Wood })
	Parts.ball(1, Color3.fromRGB(150, 255, 90), at * CFrame.new(2, 6.2, -0.6), model, NEON)
	return 7.6
end

local function magmaTitan(model: Model, at: CFrame, color: Color3): number
	local rock = { name = "Body", material = Enum.Material.Basalt }
	local lava = Color3.fromRGB(255, 120, 30)
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(1.6, 2.2, 1.6), color, at * CFrame.new(side * 1.1, 1.1, 0), model, rock)
		Parts.block(Vector3.new(1.4, 3.4, 1.4), color, at * CFrame.new(side * 2.8, 3.4, -0.2), model, rock)
		Parts.block(Vector3.new(2, 1.8, 2), color, at * CFrame.new(side * 3, 1.4, -0.4), model, rock) -- huge fists
		Parts.ball(1.6, lava, at * CFrame.new(side * 2.4, 5.6, 0), model, NEON) -- burning shoulders
	end
	Parts.block(Vector3.new(4, 3.6, 2.6), color, at * CFrame.new(0, 4, 0), model, rock)
	Parts.ball(1.8, lava, at * CFrame.new(0, 4.2, -1.1), model, NEON) -- molten core
	local head = at * CFrame.new(0, 6.5, -0.2)
	Parts.block(Vector3.new(1.8, 1.4, 1.6), color, head, model, rock)
	eyes(model, head, 0.1, 0.42, -0.82, 0.35, lava)
	for i = -1, 1 do
		Parts.wedge(Vector3.new(0.4, 1, 0.6), lava, head * CFrame.new(i * 0.6, 1.1, 0), model, NEON) -- flame crown
	end
	return 7.8
end

local function hollowKing(model: Model, at: CFrame, color: Color3): number
	local armor = { name = "Body", material = Enum.Material.Metal }
	local dark = Color3.fromRGB(20, 15, 30)
	Parts.wedge(Vector3.new(3.4, 5.4, 0.4), shade(color, -0.25), at * CFrame.new(0, 3, 1.1) * CFrame.Angles(0, math.pi, 0), model, {
		material = Enum.Material.Fabric,
	}) -- cape
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(1, 2.4, 1), color, at * CFrame.new(side * 0.7, 1.2, 0), model, armor)
		Parts.block(Vector3.new(0.9, 2.6, 0.9), color, at * CFrame.new(side * 1.9, 3.6, -0.2), model, armor)
		Parts.ball(1.4, shade(color, 0.15), at * CFrame.new(side * 1.8, 5, 0), model, armor) -- pauldrons
	end
	Parts.block(Vector3.new(2.6, 2.8, 1.6), color, at * CFrame.new(0, 3.8, 0), model, armor)
	local head = at * CFrame.new(0, 5.9, 0)
	Parts.block(Vector3.new(1.5, 1.6, 1.5), color, head, model, armor) -- helm
	Parts.block(Vector3.new(1.1, 0.3, 0.1), dark, head * CFrame.new(0, 0.1, -0.76), model) -- visor slit
	eyes(model, head, 0.1, 0.3, -0.8, 0.22, Color3.fromRGB(190, 120, 255))
	for i = 0, 4 do
		local angle = (i / 4 - 0.5) * math.pi * 0.8
		Parts.wedge(Vector3.new(0.3, 0.9, 0.3), GOLD, head * CFrame.new(math.sin(angle) * 0.7, 1.1, math.cos(angle) * -0.3), model, NEON) -- crown
	end
	-- Huge greatsword planted in front.
	Parts.block(Vector3.new(0.3, 4.6, 0.9), Color3.fromRGB(150, 150, 170), at * CFrame.new(0, 2.3, -1.4), model, { material = Enum.Material.Metal })
	Parts.block(Vector3.new(2, 0.3, 0.4), GOLD, at * CFrame.new(0, 4.6, -1.4), model, NEON)
	return 7
end

local function jadeIdol(model: Model, at: CFrame, color: Color3): number
	local jade = { name = "Body", material = Enum.Material.Marble }
	Parts.block(Vector3.new(4, 1.2, 3), shade(color, -0.2), at * CFrame.new(0, 0.6, 0), model, { material = Enum.Material.Slate }) -- plinth
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(1.2, 2.6, 1.2), color, at * CFrame.new(side * 2, 3.4, -0.2), model, jade)
		Parts.ball(1.4, color, at * CFrame.new(side * 2, 2, -0.6), model, jade) -- fists
	end
	Parts.block(Vector3.new(2.8, 3, 2.2), color, at * CFrame.new(0, 2.7, 0), model, jade)
	local head = at * CFrame.new(0, 5.4, 0)
	Parts.block(Vector3.new(2.4, 2.2, 2), color, head, model, jade) -- big stone head
	Parts.block(Vector3.new(1.8, 0.4, 0.2), shade(color, -0.35), head * CFrame.new(0, -0.6, -1), model) -- mouth
	eyes(model, head, 0.3, 0.55, -1.05, 0.45, Color3.fromRGB(120, 255, 170))
	Parts.block(Vector3.new(3, 0.5, 2.4), GOLD, head * CFrame.new(0, 1.3, 0), model, { material = Enum.Material.Metal }) -- headdress band
	for i = -1, 1 do
		Parts.wedge(Vector3.new(0.6, 1.4, 0.4), Color3.fromRGB(80, 200, 120), head * CFrame.new(i * 0.9, 2.2, 0.3), model, NEON) -- feathers
	end
	return 8.2
end

local function prismQueen(model: Model, at: CFrame, color: Color3): number
	local crystal = { name = "Body", material = Enum.Material.Glass, transparency = 0.1 }
	-- A spider queen with a tall crystal body.
	Parts.ball(3.2, color, at * CFrame.new(0, 2.2, 1.1), model, crystal) -- abdomen
	Parts.block(Vector3.new(1.6, 3.2, 1.4), color, at * CFrame.new(0, 3.6, -0.6), model, crystal) -- upright torso
	for side = -1, 1, 2 do
		for leg = 0, 3 do
			local z = -0.6 + leg * 0.7
			Parts.block(Vector3.new(2.2, 0.3, 0.3), shade(color, -0.2), at * CFrame.new(side * 1.8, 2.4, z) * CFrame.Angles(0, 0, side * math.rad(35)), model)
			Parts.block(Vector3.new(0.3, 2.4, 0.3), shade(color, -0.2), at * CFrame.new(side * 3.2, 1.2, z), model)
		end
	end
	local head = at * CFrame.new(0, 5.8, -0.6)
	Parts.ball(1.4, color, head, model, crystal)
	eyes(model, head, 0.1, 0.3, -0.62, 0.25, Color3.fromRGB(255, 90, 210))
	for i = 0, 4 do
		local angle = (i / 4 - 0.5) * math.pi
		Parts.block(Vector3.new(0.35, 1.6, 0.35), shade(color, 0.3), head * CFrame.new(math.sin(angle) * 0.6, 1, 0) * CFrame.Angles(0, 0, -angle * 0.4), model, NEON) -- crystal crown
	end
	return 7.4
end

local function kraken(model: Model, at: CFrame, color: Color3): number
	local skin = { name = "Body", material = Enum.Material.SmoothPlastic }
	Parts.ball(4.6, color, at * CFrame.new(0, 4.4, 0.4), model, skin) -- head
	Parts.ball(3, color, at * CFrame.new(0, 6.6, 1), model, skin) -- mantle
	eyes(model, at, 4.6, 1.1, -1.8, 0.8, Color3.fromRGB(255, 220, 60))
	-- Tentacles: curving up out of the ground around it.
	for i = 0, 5 do
		local angle = (i / 5 - 0.5) * math.pi * 1.2
		local base = Vector3.new(math.sin(angle) * 3, 0, -math.cos(angle) * 1.5)
		for s = 0, 3 do
			local t = s / 3
			local offset = base + Vector3.new(math.sin(angle) * t * 0.8, 0.5 + t * 3, -t * 0.6)
			Parts.ball(1.2 - t * 0.5, color, at * CFrame.new(offset), model, skin)
		end
	end
	return 8.1
end

local function griffin(model: Model, at: CFrame, color: Color3): number
	local feather = { name = "Body", material = Enum.Material.Fabric }
	local fur = Color3.fromRGB(200, 160, 90)
	Parts.block(Vector3.new(2.2, 2, 3.6), fur, at * CFrame.new(0, 2.6, 0.4), model) -- lion body
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(0.6, 1.8, 0.6), fur, at * CFrame.new(side * 0.8, 0.9, 1.5), model)
		Parts.block(Vector3.new(0.5, 1.8, 0.5), Color3.fromRGB(240, 200, 90), at * CFrame.new(side * 0.8, 0.9, -1), model) -- eagle legs
		-- Great wings raised high.
		Parts.wedge(Vector3.new(0.3, 3.6, 3.4), color, at * CFrame.new(side * 2.4, 5, 0.6) * CFrame.Angles(0, side * math.rad(70), side * math.rad(-35)), model, feather)
		Parts.wedge(Vector3.new(0.3, 2.6, 2.4), shade(color, 0.2), at * CFrame.new(side * 4.2, 6.2, 0.6) * CFrame.Angles(0, side * math.rad(70), side * math.rad(-50)), model, feather)
	end
	local head = at * CFrame.new(0, 4.6, -1.8)
	Parts.ball(1.9, color, head, model, feather) -- eagle head
	Parts.wedge(Vector3.new(0.6, 0.8, 1.1), Color3.fromRGB(250, 200, 60), head * CFrame.new(0, -0.2, -1.1) * CFrame.Angles(math.rad(180), 0, 0), model) -- beak
	eyes(model, head, 0.25, 0.45, -0.85, 0.3, Color3.fromRGB(130, 220, 255))
	Parts.block(Vector3.new(0.3, 0.3, 2), fur, at * CFrame.new(0, 3, 2.6) * CFrame.Angles(math.rad(30), 0, 0), model) -- tail
	-- Crackling storm orb above its head.
	Parts.ball(0.9, Color3.fromRGB(160, 220, 255), head * CFrame.new(0, 1.6, 0), model, NEON)
	return 7.2
end

return table.freeze({
	Treant = treant,
	Sandworm = sandworm,
	FrostWyrm = frostWyrm,
	BogHag = bogHag,
	MagmaTitan = magmaTitan,
	HollowKing = hollowKing,
	JadeIdol = jadeIdol,
	PrismQueen = prismQueen,
	Kraken = kraken,
	Griffin = griffin,
} :: { [string]: Builder })
