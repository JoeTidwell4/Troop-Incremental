--!strict
-- Builds the commander's worn gear (CommanderConfig items) onto the avatar: helmets on
-- the head, capes and back items on the torso. Client only, looks only (the bonuses are
-- applied on the server). Weapons restyle the existing sword instead (CommanderController).
-- While a helmet is on, the avatar's own hats and hair are hidden so they don't poke out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Parts = require(script.Parent.Parts)
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

type ItemDef = Types.CommanderItemDef

local CommanderGear = {}

local FOLDER_NAME = "CommanderGear"
local GOLD = Color3.fromRGB(255, 205, 70)
local NEON = { material = Enum.Material.Neon }

-- Parts are made anchored by Parts; worn gear must move with the avatar.
local function attach(parts: { BasePart }, to: BasePart)
	for _, part in parts do
		part.Anchored = false
		part.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = to
		weld.Part1 = part
		weld.Parent = part
	end
end

local function collect(model: Model): { BasePart }
	local list: { BasePart } = {}
	for _, item in model:GetChildren() do
		if item:IsA("BasePart") then
			table.insert(list, item)
		end
	end
	return list
end

---------------------------------------------------------------- helmets (on the head)

local function helmet(def: ItemDef, head: BasePart, into: Model)
	local s = head.Size.Y -- scale with the avatar's head
	local at = head.CFrame
	local color = def.color
	if def.style == "Cap" then
		Parts.ball(s * 1.1, color, at * CFrame.new(0, s * 0.25, 0), into, { material = Enum.Material.Fabric })
		Parts.block(Vector3.new(s * 1.05, s * 0.12, s * 0.5), color, at * CFrame.new(0, s * 0.15, -s * 0.6), into, { material = Enum.Material.Fabric }) -- brim
	elseif def.style == "Helm" then
		Parts.block(Vector3.new(s * 1.15, s * 0.9, s * 1.15), color, at * CFrame.new(0, s * 0.2, 0), into, { material = Enum.Material.Metal })
		Parts.block(Vector3.new(s * 0.15, s * 0.6, s * 0.1), color, at * CFrame.new(0, -s * 0.05, -s * 0.6), into, { material = Enum.Material.Metal }) -- nose guard
	elseif def.style == "Horned" then
		Parts.ball(s * 1.2, color, at * CFrame.new(0, s * 0.3, 0), into, { material = Enum.Material.Metal })
		for side = -1, 1, 2 do
			Parts.wedge(Vector3.new(s * 0.2, s * 0.8, s * 0.35), Color3.fromRGB(240, 230, 210), at * CFrame.new(side * s * 0.65, s * 0.75, 0) * CFrame.Angles(0, 0, side * math.rad(-25)), into)
		end
	elseif def.style == "Crown" then
		Parts.cylinder(s * 0.35, s * 1.05, color, at * CFrame.new(0, s * 0.6, 0), into, NEON)
		for i = 0, 4 do
			local angle = i / 5 * math.pi * 2
			Parts.wedge(Vector3.new(s * 0.18, s * 0.4, s * 0.2), color, at * CFrame.new(math.sin(angle) * s * 0.45, s * 0.95, math.cos(angle) * s * 0.45) * CFrame.Angles(0, angle, 0), into, NEON)
		end
	end
end

---------------------------------------------------------------- capes (on the back of the torso)

local function cape(def: ItemDef, torso: BasePart, into: Model)
	local w, h, d = torso.Size.X, torso.Size.Y, torso.Size.Z
	local back = torso.CFrame * CFrame.new(0, h / 2, d / 2 + 0.06) -- top of the back
	local length = h * (if def.style == "Mantle" or def.style == "Phoenix" then 2.4 else 2)
	local material = Enum.Material.Fabric
	Parts.block(
		Vector3.new(w * (if def.style == "Cloak" then 1.05 else 0.95), length, 0.1),
		def.color,
		back * CFrame.Angles(math.rad(8), 0, 0) * CFrame.new(0, -length / 2, 0),
		into,
		{ material = material }
	)
	if def.style == "Mantle" then
		Parts.block(Vector3.new(w * 1.25, h * 0.25, d * 1.2), Color3.fromRGB(245, 240, 230), torso.CFrame * CFrame.new(0, h * 0.45, 0), into, { material = Enum.Material.Fabric }) -- fur collar
	elseif def.style == "Phoenix" then
		Parts.block(Vector3.new(w * 0.95, 0.15, 0.12), GOLD, back * CFrame.Angles(math.rad(8), 0, 0) * CFrame.new(0, -length + 0.1, 0.01), into, NEON) -- glowing hem
	elseif def.style == "Cloak" then
		Parts.ball(d * 0.9, def.color, torso.CFrame * CFrame.new(0, h * 0.55, d * 0.3), into, { material = material }) -- hood down
	end
end

---------------------------------------------------------------- back items

local function backItem(def: ItemDef, torso: BasePart, into: Model)
	local h, d = torso.Size.Y, torso.Size.Z
	local back = torso.CFrame * CFrame.new(0, 0, d / 2 + 0.35)
	local color = def.color
	if def.style == "Quiver" then
		local tilt = back * CFrame.Angles(0, 0, math.rad(25))
		Parts.cylinder(h * 1.2, 0.5, color, tilt, into, { material = Enum.Material.Wood })
		for i = -1, 1 do
			Parts.block(Vector3.new(0.08, 0.5, 0.08), Color3.fromRGB(240, 240, 240), tilt * CFrame.new(i * 0.12, h * 0.7, 0), into) -- arrow fletching
		end
	elseif def.style == "Shield" then
		Parts.cylinderZ(0.2, h * 1.3, color, back, into, { material = Enum.Material.Metal })
		Parts.cylinderZ(0.25, h * 0.35, GOLD, back * CFrame.new(0, 0, 0.05), into, { material = Enum.Material.Metal }) -- boss
	elseif def.style == "Banner" then
		Parts.cylinder(h * 2.6, 0.15, Color3.fromRGB(90, 70, 50), back * CFrame.new(0, h * 0.8, 0), into, { material = Enum.Material.Wood })
		Parts.block(Vector3.new(h * 0.9, h * 0.7, 0.08), color, back * CFrame.new(h * 0.45, h * 1.75, 0), into, { material = Enum.Material.Fabric })
		Parts.ball(0.3, GOLD, back * CFrame.new(0, h * 2.1, 0), into, NEON)
	elseif def.style == "Wings" then
		for side = -1, 1, 2 do
			Parts.wedge(
				Vector3.new(0.12, h * 1.4, h * 1.1),
				color,
				back * CFrame.new(side * h * 0.55, h * 0.3, 0) * CFrame.Angles(0, side * math.rad(90), side * math.rad(-20)),
				into,
				NEON
			)
		end
	end
end

---------------------------------------------------------------- public

-- Hides (or shows again) the avatar's own hats and hair while a helmet is worn.
local function setHatsHidden(character: Model, hidden: boolean)
	for _, item in character:GetChildren() do
		if item:IsA("Accessory") then
			local kind = item.AccessoryType
			if kind == Enum.AccessoryType.Hat or kind == Enum.AccessoryType.Hair then
				for _, part in item:GetDescendants() do
					if part:IsA("BasePart") then
						part.LocalTransparencyModifier = if hidden then 1 else 0
					end
				end
			end
		end
	end
end

-- Rebuilds everything worn (except the weapon). `equipped`: slot -> item id or "".
function CommanderGear.apply(character: Model, equipped: { [string]: string }, items: { [string]: ItemDef })
	local old = character:FindFirstChild(FOLDER_NAME)
	if old ~= nil then
		old:Destroy()
	end
	local head = character:FindFirstChild("Head") :: BasePart?
	local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
	local folder = Instance.new("Model")
	folder.Name = FOLDER_NAME

	local function build(slot: string, anchor: BasePart?, builder: (ItemDef, BasePart, Model) -> ())
		local def = items[equipped[slot] or ""]
		if def == nil or anchor == nil then
			return
		end
		local piece = Instance.new("Model")
		piece.Name = slot
		builder(def, anchor, piece)
		attach(collect(piece), anchor)
		piece.Parent = folder
	end
	build("Helmet", head, helmet)
	build("Cape", torso, cape)
	build("Back", torso, backItem)
	folder.Parent = character
	setHatsHidden(character, items[equipped.Helmet or ""] ~= nil)
end

return CommanderGear
