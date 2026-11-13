--!strict
-- Builds the world around a player's battlefield for one area: a big themed ground, the
-- arena, scattered scenery, distant mountains, floating particles, and lighting/haze.
-- Client only and purely cosmetic. Rebuilt when you enter a new area.
--
-- Layout (relative to the plot centre): the arena is 70 x 36 studs; the camera sits at
-- (0, 22, -38) looking toward +Z. Scenery is kept out of the arena and out of the strip
-- between the camera and the arena so it never blocks the fight.

local Lighting = game:GetService("Lighting")

local Parts = require(script.Parent.Parts)
local Quality = require(script.Parent.Quality)

local GROUND_TOP = 0.3 -- big ground sits just below the arena top (0.5) to avoid flicker
local ARENA_SIZE = Vector3.new(70, 1, 36)

export type Theme = {
	scenery: string,
	groundColor: Color3,
	groundMaterial: Enum.Material,
	arenaColor: Color3,
	arenaMaterial: Enum.Material,
	mountainColor: Color3,
	clockTime: number,
	tint: Color3,
	hazeColor: Color3,
	hazeDensity: number,
	particles: string,
}

type PropBuilder = (rng: Random, at: CFrame, parent: Instance, near: boolean) -> ()

local Environment = {}

---------------------------------------------------------------- prop builders

local WOOD = Color3.fromRGB(105, 75, 50)
local STONE = Color3.fromRGB(130, 130, 135)

local function rock(rng: Random, at: CFrame, parent: Instance, color: Color3, material: Enum.Material)
	local size = rng:NextNumber(1.5, 4)
	Parts.block(
		Vector3.new(size * rng:NextNumber(0.8, 1.5), size * rng:NextNumber(0.5, 0.9), size),
		Parts.vary(color, rng, 0.05),
		at * CFrame.new(0, size * 0.25, 0) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), rng:NextNumber(-0.3, 0.3)),
		parent,
		{ material = material, shadow = true }
	)
end

local function bush(rng: Random, at: CFrame, parent: Instance, color: Color3)
	for _ = 1, 3 do
		local d = rng:NextNumber(1.5, 2.6)
		Parts.ball(d, Parts.vary(color, rng, 0.06), at * CFrame.new(rng:NextNumber(-1, 1), d * 0.35, rng:NextNumber(-1, 1)), parent, {
			material = Enum.Material.Grass,
		})
	end
end

local function leafyTree(rng: Random, at: CFrame, parent: Instance)
	local height = rng:NextNumber(7, 12)
	Parts.cylinder(height, rng:NextNumber(1, 1.6), WOOD, at * CFrame.new(0, height / 2, 0), parent, {
		material = Enum.Material.Wood,
		shadow = true,
	})
	local leaf = Color3.fromRGB(70, 130, 60)
	for i = 1, 3 do
		local d = rng:NextNumber(5, 8) - i
		Parts.ball(
			d,
			Parts.vary(leaf, rng, 0.07),
			at * CFrame.new(rng:NextNumber(-1.2, 1.2), height + (i - 1) * 2 - 1, rng:NextNumber(-1.2, 1.2)),
			parent,
			{ material = Enum.Material.Grass, shadow = true }
		)
	end
end

local function cactus(rng: Random, at: CFrame, parent: Instance)
	local green = Parts.vary(Color3.fromRGB(80, 140, 70), rng, 0.05)
	local height = rng:NextNumber(4, 8)
	Parts.cylinder(height, 1.4, green, at * CFrame.new(0, height / 2, 0), parent, { shadow = true })
	Parts.ball(1.4, green, at * CFrame.new(0, height, 0), parent)
	for side = -1, 1, 2 do
		if rng:NextNumber() < 0.75 then
			local armY = height * rng:NextNumber(0.4, 0.7)
			Parts.cylinder(1.2, 0.9, green, at * CFrame.new(side * 1.1, armY, 0) * CFrame.Angles(0, 0, math.rad(90)), parent)
			Parts.cylinder(2, 0.9, green, at * CFrame.new(side * 1.6, armY + 1, 0), parent)
		end
	end
end

local function bones(rng: Random, at: CFrame, parent: Instance)
	local bone = Color3.fromRGB(235, 225, 200)
	Parts.ball(1.4, bone, at * CFrame.new(0, 0.6, 0), parent)
	for i = 1, 3 do
		Parts.block(Vector3.new(0.3, 0.3, 2), bone, at * CFrame.new(rng:NextNumber(-1.5, 1.5), 0.2, i - 2) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), parent)
	end
end

local function pine(rng: Random, at: CFrame, parent: Instance, snowy: boolean)
	local height = rng:NextNumber(8, 13)
	Parts.cylinder(height * 0.4, 1, WOOD, at * CFrame.new(0, height * 0.2, 0), parent, { material = Enum.Material.Wood })
	local leaf = Parts.vary(Color3.fromRGB(45, 90, 60), rng, 0.04)
	local layers = 4
	for i = 1, layers do
		local t = (i - 1) / layers
		local d = 6 * (1 - t) + 1
		local y = height * 0.25 + t * height * 0.7
		Parts.cylinder(1.6, d, leaf, at * CFrame.new(0, y, 0), parent, { shadow = true })
		if snowy then
			Parts.cylinder(0.4, d * 0.85, Color3.fromRGB(245, 248, 255), at * CFrame.new(0, y + 0.9, 0), parent, {
				material = Enum.Material.Snow,
			})
		end
	end
end

local function iceSpike(rng: Random, at: CFrame, parent: Instance)
	local height = rng:NextNumber(3, 8)
	Parts.block(
		Vector3.new(1.2, height, 1.2),
		Color3.fromRGB(170, 215, 255),
		at * CFrame.new(0, height / 2 - 0.3, 0) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, 3), rng:NextNumber(-0.25, 0.25)),
		parent,
		{ material = Enum.Material.Ice, transparency = 0.15 }
	)
end

local function deadTree(rng: Random, at: CFrame, parent: Instance, color: Color3)
	local height = rng:NextNumber(6, 10)
	Parts.cylinder(height, 1.1, color, at * CFrame.new(0, height / 2, 0) * CFrame.Angles(rng:NextNumber(-0.1, 0.1), 0, rng:NextNumber(-0.1, 0.1)), parent, {
		material = Enum.Material.Wood,
		shadow = true,
	})
	for i = 1, 3 do
		local y = height * (0.45 + i * 0.15)
		local angle = rng:NextNumber(0, math.pi * 2)
		Parts.block(
			Vector3.new(0.4, 0.4, rng:NextNumber(2.5, 4)),
			color,
			at * CFrame.new(0, y, 0) * CFrame.Angles(0, angle, 0) * CFrame.Angles(math.rad(-35), 0, 0) * CFrame.new(0, 0, 1.5),
			parent,
			{ material = Enum.Material.Wood }
		)
	end
end

local function mushroom(rng: Random, at: CFrame, parent: Instance)
	local height = rng:NextNumber(1.5, 4)
	local capColor = if rng:NextNumber() < 0.5 then Color3.fromRGB(170, 70, 60) else Color3.fromRGB(150, 110, 170)
	Parts.cylinder(height, height * 0.35, Color3.fromRGB(225, 215, 190), at * CFrame.new(0, height / 2, 0), parent)
	Parts.cylinder(height * 0.3, height * 1.2, capColor, at * CFrame.new(0, height, 0), parent, { shadow = true })
	Parts.ball(height * 0.7, capColor, at * CFrame.new(0, height + 0.1, 0), parent)
end

local function puddle(rng: Random, at: CFrame, parent: Instance)
	Parts.cylinder(0.12, rng:NextNumber(4, 9), Color3.fromRGB(60, 80, 60), at * CFrame.new(0, 0.05, 0), parent, {
		material = Enum.Material.Glass,
		transparency = 0.25,
	})
end

local function reeds(rng: Random, at: CFrame, parent: Instance)
	for _ = 1, 5 do
		local h = rng:NextNumber(1.5, 3)
		Parts.block(
			Vector3.new(0.15, h, 0.15),
			Color3.fromRGB(110, 120, 60),
			at * CFrame.new(rng:NextNumber(-0.8, 0.8), h / 2, rng:NextNumber(-0.8, 0.8)) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2)),
			parent
		)
	end
end

local function lavaPool(rng: Random, at: CFrame, parent: Instance)
	local d = rng:NextNumber(4, 10)
	Parts.cylinder(0.2, d + 1.5, Color3.fromRGB(40, 30, 28), at * CFrame.new(0, 0.05, 0), parent, { material = Enum.Material.Basalt })
	Parts.cylinder(0.2, d, Color3.fromRGB(255, 110, 30), at * CFrame.new(0, 0.12, 0), parent, { material = Enum.Material.Neon })
end

local function lavaCrack(rng: Random, at: CFrame, parent: Instance)
	for i = 1, 3 do
		Parts.block(
			Vector3.new(0.35, 0.1, rng:NextNumber(2, 5)),
			Color3.fromRGB(255, 120, 40),
			at * CFrame.new(0, 0.02, (i - 2) * 2.5) * CFrame.Angles(0, rng:NextNumber(-0.6, 0.6), 0),
			parent,
			{ material = Enum.Material.Neon }
		)
	end
end

local function pillar(rng: Random, at: CFrame, parent: Instance)
	local height = rng:NextNumber(3, 10)
	Parts.block(Vector3.new(3, 0.8, 3), STONE, at * CFrame.new(0, 0.4, 0), parent, { material = Enum.Material.Slate })
	Parts.cylinder(height, 2, STONE, at * CFrame.new(0, height / 2 + 0.8, 0) * CFrame.Angles(rng:NextNumber(-0.08, 0.08), 0, 0), parent, {
		material = Enum.Material.Slate,
		shadow = true,
	})
end

local function grave(rng: Random, at: CFrame, parent: Instance)
	local stone = Parts.vary(Color3.fromRGB(110, 110, 120), rng, 0.05)
	Parts.block(Vector3.new(1.8, 2.4, 0.5), stone, at * CFrame.new(0, 1.2, 0) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.1, 0.1)), parent, {
		material = Enum.Material.Slate,
	})
end

local function crystal(rng: Random, at: CFrame, parent: Instance)
	local glow = Color3.fromRGB(170, 90, 255)
	for _ = 1, 3 do
		local h = rng:NextNumber(1.5, 4.5)
		Parts.block(
			Vector3.new(0.7, h, 0.7),
			glow,
			at * CFrame.new(rng:NextNumber(-0.8, 0.8), h / 2 - 0.3, rng:NextNumber(-0.8, 0.8)) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 3), rng:NextNumber(-0.4, 0.4)),
			parent,
			{ material = Enum.Material.Neon }
		)
	end
end

-- Jungle: tall trees with broad leaf tops and hanging vines.
local function jungleTree(rng: Random, at: CFrame, parent: Instance)
	local height = rng:NextNumber(10, 16)
	Parts.cylinder(height, rng:NextNumber(1.2, 1.8), Color3.fromRGB(95, 70, 45), at * CFrame.new(0, height / 2, 0), parent, {
		material = Enum.Material.Wood,
		shadow = true,
	})
	local leaf = Color3.fromRGB(45, 120, 50)
	for i = 0, 4 do
		local angle = i / 5 * math.pi * 2 + rng:NextNumber(0, 0.6)
		Parts.block(
			Vector3.new(1.6, 0.3, 5),
			Parts.vary(leaf, rng, 0.06),
			at * CFrame.new(0, height, 0) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, 2.2) * CFrame.Angles(math.rad(-20), 0, 0),
			parent,
			{ material = Enum.Material.Grass, shadow = true }
		)
	end
	for _ = 1, 2 do
		local vineLength = rng:NextNumber(3, 6)
		Parts.block(Vector3.new(0.2, vineLength, 0.2), Color3.fromRGB(60, 130, 50), at * CFrame.new(rng:NextNumber(-2, 2), height - vineLength / 2, rng:NextNumber(-2, 2)), parent)
	end
end

local function fern(rng: Random, at: CFrame, parent: Instance)
	for i = 0, 4 do
		Parts.wedge(
			Vector3.new(0.2, rng:NextNumber(1.2, 2.2), 1.4),
			Parts.vary(Color3.fromRGB(60, 140, 60), rng, 0.06),
			at * CFrame.Angles(0, i / 5 * math.pi * 2, 0) * CFrame.new(0, 0.6, 0.6) * CFrame.Angles(math.rad(25), 0, 0),
			parent,
			{ material = Enum.Material.Grass }
		)
	end
end

local function mossyRuin(rng: Random, at: CFrame, parent: Instance)
	local stone = Color3.fromRGB(120, 125, 105)
	local height = rng:NextNumber(2, 7)
	Parts.block(Vector3.new(2.4, height, 2.4), stone, at * CFrame.new(0, height / 2, 0) * CFrame.Angles(rng:NextNumber(-0.1, 0.1), rng:NextNumber(0, 3), 0), parent, {
		material = Enum.Material.Cobblestone,
		shadow = true,
	})
	Parts.block(Vector3.new(2.6, 0.4, 2.6), Color3.fromRGB(70, 130, 60), at * CFrame.new(0, height + 0.1, 0), parent, { material = Enum.Material.Grass }) -- moss
end

-- Crystal Caverns: big glowing crystal clusters and stalagmites.
local function crystalCluster(rng: Random, at: CFrame, parent: Instance)
	local colors = { Color3.fromRGB(110, 200, 255), Color3.fromRGB(220, 120, 255), Color3.fromRGB(120, 255, 220) }
	local color = colors[rng:NextInteger(1, #colors)]
	for _ = 1, rng:NextInteger(3, 5) do
		local h = rng:NextNumber(2, 7)
		Parts.block(
			Vector3.new(1, h, 1),
			color,
			at * CFrame.new(rng:NextNumber(-1.2, 1.2), h / 2 - 0.3, rng:NextNumber(-1.2, 1.2)) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 3), rng:NextNumber(-0.5, 0.5)),
			parent,
			{ material = Enum.Material.Neon }
		)
	end
end

local function stalagmite(rng: Random, at: CFrame, parent: Instance)
	local height = rng:NextNumber(3, 9)
	Parts.wedge(Vector3.new(2, height, 1.2), Color3.fromRGB(70, 60, 95), at * CFrame.new(0, height / 2, 0.6), parent, { material = Enum.Material.Slate, shadow = true })
	Parts.wedge(Vector3.new(2, height, 1.2), Color3.fromRGB(70, 60, 95), at * CFrame.new(0, height / 2, -0.6) * CFrame.Angles(0, math.pi, 0), parent, { material = Enum.Material.Slate })
end

-- Sunken Reef: branching coral, swaying seaweed, shells.
local function coral(rng: Random, at: CFrame, parent: Instance)
	local colors = { Color3.fromRGB(255, 120, 110), Color3.fromRGB(255, 180, 80), Color3.fromRGB(200, 110, 230) }
	local color = colors[rng:NextInteger(1, #colors)]
	for _ = 1, rng:NextInteger(3, 6) do
		local h = rng:NextNumber(1.5, 4.5)
		Parts.cylinder(
			h,
			0.5,
			color,
			at * CFrame.new(rng:NextNumber(-1, 1), h / 2, rng:NextNumber(-1, 1)) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), 0, rng:NextNumber(-0.5, 0.5)),
			parent
		)
	end
	Parts.ball(1.6, color, at * CFrame.new(0, 0.5, 0), parent)
end

local function seaweed(rng: Random, at: CFrame, parent: Instance)
	for _ = 1, 4 do
		local h = rng:NextNumber(3, 7)
		Parts.block(
			Vector3.new(0.3, h, 0.6),
			Parts.vary(Color3.fromRGB(60, 140, 80), rng, 0.08),
			at * CFrame.new(rng:NextNumber(-1, 1), h / 2, rng:NextNumber(-1, 1)) * CFrame.Angles(0, rng:NextNumber(0, 3), rng:NextNumber(-0.25, 0.25)),
			parent
		)
	end
end

local function shell(rng: Random, at: CFrame, parent: Instance)
	Parts.ball(rng:NextNumber(1, 2), Color3.fromRGB(250, 225, 200), at * CFrame.new(0, 0.2, 0), parent, { material = Enum.Material.Marble })
end

-- Sky Citadel: cloud puffs, marble columns, floating rocks.
local function cloud(rng: Random, at: CFrame, parent: Instance)
	for _ = 1, rng:NextInteger(3, 5) do
		local d = rng:NextNumber(3, 6)
		Parts.ball(d, Color3.fromRGB(255, 255, 255), at * CFrame.new(rng:NextNumber(-3, 3), d * 0.2, rng:NextNumber(-2, 2)), parent, {
			material = Enum.Material.SmoothPlastic,
			transparency = 0.1,
		})
	end
end

local function marbleColumn(rng: Random, at: CFrame, parent: Instance)
	local marble = Color3.fromRGB(235, 230, 220)
	local height = rng:NextNumber(5, 12)
	Parts.block(Vector3.new(3, 0.8, 3), marble, at * CFrame.new(0, 0.4, 0), parent, { material = Enum.Material.Marble })
	Parts.cylinder(height, 1.8, marble, at * CFrame.new(0, height / 2 + 0.8, 0), parent, { material = Enum.Material.Marble, shadow = true })
	if rng:NextNumber() < 0.6 then
		Parts.block(Vector3.new(3, 0.8, 3), marble, at * CFrame.new(0, height + 1.2, 0), parent, { material = Enum.Material.Marble })
	end
end

local function floatingRock(rng: Random, at: CFrame, parent: Instance)
	local size = rng:NextNumber(3, 7)
	local y = rng:NextNumber(8, 20)
	Parts.wedge(Vector3.new(size, size * 0.9, size), Color3.fromRGB(150, 140, 125), at * CFrame.new(0, y, 0) * CFrame.Angles(math.pi, rng:NextNumber(0, 3), 0), parent, {
		material = Enum.Material.Rock,
	})
	Parts.block(Vector3.new(size, 0.5, size), Color3.fromRGB(120, 180, 90), at * CFrame.new(0, y + size * 0.45 + 0.2, 0), parent, { material = Enum.Material.Grass })
end

local function pick(rng: Random, options: { PropBuilder }): PropBuilder
	return options[rng:NextInteger(1, #options)]
end

-- Each scenery set: what goes near the arena (small things) and further out (anything).
local SCENERY: { [string]: { near: { PropBuilder }, far: { PropBuilder } } } = {
	Forest = {
		near = {
			function(rng, at, parent)
				bush(rng, at, parent, Color3.fromRGB(80, 140, 60))
			end,
			function(rng, at, parent)
				rock(rng, at, parent, STONE, Enum.Material.Rock)
			end,
		},
		far = {
			leafyTree,
			leafyTree,
			leafyTree,
			function(rng, at, parent)
				bush(rng, at, parent, Color3.fromRGB(80, 140, 60))
			end,
		},
	},
	Desert = {
		near = {
			bones,
			function(rng, at, parent)
				rock(rng, at, parent, Color3.fromRGB(190, 150, 100), Enum.Material.Sandstone)
			end,
		},
		far = {
			cactus,
			cactus,
			function(rng, at, parent)
				rock(rng, at, parent, Color3.fromRGB(190, 150, 100), Enum.Material.Sandstone)
			end,
		},
	},
	Frozen = {
		near = {
			iceSpike,
			function(rng, at, parent)
				rock(rng, at, parent, Color3.fromRGB(200, 210, 225), Enum.Material.Glacier)
			end,
		},
		far = {
			function(rng, at, parent)
				pine(rng, at, parent, true)
			end,
			function(rng, at, parent)
				pine(rng, at, parent, true)
			end,
			iceSpike,
		},
	},
	Swamp = {
		near = { mushroom, reeds, puddle },
		far = {
			function(rng, at, parent)
				deadTree(rng, at, parent, Color3.fromRGB(70, 60, 45))
			end,
			mushroom,
			puddle,
			reeds,
		},
	},
	Ember = {
		near = {
			lavaCrack,
			function(rng, at, parent)
				rock(rng, at, parent, Color3.fromRGB(55, 45, 42), Enum.Material.Basalt)
			end,
		},
		far = {
			lavaPool,
			function(rng, at, parent)
				rock(rng, at, parent, Color3.fromRGB(55, 45, 42), Enum.Material.Basalt)
			end,
			lavaCrack,
		},
	},
	Jungle = {
		near = { fern, fern, mossyRuin },
		far = { jungleTree, jungleTree, jungleTree, mossyRuin, fern },
	},
	Crystal = {
		near = { crystalCluster, stalagmite },
		far = { crystalCluster, stalagmite, stalagmite },
	},
	Reef = {
		near = { coral, seaweed, shell },
		far = { coral, coral, seaweed },
	},
	Sky = {
		near = { cloud, marbleColumn },
		far = { cloud, cloud, marbleColumn, floatingRock, floatingRock },
	},
	Shadow = {
		near = { grave, crystal },
		far = {
			pillar,
			grave,
			crystal,
			function(rng, at, parent)
				deadTree(rng, at, parent, Color3.fromRGB(45, 40, 50))
			end,
		},
	},
}

---------------------------------------------------------------- layout

-- True where scenery must not go: the arena (plus a margin) and the camera's view lane.
local function blocked(x: number, z: number): boolean
	if math.abs(x) < 42 and z > -26 and z < 24 then
		return true
	end
	if math.abs(x) < 32 and z < -18 then
		return true
	end
	return false
end

local function scatter(rng: Random, origin: Vector3, parent: Instance, count: number, set: { near: { PropBuilder }, far: { PropBuilder } })
	local placed: { Vector2 } = {}
	local tries = 0
	while #placed < count and tries < count * 10 do
		tries += 1
		local x = rng:NextNumber(-170, 170)
		local z = rng:NextNumber(-55, 230)
		if not blocked(x, z) then
			local spot = Vector2.new(x, z)
			local clear = true
			for _, other in placed do
				if (other - spot).Magnitude < 7 then
					clear = false
					break
				end
			end
			if clear then
				table.insert(placed, spot)
				local near = math.abs(x) < 60 and z < 40
				local builder = pick(rng, if near then set.near else set.far)
				local at = CFrame.new(origin + Vector3.new(x, GROUND_TOP, z)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
				builder(rng, at, parent, near)
			end
		end
	end
end

local function mountains(rng: Random, theme: Theme, origin: Vector3, parent: Instance, count: number)
	local rounded = theme.scenery == "Desert" or theme.scenery == "Swamp" or theme.scenery == "Reef"
	local floating = theme.scenery == "Sky" -- far-off islands hanging in the sky instead of mountains
	for i = 1, count do
		-- Spread around the front and sides (the camera looks toward +Z).
		local angle = math.rad(-115 + (i - 1) * (230 / math.max(1, count - 1)) + rng:NextNumber(-6, 6))
		local distance = rng:NextNumber(300, 420)
		local position = origin + Vector3.new(math.sin(angle) * distance, GROUND_TOP, math.cos(angle) * distance)
		local facing = CFrame.lookAt(position, origin + Vector3.new(0, GROUND_TOP, 0))
		local color = Parts.vary(theme.mountainColor, rng, 0.04)
		if floating then
			local d = rng:NextNumber(60, 120)
			local lift = rng:NextNumber(40, 110)
			Parts.wedge(Vector3.new(d, d * 0.8, d), color, facing * CFrame.new(0, lift, 0) * CFrame.Angles(math.pi, 0, 0), parent, {
				material = Enum.Material.Rock,
			})
			Parts.block(Vector3.new(d, 3, d), Color3.fromRGB(120, 180, 90), facing * CFrame.new(0, lift + d * 0.4 + 1.5, 0), parent, {
				material = Enum.Material.Grass,
			})
		elseif rounded then
			local d = rng:NextNumber(90, 160)
			Parts.ball(d, color, facing * CFrame.new(0, -d * 0.3, 0), parent, { material = theme.groundMaterial })
		else
			local height = rng:NextNumber(60, 130)
			local width = rng:NextNumber(90, 160)
			Parts.ridge(width, height, height * 1.6, color, facing * CFrame.Angles(0, math.rad(90), 0), parent, {
				material = Enum.Material.Rock,
			})
			if theme.scenery == "Frozen" then
				Parts.ridge(width * 0.55, height * 0.35, height * 0.56, Color3.fromRGB(245, 248, 255), facing * CFrame.Angles(0, math.rad(90), 0) * CFrame.new(0, height * 0.65, 0), parent, {
					material = Enum.Material.Snow,
				})
			end
		end
	end
end

---------------------------------------------------------------- particles

type ParticleStyle = {
	color: Color3,
	texture: string,
	size: NumberRange,
	rate: number,
	lifetime: NumberRange,
	speed: NumberRange,
	direction: Enum.NormalId,
	spread: Vector2,
	lightEmission: number,
	transparency: number,
	height: number, -- emitter box height above the ground
	boxHeight: number,
}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local PARTICLES: { [string]: ParticleStyle } = {
	Fireflies = {
		color = Color3.fromRGB(220, 255, 140),
		texture = SPARKLE,
		size = NumberRange.new(0.25, 0.4),
		rate = 25,
		lifetime = NumberRange.new(4, 6),
		speed = NumberRange.new(0.5, 1.5),
		direction = Enum.NormalId.Top,
		spread = Vector2.new(180, 180),
		lightEmission = 1,
		transparency = 0.1,
		height = 4,
		boxHeight = 6,
	},
	Dust = {
		color = Color3.fromRGB(230, 200, 150),
		texture = SMOKE,
		size = NumberRange.new(1, 2.5),
		rate = 30,
		lifetime = NumberRange.new(3, 5),
		speed = NumberRange.new(4, 8),
		direction = Enum.NormalId.Right,
		spread = Vector2.new(15, 15),
		lightEmission = 0,
		transparency = 0.75,
		height = 2,
		boxHeight = 3,
	},
	Snow = {
		color = Color3.fromRGB(255, 255, 255),
		texture = SPARKLE,
		size = NumberRange.new(0.25, 0.45),
		rate = 140,
		lifetime = NumberRange.new(6, 8),
		speed = NumberRange.new(5, 8),
		direction = Enum.NormalId.Bottom,
		spread = Vector2.new(20, 20),
		lightEmission = 0.3,
		transparency = 0,
		height = 40,
		boxHeight = 1,
	},
	Mist = {
		color = Color3.fromRGB(170, 190, 160),
		texture = SMOKE,
		size = NumberRange.new(8, 14),
		rate = 6,
		lifetime = NumberRange.new(8, 12),
		speed = NumberRange.new(0.3, 1),
		direction = Enum.NormalId.Right,
		spread = Vector2.new(180, 10),
		lightEmission = 0,
		transparency = 0.85,
		height = 1.5,
		boxHeight = 2,
	},
	Embers = {
		color = Color3.fromRGB(255, 140, 50),
		texture = SPARKLE,
		size = NumberRange.new(0.2, 0.35),
		rate = 50,
		lifetime = NumberRange.new(3, 5),
		speed = NumberRange.new(3, 6),
		direction = Enum.NormalId.Top,
		spread = Vector2.new(25, 25),
		lightEmission = 1,
		transparency = 0,
		height = 1,
		boxHeight = 1,
	},
	Motes = {
		color = Color3.fromRGB(190, 140, 255),
		texture = SPARKLE,
		size = NumberRange.new(0.2, 0.4),
		rate = 30,
		lifetime = NumberRange.new(4, 6),
		speed = NumberRange.new(0.5, 2),
		direction = Enum.NormalId.Top,
		spread = Vector2.new(180, 180),
		lightEmission = 1,
		transparency = 0.1,
		height = 5,
		boxHeight = 8,
	},
}

PARTICLES.Leaves = {
	color = Color3.fromRGB(90, 170, 70),
	texture = SPARKLE,
	size = NumberRange.new(0.3, 0.5),
	rate = 20,
	lifetime = NumberRange.new(5, 7),
	speed = NumberRange.new(2, 4),
	direction = Enum.NormalId.Bottom,
	spread = Vector2.new(40, 40),
	lightEmission = 0,
	transparency = 0,
	height = 30,
	boxHeight = 1,
}
PARTICLES.Shards = {
	color = Color3.fromRGB(140, 220, 255),
	texture = SPARKLE,
	size = NumberRange.new(0.2, 0.45),
	rate = 35,
	lifetime = NumberRange.new(3, 5),
	speed = NumberRange.new(0.5, 1.5),
	direction = Enum.NormalId.Top,
	spread = Vector2.new(180, 180),
	lightEmission = 1,
	transparency = 0.1,
	height = 4,
	boxHeight = 8,
}
PARTICLES.Bubbles = {
	color = Color3.fromRGB(200, 240, 255),
	texture = SPARKLE,
	size = NumberRange.new(0.3, 0.6),
	rate = 40,
	lifetime = NumberRange.new(4, 6),
	speed = NumberRange.new(2, 4),
	direction = Enum.NormalId.Top,
	spread = Vector2.new(15, 15),
	lightEmission = 0.4,
	transparency = 0.3,
	height = 0.5,
	boxHeight = 1,
}
PARTICLES.Wind = {
	color = Color3.fromRGB(255, 255, 255),
	texture = SMOKE,
	size = NumberRange.new(1, 3),
	rate = 12,
	lifetime = NumberRange.new(3, 4),
	speed = NumberRange.new(10, 16),
	direction = Enum.NormalId.Right,
	spread = Vector2.new(5, 5),
	lightEmission = 0.2,
	transparency = 0.8,
	height = 6,
	boxHeight = 10,
}

local function ambientParticles(theme: Theme, origin: Vector3, parent: Instance)
	local style = PARTICLES[theme.particles]
	if style == nil then
		return
	end
	local box = Parts.block(
		Vector3.new(180, style.boxHeight, 140),
		Color3.new(1, 1, 1),
		CFrame.new(origin + Vector3.new(0, GROUND_TOP + style.height, 50)),
		parent,
		{ transparency = 1, name = "AmbientParticles" }
	)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = style.texture
	emitter.Color = ColorSequence.new(style.color)
	emitter.Size = NumberSequence.new(style.size.Min, style.size.Max)
	emitter.Rate = style.rate * Quality.get().particleRate
	emitter.Lifetime = style.lifetime
	emitter.Speed = style.speed
	emitter.EmissionDirection = style.direction
	emitter.SpreadAngle = style.spread
	emitter.LightEmission = style.lightEmission
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, style.transparency),
		NumberSequenceKeypoint.new(0.8, style.transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = box
end

---------------------------------------------------------------- public

-- Builds everything for one area at the current graphics quality (Visuals/Quality).
-- Returns the model holding it (destroy it to clear).
function Environment.build(theme: Theme, origin: Vector3, areaNumber: number, parent: Instance): Model
	local model = Parts.model("Environment", parent)
	local rng = Random.new(areaNumber * 7919)

	-- Big ground that reaches to the haze, so there's no void or Baseplate in view.
	Parts.block(Vector3.new(1000, 2, 1000), theme.groundColor, CFrame.new(origin + Vector3.new(0, GROUND_TOP - 1, 150)), model, {
		material = theme.groundMaterial,
		name = "Ground",
	})
	-- The arena the fight happens on (debris from defeated enemies lands on it).
	local arena = Parts.block(ARENA_SIZE, theme.arenaColor, CFrame.new(origin), model, {
		material = theme.arenaMaterial,
		name = "Arena",
	})
	arena.CanCollide = true
	-- Low border stones around the arena.
	local edgeColor = Parts.vary(theme.arenaColor, rng, 0.1)
	for _, side in { -1, 1 } do
		Parts.block(Vector3.new(ARENA_SIZE.X + 2, 0.8, 1), edgeColor, CFrame.new(origin + Vector3.new(0, 0.6, side * (ARENA_SIZE.Z / 2 + 0.5))), model, {
			material = Enum.Material.Slate,
		})
		Parts.block(Vector3.new(1, 0.8, ARENA_SIZE.Z), edgeColor, CFrame.new(origin + Vector3.new(side * (ARENA_SIZE.X / 2 + 0.5), 0.6, 0)), model, {
			material = Enum.Material.Slate,
		})
	end

	local set = SCENERY[theme.scenery] or SCENERY.Forest
	local quality = Quality.get()
	scatter(rng, origin, model, quality.props, set)
	mountains(rng, theme, origin, model, quality.mountains)
	ambientParticles(theme, origin, model)
	return model
end

-- Sky, haze and light for an area. Uses the place's Atmosphere if it has one.
function Environment.applyLighting(theme: Theme)
	Lighting.ClockTime = theme.clockTime
	local night = theme.clockTime < 6 or theme.clockTime > 19
	Lighting.OutdoorAmbient = if night then Color3.fromRGB(115, 105, 150) else Color3.fromRGB(128, 128, 128)
	Lighting.Ambient = if night then Color3.fromRGB(70, 60, 95) else Color3.fromRGB(70, 70, 70)

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere == nil then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	local haze = atmosphere :: Atmosphere
	haze.Density = theme.hazeDensity
	haze.Offset = 0.15
	haze.Color = theme.hazeColor
	haze.Decay = theme.hazeColor
	haze.Glare = 0
	haze.Haze = 1.5

	local tint = Lighting:FindFirstChild("AreaTint")
	if tint == nil then
		tint = Instance.new("ColorCorrectionEffect")
		tint.Name = "AreaTint"
		tint.Parent = Lighting
	end
	(tint :: ColorCorrectionEffect).TintColor = theme.tint
end

return table.freeze(Environment)
