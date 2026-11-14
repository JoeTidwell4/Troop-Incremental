--!strict
-- Troop models built from parts. Each faces +Z (toward the enemy) and its pivot is at its
-- feet.
--
-- Looks by tier: every troop type has 4 looks, picked by how many you own
-- (VisualConfig.TROOP_TIERS, the damage milestones 25 / 100 / 300): 1 = recruit,
-- 2 = shoulder armor and better kit, 3 = cape / plume / heavier armor, 4 = gold trim
-- and glowing accents. Low graphics (profile `troopDetail` false) skips the small
-- decorative bits (boots, hands, fletching, trims) to keep the part count down.
--
-- Gear shows on the models: parts tagged as "weapon" or "armor" take their slot's rarity
-- color once it's above Common, and glow from Epic up. Call TroopModels.applyGear again
-- whenever gear changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Parts = require(script.Parent.Parts)
local Quality = require(script.Parent.Quality)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local GearInfo = require(Shared:WaitForChild("GearInfo"))
local VisualConfig = require(Shared:WaitForChild("Config"):WaitForChild("VisualConfig"))

type TroopGear = Types.TroopGear

local SKIN = Color3.fromRGB(235, 200, 160)
local PANTS = Color3.fromRGB(60, 55, 70)
local BOOT = Color3.fromRGB(70, 48, 32)
local STEEL = Color3.fromRGB(175, 180, 190)
local DARK_STEEL = Color3.fromRGB(110, 115, 125)
local CHAIN = Color3.fromRGB(135, 140, 150)
local WOOD = Color3.fromRGB(120, 85, 55)
local LEATHER = Color3.fromRGB(110, 75, 45)
local GOLD = Color3.fromRGB(240, 195, 70)
local EYE = Color3.fromRGB(30, 25, 30)
local WHITE = Color3.fromRGB(240, 240, 240)

local METAL = { material = Enum.Material.Metal }
local FABRIC = { material = Enum.Material.Fabric }
local WOODEN = { material = Enum.Material.Wood }
local GLOW = { material = Enum.Material.Neon }

type Ctx = {
	model: Model,
	at: CFrame,
	color: Color3,
	tier: number,
	detail: boolean,
}

local TroopModels = {}

local function shade(color: Color3, factor: number): Color3
	return Color3.new(math.clamp(color.R * factor, 0, 1), math.clamp(color.G * factor, 0, 1), math.clamp(color.B * factor, 0, 1))
end

-- Marks a part as gear so applyGear can recolor it, remembering its normal look.
local function gear(part: BasePart, slot: "weapon" | "armor"): BasePart
	part:SetAttribute("GearSlot", slot)
	part:SetAttribute("BaseColor", part.Color)
	part:SetAttribute("BaseMaterial", part.Material.Name)
	return part
end

-- Two dark eyes on the front of a head centred at `y` (head diameter `size`).
local function eyes(c: Ctx, y: number, size: number)
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(0.11, 0.17, 0.05) * (size / 0.95), EYE, c.at * CFrame.new(side * 0.17 * size / 0.95, y, size * 0.48), c.model)
	end
end

-- Shared humanoid body. `s` scales it; `robe` replaces the legs with a long robe.
-- Returns the y of the head centre.
local function body(c: Ctx, tunic: Color3, s: number, robe: boolean?): number
	local m, at = c.model, c.at
	if robe then
		Parts.block(Vector3.new(1.35, 1.25, 0.85) * s, tunic, at * CFrame.new(0, 0.62 * s, 0), m, FABRIC)
		Parts.block(Vector3.new(1.5, 0.25, 0.95) * s, shade(tunic, 0.7), at * CFrame.new(0, 0.12 * s, 0), m, FABRIC) -- hem
	else
		for side = -1, 1, 2 do
			Parts.block(Vector3.new(0.5, 0.85, 0.5) * s, PANTS, at * CFrame.new(side * 0.3 * s, 0.75 * s, 0), m)
			if c.detail then
				Parts.block(Vector3.new(0.56, 0.4, 0.72) * s, BOOT, at * CFrame.new(side * 0.3 * s, 0.2 * s, 0.08 * s), m)
			else
				Parts.block(Vector3.new(0.5, 0.35, 0.5) * s, BOOT, at * CFrame.new(side * 0.3 * s, 0.18 * s, 0), m)
			end
		end
	end
	-- Torso, belt, arms, hands, head, eyes.
	Parts.block(Vector3.new(1.3, 1.3, 0.75) * s, tunic, at * CFrame.new(0, 1.75 * s, 0), m, { name = "Torso" })
	Parts.block(Vector3.new(1.34, 0.22, 0.8) * s, LEATHER, at * CFrame.new(0, 1.18 * s, 0), m)
	if c.detail then
		Parts.block(Vector3.new(0.26, 0.2, 0.06) * s, GOLD, at * CFrame.new(0, 1.18 * s, 0.41 * s), m, METAL) -- buckle
	end
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(0.4, 1.0, 0.45) * s, tunic, at * CFrame.new(side * 0.86 * s, 1.85 * s, 0), m)
		if c.detail then
			Parts.ball(0.42 * s, SKIN, at * CFrame.new(side * 0.86 * s, 1.25 * s, 0.05 * s), m)
		end
	end
	local headY = 2.9 * s
	Parts.ball(0.95 * s, SKIN, at * CFrame.new(0, headY, 0), m, { name = "Head" })
	if c.detail then -- (the camera sees the army from behind; faces show in side views)
		eyes(c, headY - 0.02 * s, 0.95 * s)
	end
	return headY
end

-- Rounded shoulder plates (tier 2+).
local function pauldrons(c: Ctx, s: number, color: Color3, y: number?)
	for side = -1, 1, 2 do
		gear(Parts.ball(0.62 * s, color, c.at * CFrame.new(side * 0.86 * s, (y or 2.38) * s, 0), c.model, METAL), "armor")
	end
end

-- A cape hanging down the back (tier 3+), gold hem at tier 4.
local function cape(c: Ctx, s: number, color: Color3, top: number?)
	local topY = (top or 2.4) * s
	local length = 1.8 * s
	local cf = c.at * CFrame.new(0, topY - length / 2, -0.47 * s) * CFrame.Angles(math.rad(-8), 0, 0)
	Parts.block(Vector3.new(1.25 * s, length, 0.08 * s), color, cf, c.model, FABRIC)
	if c.tier >= 4 and c.detail then
		Parts.block(Vector3.new(1.27 * s, 0.14 * s, 0.1 * s), GOLD, cf * CFrame.new(0, -length / 2 + 0.07 * s, 0), c.model, METAL)
	end
end

---------------------------------------------------------------- Swordsman

local function swordsman(c: Ctx)
	local m, at, tier = c.model, c.at, c.tier
	local headY = body(c, c.color, 1)
	-- Helmet: a cap on the top half of the head, rounded on top.
	gear(Parts.cylinder(0.42, 1.04, STEEL, at * CFrame.new(0, headY + 0.25, 0), m, METAL), "armor")
	gear(Parts.ball(0.96, STEEL, at * CFrame.new(0, headY + 0.36, 0), m, METAL), "armor")
	if tier >= 2 then
		Parts.block(Vector3.new(0.1, 0.42, 0.08), STEEL, at * CFrame.new(0, headY - 0.02, 0.49), m, METAL) -- nose guard
		pauldrons(c, 1, STEEL)
	end
	if tier >= 3 then
		Parts.block(Vector3.new(1.38, 0.38, 0.82), CHAIN, at * CFrame.new(0, 1.0, 0), m, METAL) -- mail skirt
		Parts.block(Vector3.new(0.16, 0.5, 0.8), c.color, at * CFrame.new(0, headY + 0.85, -0.05), m, FABRIC) -- plume
		if c.detail then
			cape(c, 1, shade(c.color, 0.7))
		end
	end
	if tier >= 4 and c.detail then
		Parts.cylinder(0.12, 1.08, GOLD, at * CFrame.new(0, headY + 0.06, 0), m, METAL) -- helmet rim
	end
	-- Sword in the right hand, angled forward and up.
	local hand = at * CFrame.new(0.86, 1.25, 0.15) * CFrame.Angles(math.rad(-30), 0, 0)
	local bladeLength = if tier >= 3 then 2.0 else 1.6
	gear(Parts.block(Vector3.new(0.1, 0.3, bladeLength), STEEL, hand * CFrame.new(0, 0, 0.3 + bladeLength / 2), m, METAL), "weapon")
	if tier >= 4 then
		Parts.block(Vector3.new(0.04, 0.12, bladeLength * 0.9), Color3.fromRGB(255, 230, 150), hand * CFrame.new(0, 0, 0.3 + bladeLength / 2), m, GLOW) -- glowing edge
	end
	Parts.block(Vector3.new(0.7, 0.12, 0.14), if tier >= 4 then GOLD else LEATHER, hand * CFrame.new(0, 0, 0.25), m, METAL) -- crossguard
	if c.detail then
		Parts.block(Vector3.new(0.13, 0.13, 0.4), LEATHER, hand * CFrame.new(0, 0, 0), m) -- grip
		Parts.ball(0.2, if tier >= 4 then GOLD else STEEL, hand * CFrame.new(0, 0, -0.22), m, METAL) -- pommel
	end
	-- Shield on the left arm, facing forward (the emblem pokes through both faces so the
	-- camera behind the army sees it): round first, a steel heater shield from tier 3.
	local shieldAt = at * CFrame.new(-1.0, 1.75, 0.45)
	if tier >= 3 then
		gear(Parts.block(Vector3.new(1.15, 1.3, 0.2), STEEL, shieldAt, m, METAL), "armor")
		gear(Parts.block(Vector3.new(0.82, 0.82, 0.2), STEEL, shieldAt * CFrame.new(0, -0.62, 0) * CFrame.Angles(0, 0, math.rad(45)), m, METAL), "armor")
		Parts.block(Vector3.new(0.45, 0.95, 0.24), c.color, shieldAt * CFrame.new(0, -0.05, 0), m) -- emblem
		Parts.block(Vector3.new(0.95, 0.25, 0.24), c.color, shieldAt * CFrame.new(0, 0.15, 0), m)
		if tier >= 4 and c.detail then
			Parts.block(Vector3.new(1.2, 0.12, 0.26), GOLD, shieldAt * CFrame.new(0, 0.62, 0), m, METAL)
		end
	else
		gear(Parts.cylinderZ(0.2, 1.35, if tier >= 2 then STEEL else WOOD, shieldAt, m, if tier >= 2 then METAL else WOODEN), "armor")
		Parts.cylinderZ(0.24, 0.75, c.color, shieldAt, m)
		Parts.ball(0.3, STEEL, shieldAt * CFrame.new(0, 0, 0.12), m, METAL) -- boss
	end
end

---------------------------------------------------------------- Archer

local function archer(c: Ctx)
	local m, at, tier = c.model, c.at, c.tier
	local s = 0.95
	local hoodColor = if tier >= 3 then shade(c.color, 0.55) else Color3.fromRGB(70, 100, 60)
	local headY = body(c, c.color, s)
	-- Hood: cap + a fold hanging behind the head + a point.
	gear(Parts.cylinder(0.4, 1.02 * s, hoodColor, at * CFrame.new(0, headY + 0.24, 0), m, FABRIC), "armor")
	gear(Parts.ball(1.0 * s, hoodColor, at * CFrame.new(0, headY + 0.05, -0.18), m, FABRIC), "armor")
	Parts.wedge(Vector3.new(0.3, 0.5, 0.6), hoodColor, at * CFrame.new(0, headY + 0.35, -0.65) * CFrame.Angles(math.rad(-20), 0, 0), m, FABRIC)
	if tier >= 2 then
		for side = -1, 1, 2 do
			gear(Parts.block(Vector3.new(0.46, 0.4, 0.5) * s, LEATHER, at * CFrame.new(side * 0.86 * s, 1.5 * s, 0), m), "armor") -- bracers
		end
	end
	if tier >= 3 and c.detail then
		cape(c, s, hoodColor, 2.45)
		Parts.block(Vector3.new(0.05, 0.6, 0.18), Color3.fromRGB(230, 60, 50), at * CFrame.new(0.45, headY + 0.4, -0.2) * CFrame.Angles(math.rad(-25), 0, 0), m) -- feather
	end
	if tier >= 4 then
		Parts.cylinder(0.1, 1.06 * s, GOLD, at * CFrame.new(0, headY + 0.1, 0), m, METAL) -- circlet
		Parts.ball(0.16, Color3.fromRGB(120, 255, 170), at * CFrame.new(0, headY + 0.12, 0.5), m, GLOW) -- gem
	end
	-- Bow held out in the left hand: five slats in an arc, a string and a nocked arrow.
	local bowAt = at * CFrame.new(-0.9, 1.9, 0.55)
	local size = if tier >= 3 then 1.2 else 1.0
	local bowColor = if tier >= 4 then GOLD else WOOD
	local bowOptions = if tier >= 4 then METAL else WOODEN
	gear(Parts.block(Vector3.new(0.14, 0.7 * size, 0.14), bowColor, bowAt, m, bowOptions), "weapon")
	for side = -1, 1, 2 do
		gear(Parts.block(Vector3.new(0.13, 0.7 * size, 0.13), bowColor, bowAt * CFrame.new(0, side * 0.62 * size, -0.12) * CFrame.Angles(math.rad(-side * 22), 0, 0), m, bowOptions), "weapon")
		gear(Parts.block(Vector3.new(0.12, 0.6 * size, 0.12), bowColor, bowAt * CFrame.new(0, side * 1.15 * size, -0.38) * CFrame.Angles(math.rad(-side * 45), 0, 0), m, bowOptions), "weapon")
	end
	Parts.block(Vector3.new(0.04, 2.7 * size, 0.04), WHITE, bowAt * CFrame.new(0, 0, -0.62 * size), m, if tier >= 4 then GLOW else nil) -- string
	if c.detail then
		Parts.block(Vector3.new(0.06, 0.06, 1.3), WOOD, bowAt * CFrame.new(0.05, 0, -0.05), m) -- arrow
		Parts.block(Vector3.new(0.12, 0.12, 0.2), if tier >= 4 then Color3.fromRGB(120, 255, 170) else STEEL, bowAt * CFrame.new(0.05, 0, 0.65), m, if tier >= 4 then GLOW else METAL)
	end
	-- Quiver on the back with fletchings.
	local quiver = at * CFrame.new(0.3, 2.0, -0.5) * CFrame.Angles(0, 0, math.rad(-20))
	Parts.cylinder(1.4, 0.45, if tier >= 4 then shade(c.color, 0.6) else LEATHER, quiver, m)
	if c.detail then
		for i = -1, 1 do
			Parts.block(Vector3.new(0.08, 0.35, 0.18), WHITE, quiver * CFrame.new(i * 0.1, 0.85, 0), m)
		end
	end
end

---------------------------------------------------------------- Knight

local function knight(c: Ctx)
	local m, at, tier = c.model, c.at, c.tier
	local s = 1.25
	body(c, STEEL, s)
	-- Breastplate, tabard, gauntlets.
	gear(Parts.block(Vector3.new(1.42, 1.38, 0.86) * s, STEEL, at * CFrame.new(0, 1.78 * s, 0), m, METAL), "armor")
	Parts.block(Vector3.new(0.65, 1.3, 0.05) * s, c.color, at * CFrame.new(0, 1.6 * s, 0.45 * s), m, FABRIC)
	pauldrons(c, s, if tier >= 4 then GOLD else STEEL, 2.4)
	-- Great helm with a visor slit (glowing at tier 4) and a plume.
	gear(Parts.block(Vector3.new(1.05, 1.1, 1.05) * s, STEEL, at * CFrame.new(0, 2.95 * s, 0), m, METAL), "armor")
	Parts.block(Vector3.new(0.8, 0.12, 0.05) * s, if tier >= 4 then Color3.fromRGB(120, 200, 255) else Color3.fromRGB(30, 30, 35), at * CFrame.new(0, 3.02 * s, 0.53 * s), m, if tier >= 4 then GLOW else nil)
	if c.detail then
		Parts.block(Vector3.new(0.08, 0.5, 0.05) * s, DARK_STEEL, at * CFrame.new(0, 2.72 * s, 0.53 * s), m, METAL) -- breathing slit
	end
	Parts.block(Vector3.new(0.18, if tier >= 3 then 0.8 else 0.55, 1.0) * s, c.color, at * CFrame.new(0, 3.8 * s, -0.1), m, FABRIC)
	if tier >= 2 then
		Parts.block(Vector3.new(1.48, 0.42, 0.9) * s, CHAIN, at * CFrame.new(0, 1.0 * s, 0), m, METAL) -- mail skirt
	end
	if tier >= 3 then
		if c.detail then
			cape(c, s, shade(c.color, 0.75), 2.5)
		end
		for side = -1, 1, 2 do -- helm wings
			Parts.wedge(Vector3.new(0.1, 0.7, 0.6) * s, if tier >= 4 then GOLD else STEEL, at * CFrame.new(side * 0.58 * s, 3.25 * s, -0.1) * CFrame.Angles(0, 0, math.rad(side * -15)), m, METAL)
		end
	end
	if tier >= 4 and c.detail then
		Parts.block(Vector3.new(1.44, 0.1, 0.88) * s, GOLD, at * CFrame.new(0, 2.4 * s, 0), m, METAL) -- collar trim
		Parts.block(Vector3.new(1.07, 0.1, 1.07) * s, GOLD, at * CFrame.new(0, 2.45 * s, 0), m, METAL) -- helm trim
	end
	-- Lance and tower shield.
	gear(Parts.cylinderZ(3.6, 0.22, WOOD, at * CFrame.new(1.1 * s, 1.6 * s, 1.4), m, WOODEN), "weapon")
	gear(Parts.wedge(Vector3.new(0.35, 0.35, 0.9), STEEL, at * CFrame.new(1.1 * s, 1.6 * s, 3.6), m, METAL), "weapon")
	Parts.cylinderZ(0.3, 0.5, if tier >= 4 then GOLD else DARK_STEEL, at * CFrame.new(1.1 * s, 1.6 * s, 0.1), m, METAL) -- hand guard
	if tier >= 2 and c.detail then
		Parts.block(Vector3.new(0.04, 0.5, 0.6), c.color, at * CFrame.new(1.1 * s, 1.95 * s, 2.4), m, FABRIC) -- pennant
	end
	-- Tower shield facing forward (cross on both faces).
	local shieldAt = at * CFrame.new(-1.2 * s, 1.75 * s, 0.7)
	gear(Parts.block(Vector3.new(1.3, 1.9, 0.25) * s, STEEL, shieldAt, m, METAL), "armor")
	Parts.block(Vector3.new(0.3, 1.5, 0.3) * s, c.color, shieldAt, m)
	Parts.block(Vector3.new(1.0, 0.3, 0.3) * s, c.color, shieldAt * CFrame.new(0, 0.25, 0), m) -- cross
	if tier >= 4 and c.detail then
		Parts.block(Vector3.new(1.35, 0.12, 0.32) * s, GOLD, shieldAt * CFrame.new(0, 1.15, 0), m, METAL)
		Parts.block(Vector3.new(1.35, 0.12, 0.32) * s, GOLD, shieldAt * CFrame.new(0, -1.15, 0), m, METAL)
	end
end

---------------------------------------------------------------- Mage

local function mage(c: Ctx)
	local m, at, tier = c.model, c.at, c.tier
	local s = 0.95
	local robe = if tier >= 3 then shade(c.color, 0.8) else c.color
	local headY = body(c, robe, s, true)
	-- Beard.
	Parts.block(Vector3.new(0.55, 0.5, 0.2), WHITE, at * CFrame.new(0, headY - 0.42, 0.38), m, FABRIC)
	if c.detail then
		Parts.wedge(Vector3.new(0.5, 0.35, 0.2), WHITE, at * CFrame.new(0, headY - 0.85, 0.38) * CFrame.Angles(math.pi, math.pi, 0), m, FABRIC)
	end
	-- Pointed hat: brim + stacked shrinking discs with a bent tip.
	local hatColor = if tier >= 2 then shade(c.color, 0.55) else Color3.fromRGB(70, 50, 100)
	gear(Parts.cylinder(0.14, 1.65, hatColor, at * CFrame.new(0, headY + 0.32, 0), m, FABRIC), "armor")
	for i = 0, 3 do
		Parts.cylinder(0.36, 1.05 - i * 0.24, hatColor, at * CFrame.new(0, headY + 0.55 + i * 0.32, -i * 0.05) * CFrame.Angles(math.rad(-7 * i), 0, 0), m, FABRIC)
	end
	if tier >= 2 then
		Parts.cylinder(0.12, 1.08, GOLD, at * CFrame.new(0, headY + 0.45, 0), m, METAL) -- hat band
		-- Mantle over the shoulders.
		gear(Parts.block(Vector3.new(1.6, 0.35, 0.95) * s, hatColor, at * CFrame.new(0, 2.35 * s, 0), m, FABRIC), "armor")
	end
	if tier >= 3 and c.detail then
		cape(c, s, hatColor, 2.45)
	end
	if tier >= 4 and c.detail then
		Parts.block(Vector3.new(1.52, 0.12, 0.97) * s, GOLD, at * CFrame.new(0, 0.26 * s, 0), m, METAL) -- robe trim
		Parts.ball(0.25, GOLD, at * CFrame.new(0, headY + 1.75, -0.25), m, GLOW) -- star on the hat tip
	end
	-- Staff with a glowing orb (caged from tier 3, bigger at tier 4).
	gear(Parts.cylinder(3.6, 0.2, if tier >= 4 then GOLD else WOOD, at * CFrame.new(0.9, 1.9, 0.3), m, if tier >= 4 then METAL else WOODEN), "weapon")
	local orbAt = at * CFrame.new(0.9, 3.85, 0.3)
	Parts.ball(if tier >= 4 then 0.75 else 0.6, Color3.fromRGB(190, 140, 255), orbAt, m, { material = Enum.Material.Neon, name = "Orb" })
	if tier >= 3 then
		for i = 0, 2 do
			Parts.block(Vector3.new(0.08, 0.9, 0.08), if tier >= 4 then GOLD else DARK_STEEL, orbAt * CFrame.Angles(0, i * math.pi / 3, 0) * CFrame.new(0.38, 0, 0), m, METAL)
		end
	end
	if tier >= 2 and c.detail then
		-- A spellbook on the belt.
		Parts.block(Vector3.new(0.4, 0.5, 0.15), Color3.fromRGB(110, 40, 40), at * CFrame.new(-0.6, 1.0, 0.4), m)
	end
end

---------------------------------------------------------------- Cavalry

local function cavalry(c: Ctx)
	local m, at, tier = c.model, c.at, c.tier
	local horse = Color3.fromRGB(120, 85, 60)
	local mane = Color3.fromRGB(55, 38, 28)
	-- Horse: rounded body, legs with hooves, neck, head with ears, mane, tail.
	Parts.block(Vector3.new(1.5, 1.3, 2.6), horse, at * CFrame.new(0, 2.15, -0.1), m)
	Parts.ball(1.55, horse, at * CFrame.new(0, 2.15, 1.15), m) -- chest
	Parts.ball(1.5, horse, at * CFrame.new(0, 2.2, -1.3), m) -- rump
	for _, offset in { Vector3.new(-0.45, 0.75, 1.15), Vector3.new(0.45, 0.75, 1.15), Vector3.new(-0.45, 0.75, -1.25), Vector3.new(0.45, 0.75, -1.25) } do
		Parts.block(Vector3.new(0.38, 1.3, 0.4), horse, at * CFrame.new(offset), m)
		if c.detail then
			Parts.block(Vector3.new(0.44, 0.22, 0.46), mane, at * CFrame.new(offset.X, 0.11, offset.Z + 0.03), m) -- hoof
		end
	end
	Parts.block(Vector3.new(0.75, 1.5, 0.85), horse, at * CFrame.new(0, 3.05, 1.65) * CFrame.Angles(math.rad(30), 0, 0), m) -- neck
	local head = at * CFrame.new(0, 3.65, 2.3) * CFrame.Angles(math.rad(-15), 0, 0)
	Parts.block(Vector3.new(0.7, 0.7, 1.3), horse, head, m)
	Parts.block(Vector3.new(0.6, 0.55, 0.4), shade(horse, 0.8), head * CFrame.new(0, -0.08, 0.75), m) -- muzzle
	if c.detail then
		for side = -1, 1, 2 do
			Parts.block(Vector3.new(0.08, 0.13, 0.05), EYE, head * CFrame.new(side * 0.36, 0.12, 0.25), m)
			Parts.wedge(Vector3.new(0.15, 0.35, 0.2), horse, head * CFrame.new(side * 0.22, 0.5, -0.4), m) -- ears
		end
	end
	Parts.block(Vector3.new(0.18, 1.4, 0.5), mane, at * CFrame.new(0, 3.35, 1.45) * CFrame.Angles(math.rad(30), 0, 0), m) -- mane
	Parts.block(Vector3.new(0.25, 1.2, 0.3), mane, at * CFrame.new(0, 2.0, -2.05) * CFrame.Angles(math.rad(-25), 0, 0), m) -- tail
	-- Barding (cloth from tier 2, steel head armor from tier 3, gold trim at tier 4).
	gear(Parts.block(Vector3.new(1.62, 0.25, 1.5), c.color, at * CFrame.new(0, 2.85, -0.1), m, FABRIC), "armor") -- saddle cloth
	if tier >= 2 then
		for side = -1, 1, 2 do
			Parts.block(Vector3.new(0.06, 0.9, 2.4), c.color, at * CFrame.new(side * 0.79, 2.15, -0.1), m, FABRIC)
		end
	end
	if tier >= 3 then
		gear(Parts.block(Vector3.new(0.74, 0.5, 1.05), STEEL, head * CFrame.new(0, 0.18, 0.1), m, METAL), "armor") -- chanfron
	end
	if tier >= 4 and c.detail then
		for side = -1, 1, 2 do
			Parts.block(Vector3.new(0.08, 0.12, 2.42), GOLD, at * CFrame.new(side * 0.8, 1.72, -0.1), m, METAL)
		end
		Parts.block(Vector3.new(0.14, 0.5, 0.5), GOLD, head * CFrame.new(0, 0.6, -0.1), m, METAL) -- horse plume base
	end
	-- Rider.
	Parts.block(Vector3.new(1.1, 1.2, 0.7), c.color, at * CFrame.new(0, 3.65, -0.1), m, { name = "Torso" })
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(0.35, 0.9, 0.4), c.color, at * CFrame.new(side * 0.72, 3.7, -0.1), m)
		Parts.block(Vector3.new(0.38, 0.4, 0.9), PANTS, at * CFrame.new(side * 0.6, 3.0, 0), m) -- thighs over the horse
	end
	Parts.ball(0.85, SKIN, at * CFrame.new(0, 4.65, -0.1), m, { name = "Head" })
	if c.detail then
		for side = -1, 1, 2 do
			Parts.block(Vector3.new(0.1, 0.15, 0.05), EYE, at * CFrame.new(side * 0.15, 4.63, 0.31), m)
		end
	end
	gear(Parts.cylinder(0.38, 0.92, STEEL, at * CFrame.new(0, 4.88, -0.1), m, METAL), "armor") -- helmet
	gear(Parts.ball(0.86, STEEL, at * CFrame.new(0, 4.98, -0.1), m, METAL), "armor")
	if tier >= 2 then
		pauldrons(c, 0.8, STEEL, 4.65)
	end
	if tier >= 3 then
		Parts.block(Vector3.new(0.14, 0.5, 0.7), c.color, at * CFrame.new(0, 5.45, -0.2), m, FABRIC) -- plume
		if c.detail then
			Parts.block(Vector3.new(1.0, 1.5, 0.08), shade(c.color, 0.7), at * CFrame.new(0, 3.5, -0.55) * CFrame.Angles(math.rad(-15), 0, 0), m, FABRIC) -- cape
		end
	end
	-- Spear (gold-tipped at tier 4).
	gear(Parts.cylinderZ(4.4, 0.18, WOOD, at * CFrame.new(0.75, 3.5, 1.4), m, WOODEN), "weapon")
	gear(Parts.wedge(Vector3.new(0.25, 0.5, 0.75), if tier >= 4 then GOLD else STEEL, at * CFrame.new(0.75, 3.5, 3.95), m, METAL), "weapon")
end

---------------------------------------------------------------- Siege

local function siege(c: Ctx)
	local m, at, tier = c.model, c.at, c.tier
	local timber = Color3.fromRGB(125, 90, 55)
	local planks = { material = Enum.Material.WoodPlanks }
	local fittings = if tier >= 4 then GOLD else DARK_STEEL
	-- Base frame (two rails + cross beams) and four wheels with hubs.
	for side = -1, 1, 2 do
		Parts.block(Vector3.new(0.5, 0.5, 4.8), timber, at * CFrame.new(side * 1.3, 1.25, 0), m, planks)
	end
	for _, z in { -1.8, 0, 1.8 } do
		Parts.block(Vector3.new(3.1, 0.4, 0.45), timber, at * CFrame.new(0, 1.25, z), m, planks)
	end
	for _, x in { -1.75, 1.75 } do
		for _, z in { -1.6, 1.6 } do
			local wheel = at * CFrame.new(x, 0.85, z) * CFrame.Angles(0, 0, math.rad(90))
			Parts.cylinder(0.35, 1.7, Color3.fromRGB(80, 60, 40), wheel, m, planks)
			Parts.cylinder(0.42, 0.5, fittings, wheel, m, METAL)
		end
	end
	-- Uprights with a crossbar, the axle.
	for _, x in { -1.0, 1.0 } do
		Parts.block(Vector3.new(0.4, 2.8, 0.4), timber, at * CFrame.new(x, 2.75, 0), m, planks)
		if tier >= 2 then
			Parts.block(Vector3.new(0.46, 0.15, 0.46), fittings, at * CFrame.new(x, 2.0, 0), m, METAL) -- iron bands
			Parts.block(Vector3.new(0.46, 0.15, 0.46), fittings, at * CFrame.new(x, 3.4, 0), m, METAL)
		end
	end
	Parts.block(Vector3.new(2.4, 0.35, 0.35), timber, at * CFrame.new(0, 4.25, 0), m, planks)
	Parts.cylinder(2.3, 0.3, fittings, at * CFrame.new(0, 3.6, 0) * CFrame.Angles(0, 0, math.rad(90)), m, METAL)
	-- Throwing arm with a bucket and a boulder (flaming at tier 4), counterweight box.
	local arm = at * CFrame.new(0, 3.9, -0.4) * CFrame.Angles(math.rad(-25), 0, 0)
	gear(Parts.block(Vector3.new(0.42, 0.42, 5), timber, arm, m, planks), "weapon")
	Parts.block(Vector3.new(1.0, 0.3, 1.0), timber, arm * CFrame.new(0, 0.3, -2.3), m, planks) -- bucket
	local boulder = if tier >= 4 then Color3.fromRGB(255, 120, 40) else Color3.fromRGB(110, 105, 100)
	Parts.ball(1.1, boulder, at * CFrame.new(0, 5.2, -2.6), m, { material = if tier >= 4 then Enum.Material.Neon else Enum.Material.Slate, name = "Boulder" })
	gear(Parts.block(Vector3.new(1.4, 1.2, 1.2), c.color, at * CFrame.new(0, 3.3, 1.7), m, METAL), "armor")
	if c.detail then
		Parts.block(Vector3.new(1.46, 0.15, 1.26), fittings, at * CFrame.new(0, 3.75, 1.7), m, METAL)
		Parts.block(Vector3.new(0.05, 1.5, 0.05), Color3.fromRGB(200, 180, 140), at * CFrame.new(0, 3.1, 0.9) * CFrame.Angles(math.rad(35), 0, 0), m) -- rope
	end
	-- War banner on the back (tier 3+), crowned at tier 4.
	if tier >= 3 then
		Parts.block(Vector3.new(0.15, 4.2, 0.15), timber, at * CFrame.new(1.3, 3.35, -2.3), m, planks)
		Parts.block(Vector3.new(0.06, 1.2, 1.3), c.color, at * CFrame.new(1.3, 4.7, -1.6), m, FABRIC)
		if tier >= 4 then
			Parts.ball(0.35, GOLD, at * CFrame.new(1.3, 5.55, -2.3), m, METAL)
		end
	end
end

local BUILDERS: { [string]: (Ctx) -> () } = {
	Swordsman = swordsman,
	Archer = archer,
	Knight = knight,
	Mage = mage,
	Cavalry = cavalry,
	Siege = siege,
}

-- Which look (1-4) a troop type has with `count` owned.
function TroopModels.tierFor(count: number): number
	local tier = 1
	for _, threshold in VisualConfig.TROOP_TIERS do
		if count >= threshold then
			tier += 1
		end
	end
	return tier
end

-- Builds one troop at `home` (feet position, facing +Z). `tier` 1-4 (default 1).
function TroopModels.build(troopId: string, color: Color3, home: CFrame, parent: Instance, tier: number?): Model
	local model = Instance.new("Model")
	model.Name = troopId
	local root = Parts.block(Vector3.new(0.2, 0.2, 0.2), Color3.new(), home, model, { transparency = 1, name = "Root" })
	model.PrimaryPart = root
	local builder = BUILDERS[troopId] or swordsman
	builder({
		model = model,
		at = home,
		color = color,
		tier = math.clamp(tier or 1, 1, 4),
		detail = Quality.get().troopDetail,
	})
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
