--!strict
-- Low-poly troop models built from parts. Each faces +Z (toward the enemy) and its pivot
-- is at its feet.
--
-- Gear shows on the models: parts tagged as "weapon" or "armor" take their slot's rarity
-- color once it's above Common, and glow from Epic up. Call TroopModels.applyGear again
-- whenever gear changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Parts = require(script.Parent.Parts)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local GearInfo = require(Shared:WaitForChild("GearInfo"))

type TroopGear = Types.TroopGear

local SKIN = Color3.fromRGB(235, 200, 160)
local PANTS = Color3.fromRGB(60, 55, 70)
local STEEL = Color3.fromRGB(175, 180, 190)
local WOOD = Color3.fromRGB(120, 85, 55)
local LEATHER = Color3.fromRGB(110, 75, 45)

local TroopModels = {}

-- Marks a part as gear so applyGear can recolor it, remembering its normal look.
local function gear(part: BasePart, slot: "weapon" | "armor"): BasePart
	part:SetAttribute("GearSlot", slot)
	part:SetAttribute("BaseColor", part.Color)
	part:SetAttribute("BaseMaterial", part.Material.Name)
	return part
end

-- Shared body: legs, torso, arms, head. Returns the torso so callers can add to it.
local function body(model: Model, at: CFrame, tunic: Color3, scale: number)
	local s = scale
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(0.5, 1.1, 0.55) * s, PANTS, at * CFrame.new(side * 0.3 * s, 0.55 * s, 0), model)
		Parts.block(Vector3.new(0.4, 1.1, 0.45) * s, tunic, at * CFrame.new(side * 0.88 * s, 1.75 * s, 0), model)
	end
	Parts.block(Vector3.new(1.3, 1.3, 0.75) * s, tunic, at * CFrame.new(0, 1.75 * s, 0), model, { name = "Torso" })
	Parts.block(Vector3.new(1.34, 0.2, 0.79) * s, LEATHER, at * CFrame.new(0, 1.2 * s, 0), model) -- belt
	Parts.ball(0.95 * s, SKIN, at * CFrame.new(0, 2.9 * s, 0), model, { name = "Head" })
end

local function swordsman(model: Model, at: CFrame, color: Color3)
	body(model, at, color, 1)
	gear(Parts.ball(1.02, STEEL, at * CFrame.new(0, 3.02, -0.03), model, { material = Enum.Material.Metal }), "armor") -- helmet
	gear(Parts.block(Vector3.new(0.2, 0.2, 1.7), STEEL, at * CFrame.new(0.88, 1.25, 0.95), model, { material = Enum.Material.Metal }), "weapon")
	Parts.block(Vector3.new(0.6, 0.15, 0.15), LEATHER, at * CFrame.new(0.88, 1.25, 0.15), model) -- crossguard
	gear(Parts.cylinderZ(0.2, 1.3, STEEL, at * CFrame.new(-0.95, 1.7, 0.35), model, { material = Enum.Material.Metal }), "armor") -- shield
	Parts.cylinderZ(0.22, 0.6, color, at * CFrame.new(-0.95, 1.7, 0.36), model) -- shield emblem
end

local function archer(model: Model, at: CFrame, color: Color3)
	body(model, at, color, 0.95)
	gear(Parts.ball(1.05, Color3.fromRGB(60, 95, 55), at * CFrame.new(0, 2.85, -0.1), model, { material = Enum.Material.Fabric }), "armor") -- hood
	-- Bow: three slats making an arc, held out to the left.
	local bowAt = at * CFrame.new(-0.9, 1.9, 0.55)
	gear(Parts.block(Vector3.new(0.14, 1, 0.14), WOOD, bowAt, model, { material = Enum.Material.Wood }), "weapon")
	gear(Parts.block(Vector3.new(0.14, 0.9, 0.14), WOOD, bowAt * CFrame.new(0, 0.8, -0.2) * CFrame.Angles(math.rad(-30), 0, 0), model, { material = Enum.Material.Wood }), "weapon")
	gear(Parts.block(Vector3.new(0.14, 0.9, 0.14), WOOD, bowAt * CFrame.new(0, -0.8, -0.2) * CFrame.Angles(math.rad(30), 0, 0), model, { material = Enum.Material.Wood }), "weapon")
	Parts.block(Vector3.new(0.04, 2.2, 0.04), Color3.fromRGB(240, 240, 240), bowAt * CFrame.new(0, 0, -0.42), model) -- string
	Parts.cylinder(1.4, 0.45, LEATHER, at * CFrame.new(0.3, 2, -0.5) * CFrame.Angles(0, 0, math.rad(-20)), model) -- quiver
end

local function knight(model: Model, at: CFrame, color: Color3)
	local s = 1.25
	body(model, at, STEEL, s)
	local metal = { material = Enum.Material.Metal }
	gear(Parts.block(Vector3.new(1.4, 1.4, 0.85) * s, STEEL, at * CFrame.new(0, 1.75 * s, 0), model, metal), "armor") -- breastplate
	Parts.block(Vector3.new(0.6, 1.2, 0.05) * s, color, at * CFrame.new(0, 1.75 * s, 0.44 * s), model) -- tabard
	gear(Parts.block(Vector3.new(1.05, 1.1, 1.05) * s, STEEL, at * CFrame.new(0, 2.95 * s, 0), model, metal), "armor") -- helm
	Parts.block(Vector3.new(0.8, 0.12, 0.05) * s, Color3.fromRGB(30, 30, 35), at * CFrame.new(0, 3.0 * s, 0.53 * s), model) -- visor slit
	Parts.block(Vector3.new(0.18, 0.6, 0.9) * s, color, at * CFrame.new(0, 3.75 * s, -0.1), model) -- plume
	gear(Parts.cylinderZ(3.6, 0.22, WOOD, at * CFrame.new(1.1 * s, 1.6 * s, 1.4), model, { material = Enum.Material.Wood }), "weapon") -- lance
	gear(Parts.ball(0.4, STEEL, at * CFrame.new(1.1 * s, 1.6 * s, 3.2), model, metal), "weapon") -- lance tip
	gear(Parts.block(Vector3.new(0.25, 1.9, 1.4) * s, STEEL, at * CFrame.new(-1.15 * s, 1.75 * s, 0.3), model, metal), "armor") -- tower shield
	Parts.block(Vector3.new(0.27, 0.8, 0.5) * s, color, at * CFrame.new(-1.16 * s, 1.85 * s, 0.3), model) -- shield crest
end

local function mage(model: Model, at: CFrame, color: Color3)
	body(model, at, color, 0.95)
	-- Long robe over the legs.
	Parts.block(Vector3.new(1.35, 1.2, 0.8), color, at * CFrame.new(0, 0.6, 0), model, { material = Enum.Material.Fabric })
	-- Pointed hat: stacked shrinking discs.
	for i = 0, 3 do
		Parts.cylinder(0.35, 1.4 - i * 0.32, color, at * CFrame.new(0, 3.25 + i * 0.32, 0) * CFrame.Angles(math.rad(-6 * i), 0, 0), model, {
			material = Enum.Material.Fabric,
		})
	end
	gear(Parts.cylinder(1.6, 1.6, Color3.fromRGB(70, 50, 100), at * CFrame.new(0, 3.2, 0), model, { material = Enum.Material.Fabric }), "armor") -- hat brim
	gear(Parts.cylinder(3.6, 0.2, WOOD, at * CFrame.new(0.9, 1.9, 0.3), model, { material = Enum.Material.Wood }), "weapon") -- staff
	Parts.ball(0.6, Color3.fromRGB(190, 140, 255), at * CFrame.new(0.9, 3.85, 0.3), model, { material = Enum.Material.Neon, name = "Orb" })
end

local function cavalry(model: Model, at: CFrame, color: Color3)
	local horse = Color3.fromRGB(120, 85, 60)
	-- Horse: body, legs, neck, head, tail.
	Parts.block(Vector3.new(1.5, 1.4, 3.2), horse, at * CFrame.new(0, 2.1, 0), model)
	for _, offset in { Vector3.new(-0.5, 0.7, 1.2), Vector3.new(0.5, 0.7, 1.2), Vector3.new(-0.5, 0.7, -1.2), Vector3.new(0.5, 0.7, -1.2) } do
		Parts.block(Vector3.new(0.4, 1.4, 0.4), horse, at * CFrame.new(offset), model)
	end
	Parts.block(Vector3.new(0.8, 1.4, 0.8), horse, at * CFrame.new(0, 3, 1.6) * CFrame.Angles(math.rad(30), 0, 0), model)
	Parts.block(Vector3.new(0.75, 0.75, 1.3), horse, at * CFrame.new(0, 3.6, 2.2), model)
	Parts.block(Vector3.new(0.25, 1.1, 0.25), Color3.fromRGB(60, 40, 30), at * CFrame.new(0, 2.4, -1.75) * CFrame.Angles(math.rad(-30), 0, 0), model)
	gear(Parts.block(Vector3.new(1.6, 0.25, 1.4), color, at * CFrame.new(0, 2.9, 0), model, { material = Enum.Material.Fabric }), "armor") -- saddle cloth
	-- Rider (upper body only, sitting on the horse).
	Parts.block(Vector3.new(1.1, 1.2, 0.7), color, at * CFrame.new(0, 3.65, -0.1), model)
	Parts.ball(0.85, SKIN, at * CFrame.new(0, 4.65, -0.1), model)
	gear(Parts.ball(0.92, STEEL, at * CFrame.new(0, 4.75, -0.12), model, { material = Enum.Material.Metal }), "armor") -- helmet
	gear(Parts.cylinderZ(4.2, 0.18, WOOD, at * CFrame.new(0.75, 3.5, 1.3), model, { material = Enum.Material.Wood }), "weapon") -- spear
	gear(Parts.wedge(Vector3.new(0.25, 0.5, 0.7), STEEL, at * CFrame.new(0.75, 3.5, 3.6), model, { material = Enum.Material.Metal }), "weapon")
end

local function siege(model: Model, at: CFrame, color: Color3)
	local timber = Color3.fromRGB(125, 90, 55)
	local wood = { material = Enum.Material.WoodPlanks }
	-- Base frame and wheels.
	Parts.block(Vector3.new(3.2, 0.6, 4.6), timber, at * CFrame.new(0, 1.2, 0), model, wood)
	for _, x in { -1.75, 1.75 } do
		for _, z in { -1.5, 1.5 } do
			Parts.cylinder(0.4, 1.6, Color3.fromRGB(80, 60, 40), at * CFrame.new(x, 0.8, z) * CFrame.Angles(0, 0, math.rad(90)), model, wood)
		end
		Parts.block(Vector3.new(0.4, 2.6, 0.4), timber, at * CFrame.new(x * 0.7, 2.6, 0), model, wood) -- uprights
	end
	Parts.cylinder(2.6, 0.35, timber, at * CFrame.new(0, 3.6, 0) * CFrame.Angles(0, 0, math.rad(90)), model, wood) -- axle
	-- Throwing arm with a counterweight and a loaded boulder.
	gear(Parts.block(Vector3.new(0.45, 0.45, 5), timber, at * CFrame.new(0, 3.9, -0.4) * CFrame.Angles(math.rad(-25), 0, 0), model, wood), "weapon")
	gear(Parts.block(Vector3.new(1.4, 1.2, 1.2), color, at * CFrame.new(0, 3.3, 1.7), model, { material = Enum.Material.Metal }), "armor")
	Parts.ball(1.1, Color3.fromRGB(110, 105, 100), at * CFrame.new(0, 5.2, -2.6), model, { material = Enum.Material.Slate, name = "Boulder" })
end

local BUILDERS: { [string]: (Model, CFrame, Color3) -> () } = {
	Swordsman = swordsman,
	Archer = archer,
	Knight = knight,
	Mage = mage,
	Cavalry = cavalry,
	Siege = siege,
}

-- Builds one troop at `home` (feet position, facing +Z).
function TroopModels.build(troopId: string, color: Color3, home: CFrame, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = troopId
	local root = Parts.block(Vector3.new(0.2, 0.2, 0.2), Color3.new(), home, model, { transparency = 1, name = "Root" })
	model.PrimaryPart = root
	local builder = BUILDERS[troopId] or swordsman
	builder(model, home, color)
	model.Parent = parent
	return model
end

-- Recolors a troop's gear to match its rarities (Common = normal look).
function TroopModels.applyGear(model: Model, troopGear: TroopGear?)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local slot = part:GetAttribute("GearSlot")
			if slot ~= nil then
				local state = if troopGear == nil then nil elseif slot == "weapon" then troopGear.weapon else troopGear.armor
				local rarity = if state ~= nil then state.rarity else 1
				if rarity <= 1 then
					part.Color = part:GetAttribute("BaseColor") :: Color3
					part.Material = (Enum.Material :: any)[part:GetAttribute("BaseMaterial") :: string]
				else
					part.Color = GearInfo.rarity(rarity).color
					part.Material = if rarity >= 4 then Enum.Material.Neon else Enum.Material.Metal
				end
			end
		end
	end
end

return table.freeze(TroopModels)
