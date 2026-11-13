--!strict
-- Animal-like enemies: Wolf, Beetle, Toad, Salamander, Serpent, Ape, Crab, Shark,
-- Crystal Spider. Built from parts; see Common for the builder rules.

local Parts = require(script.Parent.Parent.Parts)
local Common = require(script.Parent.Common)

type Builder = Common.Builder

local BODY = Common.BODY
local eyes = Common.eyes
local shade = Common.shade

local function wolf(model: Model, at: CFrame, color: Color3): number
	Parts.block(Vector3.new(1.6, 1.4, 3.4), color, at * CFrame.new(0, 2, 0.2), model, BODY)
	for side = -1, 1, 2 do
		for _, z in { -1.2, 1.4 } do
			Parts.block(Vector3.new(0.5, 1.5, 0.5), shade(color, -0.1), at * CFrame.new(side * 0.55, 0.75, z), model)
		end
	end
	local head = at * CFrame.new(0, 2.8, -1.9)
	Parts.block(Vector3.new(1.3, 1.2, 1.3), color, head, model, BODY)
	Parts.block(Vector3.new(0.8, 0.6, 1), shade(color, -0.15), head * CFrame.new(0, -0.25, -0.9), model) -- snout
	for side = -1, 1, 2 do
		Parts.wedge(Vector3.new(0.3, 0.7, 0.5), color, head * CFrame.new(side * 0.45, 0.9, 0.2), model, BODY) -- ears
	end
	eyes(model, head, 0.2, 0.35, -0.66, 0.25, Color3.fromRGB(255, 210, 80))
	Parts.block(Vector3.new(0.4, 0.4, 1.8), color, at * CFrame.new(0, 2.6, 2.4) * CFrame.Angles(math.rad(35), 0, 0), model, BODY) -- tail
	return 3.6
end

local function beetle(model: Model, at: CFrame, color: Color3): number
	Parts.ball(3.4, color, at * CFrame.new(0, 1.5, 0.2), model, { name = "Body", material = Enum.Material.Metal })
	Parts.block(Vector3.new(0.1, 1.6, 3), shade(color, -0.25), at * CFrame.new(0, 2.4, 0.2), model) -- shell seam
	local head = at * CFrame.new(0, 1.4, -1.8)
	Parts.ball(1.5, shade(color, -0.2), head, model)
	Parts.wedge(Vector3.new(0.4, 1.4, 0.6), shade(color, 0.15), head * CFrame.new(0, 0.9, -0.4) * CFrame.Angles(math.rad(-30), 0, 0), model) -- horn
	eyes(model, head, 0.15, 0.35, -0.6, 0.25, Color3.fromRGB(255, 240, 120))
	for side = -1, 1, 2 do
		for leg = 0, 2 do
			Parts.block(Vector3.new(1.4, 0.22, 0.22), shade(color, -0.3), at * CFrame.new(side * 1.6, 0.5, -0.8 + leg * 0.9) * CFrame.Angles(0, 0, side * math.rad(-35)), model)
		end
	end
	return 3.2
end

local function toad(model: Model, at: CFrame, color: Color3): number
	Parts.ball(3.4, color, at * CFrame.new(0, 1.5, 0), model, BODY)
	Parts.ball(2.6, shade(color, 0.2), at * CFrame.new(0, 1.2, -0.7), model) -- belly
	for side = -1, 1, 2 do
		Parts.ball(1, color, at * CFrame.new(side * 0.8, 3.1, -0.8), model, BODY) -- eye bumps
		Parts.ball(1.4, color, at * CFrame.new(side * 1.6, 0.6, 0.6), model, BODY) -- back legs
	end
	eyes(model, at, 3.2, 0.8, -1.25, 0.5, Color3.fromRGB(255, 220, 60))
	Parts.block(Vector3.new(1.8, 0.15, 0.2), shade(color, -0.35), at * CFrame.new(0, 1.9, -1.65), model) -- mouth
	return 3.6
end

local function salamander(model: Model, at: CFrame, color: Color3): number
	local glow = Color3.fromRGB(255, 140, 40)
	for i = 0, 3 do
		Parts.ball(1.6 - i * 0.25, color, at * CFrame.new(0, 0.9, -0.6 + i * 1.2), model, BODY)
	end
	local head = at * CFrame.new(0, 1.2, -1.9)
	Parts.block(Vector3.new(1.4, 0.9, 1.5), color, head, model, BODY)
	eyes(model, head, 0.3, 0.45, -0.75, 0.3, glow)
	for side = -1, 1, 2 do
		for _, z in { -0.8, 1 } do
			Parts.block(Vector3.new(0.9, 0.3, 0.3), shade(color, -0.1), at * CFrame.new(side * 1, 0.35, z), model)
		end
	end
	-- Flaming back spines.
	for i = 0, 3 do
		Parts.wedge(Vector3.new(0.2, 0.7, 0.6), glow, at * CFrame.new(0, 1.8, -0.6 + i * 1.1), model, { material = Enum.Material.Neon })
	end
	return 2.4
end

local function serpent(model: Model, at: CFrame, color: Color3): number
	-- Coiled body rising into a raised head.
	for i = 0, 6 do
		local angle = i * 0.9
		local r = 1.4 - i * 0.1
		Parts.ball(1.5 - i * 0.05, color, at * CFrame.new(math.cos(angle) * r, 0.7 + i * 0.12, math.sin(angle) * r + 0.6), model, BODY)
	end
	for i = 1, 3 do
		Parts.ball(1.2, color, at * CFrame.new(0, 1.5 + i * 0.9, -0.2 - i * 0.25), model, BODY)
	end
	local head = at * CFrame.new(0, 5, -1.2)
	Parts.block(Vector3.new(1.4, 0.9, 1.8), color, head, model, BODY)
	Parts.block(Vector3.new(1.8, 1.6, 0.2), shade(color, 0.2), head * CFrame.new(0, 0, 0.9), model) -- hood
	eyes(model, head, 0.25, 0.4, -0.9, 0.28, Color3.fromRGB(255, 230, 80))
	Parts.block(Vector3.new(0.12, 0.12, 0.7), Color3.fromRGB(230, 60, 60), head * CFrame.new(0, -0.3, -1.2), model) -- tongue
	return 5.6
end

local function ape(model: Model, at: CFrame, color: Color3): number
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(0.9, 1.4, 0.9), color, at * CFrame.new(side * 0.7, 0.7, 0.3), model, BODY)
		-- Long arms reaching to the ground.
		Parts.block(Vector3.new(0.8, 3.2, 0.8), color, at * CFrame.new(side * 1.8, 2, -0.5) * CFrame.Angles(math.rad(-20), 0, side * math.rad(-10)), model, BODY)
		Parts.ball(1.1, shade(color, -0.15), at * CFrame.new(side * 1.9, 0.5, -1.1), model)
	end
	Parts.ball(3, color, at * CFrame.new(0, 2.7, 0), model, BODY)
	Parts.ball(1.9, shade(color, 0.25), at * CFrame.new(0, 2.5, -0.8), model) -- chest
	local head = at * CFrame.new(0, 4.4, -0.4)
	Parts.ball(1.7, color, head, model, BODY)
	Parts.ball(1.1, shade(color, 0.3), head * CFrame.new(0, -0.2, -0.55), model) -- face
	eyes(model, head, 0.15, 0.3, -0.95, 0.25, Color3.fromRGB(255, 200, 70))
	return 5.2
end

local function crab(model: Model, at: CFrame, color: Color3): number
	Parts.ball(3.2, color, at * CFrame.new(0, 1.3, 0), model, BODY)
	Parts.block(Vector3.new(3.4, 0.6, 2.4), shade(color, -0.15), at * CFrame.new(0, 0.9, 0), model) -- shell rim
	for side = -1, 1, 2 do
		Parts.cylinder(0.9, 0.2, shade(color, -0.2), at * CFrame.new(side * 0.5, 2.9, -0.9), model) -- eye stalks
		Parts.ball(0.4, Color3.fromRGB(20, 20, 20), at * CFrame.new(side * 0.5, 3.4, -0.9), model)
		for leg = 0, 2 do
			Parts.block(Vector3.new(1.4, 0.22, 0.22), color, at * CFrame.new(side * 1.8, 0.5, -0.4 + leg * 0.6) * CFrame.Angles(0, 0, side * math.rad(-30)), model)
		end
		-- Big claws.
		Parts.block(Vector3.new(0.4, 0.4, 1.4), color, at * CFrame.new(side * 1.5, 1.4, -1.6), model, BODY)
		Parts.ball(1.3, color, at * CFrame.new(side * 1.6, 1.5, -2.5), model, BODY)
		Parts.wedge(Vector3.new(0.5, 0.6, 1), shade(color, 0.15), at * CFrame.new(side * 1.6, 2.1, -2.8), model)
	end
	return 3.6
end

local function shark(model: Model, at: CFrame, color: Color3): number
	-- A shark "swimming" upright through the air above the ground.
	Parts.ball(2.4, color, at * CFrame.new(0, 2.2, 0.4), model, BODY)
	Parts.ball(2, color, at * CFrame.new(0, 2.2, -1.1), model, BODY)
	Parts.ball(1.5, color, at * CFrame.new(0, 2.2, 1.9), model, BODY)
	Parts.block(Vector3.new(1.6, 0.7, 1.6), shade(color, 0.3), at * CFrame.new(0, 1.6, -0.6), model) -- belly
	Parts.wedge(Vector3.new(0.3, 1.6, 1.3), color, at * CFrame.new(0, 3.6, 0.3), model, BODY) -- dorsal fin
	Parts.wedge(Vector3.new(0.3, 1.8, 1), color, at * CFrame.new(0, 2.5, 2.9) * CFrame.Angles(math.rad(-30), 0, 0), model, BODY) -- tail
	for side = -1, 1, 2 do
		Parts.wedge(Vector3.new(0.2, 0.9, 1.1), color, at * CFrame.new(side * 1.2, 1.7, -0.3) * CFrame.Angles(0, 0, side * math.rad(60)), model, BODY)
	end
	eyes(model, at, 2.5, 0.75, -1.9, 0.28, Color3.fromRGB(20, 20, 30))
	for i = -2, 2 do
		Parts.wedge(Vector3.new(0.18, 0.3, 0.15), Color3.fromRGB(250, 250, 250), at * CFrame.new(i * 0.25, 1.85, -2.05), model) -- teeth
	end
	return 4
end

local function crystalSpider(model: Model, at: CFrame, color: Color3): number
	local glow = { material = Enum.Material.Neon }
	Parts.ball(2.4, color, at * CFrame.new(0, 1.6, 0.8), model, { name = "Body", material = Enum.Material.Glass })
	Parts.ball(1.6, color, at * CFrame.new(0, 1.5, -0.8), model, BODY)
	for side = -1, 1, 2 do
		for leg = 0, 3 do
			local z = -0.9 + leg * 0.6
			Parts.block(Vector3.new(1.6, 0.2, 0.2), shade(color, -0.2), at * CFrame.new(side * 1.4, 1.9, z) * CFrame.Angles(0, 0, side * math.rad(35)), model)
			Parts.block(Vector3.new(0.2, 1.6, 0.2), shade(color, -0.2), at * CFrame.new(side * 2.4, 0.9, z), model)
		end
	end
	-- Crystals growing out of its back.
	for i = 1, 3 do
		Parts.block(Vector3.new(0.4, 1.2 + i * 0.3, 0.4), shade(color, 0.3), at * CFrame.new((i - 2) * 0.5, 3, 0.8) * CFrame.Angles(0, 0, (i - 2) * 0.4), model, glow)
	end
	eyes(model, at, 1.8, 0.3, -1.55, 0.25, Color3.fromRGB(255, 80, 200))
	return 3.6
end

return table.freeze({
	Wolf = wolf,
	Beetle = beetle,
	Toad = toad,
	Salamander = salamander,
	Serpent = serpent,
	Ape = ape,
	Crab = crab,
	Shark = shark,
	CrystalSpider = crystalSpider,
} :: { [string]: Builder })
