--!strict
-- Fielded Generals on the battlefield (Phase 13c part 2). Cosmetic only, built from parts
-- like the troops, a bit bigger than a soldier: armor in their House color, a cape in
-- their rarity color, a weapon that matches their trait, a crown from Legendary up and a
-- glowing aura for the Mythic. Each stands beside a small standard in the House color.
-- Built at the origin with its front towards local -Z (Roblox's forward); the controller
-- pivots it to face the enemy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Parts = require(script.Parent.Parts)
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

type GeneralDef = Types.GeneralDef

local GeneralModels = {}

local SKIN = Color3.fromRGB(235, 200, 165)
local STEEL = Color3.fromRGB(190, 195, 205)
local WOOD = Color3.fromRGB(110, 75, 45)
local GOLD = Color3.fromRGB(255, 205, 70)
local SCALE = 1.35

local METAL = { material = Enum.Material.Metal }
local NEON = { material = Enum.Material.Neon }

-- The weapon fits what the General is known for.
local function weapon(def: GeneralDef, at: CFrame, model: Model, s: number)
	local troop = def.trait.troopId
	local hand = at * CFrame.new(1 * s, 1.4 * s, -0.35 * s)
	if troop == "Archer" then
		Parts.block(Vector3.new(0.14, 2.2, 0.14) * s, WOOD, hand, model, { material = Enum.Material.Wood })
		Parts.block(Vector3.new(0.04, 2, 0.04) * s, Color3.new(1, 1, 1), hand * CFrame.new(0, 0, -0.25 * s), model)
	elseif troop == "Mage" or def.trait.kind == "critChance" then
		Parts.cylinder(2.6 * s, 0.16 * s, WOOD, hand * CFrame.new(0, 0.4 * s, 0), model, { material = Enum.Material.Wood })
		Parts.ball(0.45 * s, def.trait.kind == "critChance" and Color3.fromRGB(255, 140, 40) or Color3.fromRGB(170, 110, 255), hand * CFrame.new(0, 1.8 * s, 0), model, NEON)
	elseif troop == "Cavalry" then
		Parts.cylinder(3.4 * s, 0.14 * s, WOOD, hand * CFrame.new(0, 0.6 * s, 0), model, { material = Enum.Material.Wood })
		Parts.wedge(Vector3.new(0.12, 0.5, 0.3) * s, STEEL, hand * CFrame.new(0, 2.5 * s, 0), model, METAL)
	elseif troop == "Siege" then
		Parts.cylinder(1.8 * s, 0.18 * s, WOOD, hand, model, { material = Enum.Material.Wood })
		Parts.block(Vector3.new(0.7, 0.45, 0.45) * s, STEEL, hand * CFrame.new(0, 0.95 * s, 0), model, METAL) -- hammer head
	elseif def.trait.kind == "goldenChance" then
		Parts.cylinderZ(0.15 * s, 0.6 * s, GOLD, hand * CFrame.new(0, 0.1 * s, 0), model, NEON) -- a gold coin
	else
		Parts.block(Vector3.new(0.18, 2.2, 0.08) * s, STEEL, hand * CFrame.new(0, 0.9 * s, 0), model, METAL) -- sword
		Parts.block(Vector3.new(0.6, 0.12, 0.12) * s, GOLD, hand * CFrame.new(0, -0.15 * s, 0), model)
	end
end

export type AttackStyle = "Arrow" | "Orb" | "Coin" | "Boulder" | "Melee" | "Lance"

-- How a General attacks (matches the weapon above).
function GeneralModels.attackStyle(def: GeneralDef): AttackStyle
	local troop = def.trait.troopId
	if troop == "Archer" then
		return "Arrow"
	elseif troop == "Mage" or def.trait.kind == "critChance" then
		return "Orb"
	elseif troop == "Cavalry" then
		return "Lance"
	elseif troop == "Siege" then
		return "Boulder"
	elseif def.trait.kind == "goldenChance" then
		return "Coin"
	end
	return "Melee"
end

-- Where projectiles leave from, relative to the General's feet (in front, weapon hand).
function GeneralModels.handOffset(): CFrame
	return CFrame.new(1 * SCALE, 2.3 * SCALE, -0.6 * SCALE)
end

-- Builds one General. `houseColor` / `rarityColor` from GeneralConfig.
function GeneralModels.build(def: GeneralDef, houseColor: Color3, rarityColor: Color3, parent: Instance): Model
	local model = Parts.model(`General_{def.id}`, parent)
	local s = SCALE
	local at = CFrame.new()
	local legendary = def.rarity == "Legendary" or def.rarity == "Mythic"

	-- Legs, body, arms, head.
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(0.5, 1.1, 0.55) * s, Color3.fromRGB(60, 50, 45), at * CFrame.new(side * 0.3 * s, 0.55 * s, 0), model)
		Parts.block(Vector3.new(0.42, 1.1, 0.48) * s, houseColor, at * CFrame.new(side * 0.9 * s, 1.75 * s, 0), model, METAL)
	end
	local torso = Parts.block(Vector3.new(1.4, 1.35, 0.8) * s, houseColor, at * CFrame.new(0, 1.78 * s, 0), model, { material = Enum.Material.Metal, name = "Torso" })
	model.PrimaryPart = torso
	Parts.block(Vector3.new(1.44, 0.2, 0.84) * s, GOLD, at * CFrame.new(0, 1.22 * s, 0), model) -- belt
	for side = -1, 1, 2 do
		Parts.ball(0.6 * s, STEEL, at * CFrame.new(side * 0.85 * s, 2.45 * s, 0), model, METAL) -- shoulder plates
	end
	Parts.ball(0.85 * s, SKIN, at * CFrame.new(0, 2.95 * s, 0), model, { name = "Head" })

	-- Cape in the rarity color (behind them: local +Z).
	Parts.block(Vector3.new(1.3, 2.1, 0.08) * s, rarityColor, at * CFrame.new(0, 1.6 * s, 0.46 * s) * CFrame.Angles(math.rad(-6), 0, 0), model, { material = Enum.Material.Fabric })

	-- Crown from Legendary up.
	if legendary then
		Parts.cylinder(0.25 * s, 0.75 * s, GOLD, at * CFrame.new(0, 3.42 * s, 0), model, METAL)
		for i = 0, 3 do
			local angle = i / 4 * math.pi * 2
			Parts.wedge(Vector3.new(0.12, 0.25, 0.14) * s, GOLD, at * CFrame.new(math.sin(angle) * 0.32 * s, 3.62 * s, math.cos(angle) * 0.32 * s) * CFrame.Angles(0, angle, 0), model, METAL)
		end
	else
		Parts.block(Vector3.new(0.9, 0.3, 0.9) * s, STEEL, at * CFrame.new(0, 3.32 * s, 0), model, METAL) -- helm
	end

	weapon(def, at, model, s)

	-- Mythic: a soft glow.
	if def.rarity == "Mythic" then
		local light = Instance.new("PointLight")
		light.Color = rarityColor
		light.Range = 12
		light.Brightness = 1.5
		light.Parent = torso
		Parts.cylinder(0.08, 2.6 * s, rarityColor, at * CFrame.new(0, 0.05, 0), model, { material = Enum.Material.Neon, transparency = 0.4 }) -- ring on the ground
	end

	-- The pivot is the torso by default (it's the PrimaryPart), which put the feet ~2.4
	-- studs underground. Move it to the feet (the model's origin) so PivotTo places it on
	-- the ground.
	torso.PivotOffset = torso.CFrame:Inverse()

	-- A small standard in the House color beside them.
	local pole = at * CFrame.new(-1.6 * s, 0, 0.4 * s)
	Parts.cylinder(4.2 * s, 0.14 * s, WOOD, pole * CFrame.new(0, 2.1 * s, 0), model, { material = Enum.Material.Wood })
	Parts.block(Vector3.new(0.06, 1.1, 0.9) * s, houseColor, pole * CFrame.new(0, 3.6 * s, -0.45 * s), model, { material = Enum.Material.Fabric })
	Parts.ball(0.25 * s, GOLD, pole * CFrame.new(0, 4.3 * s, 0), model, METAL)

	return model
end

return GeneralModels
