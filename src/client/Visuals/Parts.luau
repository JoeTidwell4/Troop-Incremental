--!strict
-- Tiny helpers for building low-poly models out of plain Parts. Every part made here is
-- anchored and doesn't collide, block clicks, or fire touch events (it's all decoration).
-- Cylinders are stood upright for you (Roblox cylinders lie along X by default).

local Parts = {}

export type Options = {
	material: Enum.Material?,
	transparency: number?,
	shadow: boolean?, -- cast shadows (default false: cheaper, fine for small things)
	name: string?,
}

local function base(className: string, size: Vector3, color: Color3, cframe: CFrame, parent: Instance, options: Options?): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = if options ~= nil and options.name ~= nil then options.name else className
	part.Size = size
	part.Color = color
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = options ~= nil and options.shadow == true
	part.Material = if options ~= nil and options.material ~= nil then options.material else Enum.Material.SmoothPlastic
	part.Transparency = if options ~= nil and options.transparency ~= nil then options.transparency else 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function Parts.block(size: Vector3, color: Color3, cframe: CFrame, parent: Instance, options: Options?): Part
	return base("Part", size, color, cframe, parent, options) :: Part
end

function Parts.ball(diameter: number, color: Color3, cframe: CFrame, parent: Instance, options: Options?): Part
	local part = base("Part", Vector3.one * diameter, color, cframe, parent, options) :: Part
	part.Shape = Enum.PartType.Ball
	return part
end

-- Upright cylinder centred on `cframe`.
function Parts.cylinder(height: number, diameter: number, color: Color3, cframe: CFrame, parent: Instance, options: Options?): Part
	local part = base("Part", Vector3.new(height, diameter, diameter), color, cframe * CFrame.Angles(0, 0, math.rad(90)), parent, options) :: Part
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Cylinder lying along the cframe's Z axis (handy for disks facing forward, lances, logs).
function Parts.cylinderZ(length: number, diameter: number, color: Color3, cframe: CFrame, parent: Instance, options: Options?): Part
	local part = base("Part", Vector3.new(length, diameter, diameter), color, cframe * CFrame.Angles(0, math.rad(90), 0), parent, options) :: Part
	part.Shape = Enum.PartType.Cylinder
	return part
end

function Parts.wedge(size: Vector3, color: Color3, cframe: CFrame, parent: Instance, options: Options?): WedgePart
	return base("WedgePart", size, color, cframe, parent, options) :: WedgePart
end

-- A triangular ridge (two wedges back to back): a cheap mountain or roof shape.
-- A WedgePart's tall flat face is on its back (+Z) side and it slopes down toward its
-- front (-Z), so the +Z half is turned around to put both tall faces in the middle.
function Parts.ridge(width: number, height: number, depth: number, color: Color3, cframe: CFrame, parent: Instance, options: Options?)
	local half = depth / 2
	Parts.wedge(
		Vector3.new(width, height, half),
		color,
		cframe * CFrame.new(0, height / 2, half / 2) * CFrame.Angles(0, math.pi, 0),
		parent,
		options
	)
	Parts.wedge(Vector3.new(width, height, half), color, cframe * CFrame.new(0, height / 2, -half / 2), parent, options)
end

function Parts.model(name: string, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

-- Slightly varied copy of a color, so repeated props don't look stamped.
function Parts.vary(color: Color3, rng: Random, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.clamp(s + rng:NextNumber(-amount, amount), 0, 1), math.clamp(v + rng:NextNumber(-amount, amount), 0, 1))
end

return table.freeze(Parts)
