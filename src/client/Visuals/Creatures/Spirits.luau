--!strict
-- Magical, undead and flying enemies: Shroomling, Mummy, Sprite (used as Frost Sprite and
-- Wisp), Fire Imp, Skeleton, Bat, Jellyfish, Harpy, Gargoyle. See Common for the rules.

local Parts = require(script.Parent.Parent.Parts)
local Common = require(script.Parent.Common)

type Builder = Common.Builder

local BODY = Common.BODY
local eyes = Common.eyes
local shade = Common.shade

local BONE = Color3.fromRGB(230, 225, 205)

local function shroomling(model: Model, at: CFrame, color: Color3): number
	Parts.cylinder(2, 1.5, Color3.fromRGB(230, 220, 195), at * CFrame.new(0, 1.2, 0), model) -- stalk body
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(0.4, 0.9, 0.4), Color3.fromRGB(220, 210, 185), at * CFrame.new(side * 0.4, 0.3, 0), model)
	end
	Parts.cylinder(0.6, 3.4, color, at * CFrame.new(0, 2.5, 0), model, BODY) -- cap
	Parts.ball(3, color, at * CFrame.new(0, 2.8, 0), model, BODY)
	for i = 1, 4 do
		Parts.ball(0.5, Color3.fromRGB(255, 250, 235), at * CFrame.new(math.cos(i * 1.6) * 0.9, 3.9, math.sin(i * 1.6) * 0.9), model) -- spots
	end
	eyes(model, at, 1.6, 0.3, -0.76, 0.3, Color3.fromRGB(40, 40, 40))
	return 4.2
end

local function mummy(model: Model, at: CFrame, color: Color3): number
	local wrap = { name = "Body", material = Enum.Material.Fabric }
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(0.8, 1.8, 0.8), color, at * CFrame.new(side * 0.5, 0.9, 0), model, wrap)
		-- Arms out in front, mummy style.
		Parts.block(Vector3.new(0.6, 0.6, 2), color, at * CFrame.new(side * 1.2, 3, -0.9), model, wrap)
	end
	Parts.block(Vector3.new(2, 2.2, 1.2), color, at * CFrame.new(0, 2.9, 0), model, wrap)
	for i = 0, 3 do
		Parts.block(Vector3.new(2.1, 0.12, 1.3), shade(color, -0.15), at * CFrame.new(0, 2 + i * 0.55, 0) * CFrame.Angles(0, 0, (i % 2 - 0.5) * 0.2), model) -- bandages
	end
	local head = at * CFrame.new(0, 4.6, 0)
	Parts.block(Vector3.new(1.3, 1.3, 1.2), color, head, model, wrap)
	eyes(model, head, 0.1, 0.3, -0.62, 0.25, Color3.fromRGB(120, 255, 160))
	return 5.3
end

-- A glowing orb with a little crown of shards (Frost Sprite / Wisp, by theme color).
local function sprite(model: Model, at: CFrame, color: Color3): number
	Parts.ball(1.8, color, at * CFrame.new(0, 2.6, 0), model, { name = "Body", material = Enum.Material.Neon })
	Parts.ball(2.6, color, at * CFrame.new(0, 2.6, 0), model, { name = "Body", material = Enum.Material.ForceField, transparency = 0.3 })
	for i = 0, 4 do
		local angle = i / 5 * math.pi * 2
		Parts.wedge(Vector3.new(0.3, 1, 0.5), shade(color, 0.2), at * CFrame.new(math.cos(angle) * 0.8, 3.7, math.sin(angle) * 0.8) * CFrame.Angles(0, -angle, 0), model, {
			material = Enum.Material.Ice,
		})
	end
	eyes(model, at, 2.7, 0.35, -0.85, 0.3, Color3.fromRGB(255, 255, 255))
	Parts.wedge(Vector3.new(0.6, 1.4, 0.6), color, at * CFrame.new(0, 1.2, 0.2) * CFrame.Angles(math.rad(180), 0, 0), model, {
		name = "Body",
		material = Enum.Material.Neon,
	}) -- wispy tail
	return 4.2
end

local function fireImp(model: Model, at: CFrame, color: Color3): number
	local glow = Color3.fromRGB(255, 170, 50)
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(0.5, 1.2, 0.5), color, at * CFrame.new(side * 0.45, 0.6, 0), model, BODY)
		Parts.block(Vector3.new(0.4, 1.2, 0.4), color, at * CFrame.new(side * 1.1, 2, -0.3) * CFrame.Angles(math.rad(-30), 0, side * math.rad(-20)), model, BODY)
		Parts.wedge(Vector3.new(0.2, 1.4, 1.2), shade(color, -0.2), at * CFrame.new(side * 1, 2.6, 0.6) * CFrame.Angles(0, side * math.rad(40), 0), model) -- wings
	end
	Parts.ball(1.8, color, at * CFrame.new(0, 2, 0), model, BODY)
	local head = at * CFrame.new(0, 3.2, -0.1)
	Parts.ball(1.4, color, head, model, BODY)
	for side = -1, 1, 2 do
		Parts.wedge(Vector3.new(0.2, 0.6, 0.3), Color3.fromRGB(40, 30, 30), head * CFrame.new(side * 0.4, 0.7, 0), model) -- horns
	end
	eyes(model, head, 0.1, 0.25, -0.62, 0.25, glow)
	Parts.ball(0.9, glow, at * CFrame.new(1.3, 2.9, -0.8), model, { material = Enum.Material.Neon }) -- fireball in hand
	return 4
end

local function skeleton(model: Model, at: CFrame, _color: Color3): number
	local bone = { name = "Body", material = Enum.Material.SmoothPlastic }
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(0.3, 1.8, 0.3), BONE, at * CFrame.new(side * 0.4, 0.9, 0), model, bone)
		Parts.block(Vector3.new(0.25, 1.8, 0.25), BONE, at * CFrame.new(side * 1.05, 2.6, -0.2) * CFrame.Angles(math.rad(-15), 0, 0), model, bone)
	end
	Parts.block(Vector3.new(1.2, 0.4, 0.6), BONE, at * CFrame.new(0, 1.9, 0), model, bone) -- hips
	for i = 0, 3 do
		Parts.block(Vector3.new(1.5 - i * 0.12, 0.18, 0.8), BONE, at * CFrame.new(0, 2.3 + i * 0.35, 0), model, bone) -- ribs
	end
	Parts.block(Vector3.new(0.25, 1.6, 0.25), BONE, at * CFrame.new(0, 2.9, 0.3), model, bone) -- spine
	local head = at * CFrame.new(0, 4.3, 0)
	Parts.ball(1.3, BONE, head, model, bone)
	eyes(model, head, 0.05, 0.25, -0.55, 0.3, Color3.fromRGB(120, 200, 255))
	-- Rusty sword.
	Parts.block(Vector3.new(0.15, 2.4, 0.4), Color3.fromRGB(150, 130, 110), at * CFrame.new(1.1, 2.6, -1.2) * CFrame.Angles(math.rad(-60), 0, 0), model, {
		material = Enum.Material.CorrodedMetal,
	})
	return 5
end

local function bat(model: Model, at: CFrame, color: Color3): number
	Parts.ball(1.6, color, at * CFrame.new(0, 3, 0), model, BODY)
	for side = -1, 1, 2 do
		Parts.wedge(Vector3.new(0.15, 1.2, 2.4), color, at * CFrame.new(side * 1.6, 3.2, 0) * CFrame.Angles(0, side * math.rad(90), side * math.rad(-15)), model, BODY)
		Parts.wedge(Vector3.new(0.15, 0.8, 1.4), color, at * CFrame.new(side * 2.9, 3.1, 0) * CFrame.Angles(0, side * math.rad(90), side * math.rad(-25)), model, BODY)
		Parts.wedge(Vector3.new(0.15, 0.6, 0.4), color, at * CFrame.new(side * 0.4, 3.9, 0), model, BODY) -- ears
	end
	eyes(model, at, 3.15, 0.3, -0.7, 0.25, Color3.fromRGB(255, 60, 60))
	return 4.1
end

local function jellyfish(model: Model, at: CFrame, color: Color3): number
	local jelly = { name = "Body", material = Enum.Material.Glass, transparency = 0.3 }
	Parts.ball(3, color, at * CFrame.new(0, 3.6, 0), model, jelly)
	Parts.cylinder(0.5, 3, color, at * CFrame.new(0, 3.1, 0), model, jelly)
	Parts.ball(1.4, shade(color, 0.3), at * CFrame.new(0, 3.7, 0), model, { material = Enum.Material.Neon }) -- glowing core
	for i = 0, 5 do
		local angle = i / 6 * math.pi * 2
		Parts.block(Vector3.new(0.15, 2.4, 0.15), color, at * CFrame.new(math.cos(angle) * 1, 1.7, math.sin(angle) * 1), model, {
			material = Enum.Material.Neon,
			transparency = 0.2,
		})
	end
	eyes(model, at, 3.6, 0.45, -1.4, 0.25, Color3.fromRGB(255, 255, 255))
	return 5.1
end

local function harpy(model: Model, at: CFrame, color: Color3): number
	local feather = { name = "Body", material = Enum.Material.Fabric }
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(0.3, 1.2, 0.3), Color3.fromRGB(210, 170, 80), at * CFrame.new(side * 0.4, 1.3, 0), model) -- bird legs
		-- Big wings spread wide.
		Parts.wedge(Vector3.new(0.2, 2.6, 2.4), color, at * CFrame.new(side * 1.9, 3.4, 0.3) * CFrame.Angles(0, side * math.rad(80), side * math.rad(-20)), model, feather)
		Parts.wedge(Vector3.new(0.2, 1.8, 1.8), shade(color, 0.15), at * CFrame.new(side * 3.4, 3.8, 0.3) * CFrame.Angles(0, side * math.rad(80), side * math.rad(-35)), model, feather)
	end
	Parts.block(Vector3.new(1.4, 1.8, 1), color, at * CFrame.new(0, 2.8, 0), model, feather)
	local head = at * CFrame.new(0, 4.2, -0.1)
	Parts.ball(1.2, Color3.fromRGB(230, 200, 170), head, model)
	Parts.ball(1.4, color, head * CFrame.new(0, 0.25, 0.25), model, feather) -- feathery hair
	Parts.wedge(Vector3.new(0.3, 0.3, 0.5), Color3.fromRGB(240, 190, 60), head * CFrame.new(0, -0.1, -0.7), model) -- beak-nose
	eyes(model, head, 0.1, 0.25, -0.5, 0.22, Color3.fromRGB(255, 220, 90))
	return 4.8
end

local function gargoyle(model: Model, at: CFrame, color: Color3): number
	local stone = { name = "Body", material = Enum.Material.Slate }
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(0.9, 1.4, 1), color, at * CFrame.new(side * 0.7, 0.7, 0.2), model, stone)
		Parts.block(Vector3.new(0.7, 2, 0.7), color, at * CFrame.new(side * 1.6, 2.2, -0.4) * CFrame.Angles(math.rad(-25), 0, 0), model, stone)
		Parts.wedge(Vector3.new(0.2, 2.4, 2.2), shade(color, -0.1), at * CFrame.new(side * 1.5, 3.6, 0.9) * CFrame.Angles(0, side * math.rad(60), 0), model, stone) -- wings
	end
	Parts.block(Vector3.new(2.2, 2, 1.6), color, at * CFrame.new(0, 2.5, 0.1) * CFrame.Angles(math.rad(-10), 0, 0), model, stone)
	local head = at * CFrame.new(0, 4, -0.5)
	Parts.block(Vector3.new(1.4, 1.2, 1.3), color, head, model, stone)
	for side = -1, 1, 2 do
		Parts.wedge(Vector3.new(0.25, 0.8, 0.4), shade(color, -0.2), head * CFrame.new(side * 0.5, 0.9, 0.2), model, stone) -- horns
	end
	eyes(model, head, 0.1, 0.35, -0.66, 0.28, Color3.fromRGB(255, 120, 60))
	return 4.9
end

return table.freeze({
	Shroomling = shroomling,
	Mummy = mummy,
	Sprite = sprite,
	FireImp = fireImp,
	Skeleton = skeleton,
	Bat = bat,
	Jellyfish = jellyfish,
	Harpy = harpy,
	Gargoyle = gargoyle,
} :: { [string]: Builder })
