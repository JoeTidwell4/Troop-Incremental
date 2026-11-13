--!strict
-- Shared bits for the creature builders in this folder (see Visuals/EnemyModels).
-- A builder makes a creature at `at` (its feet), facing -Z (toward your troops), in the
-- theme's `color`, and returns its height in studs (before scaling).

local Parts = require(script.Parent.Parent.Parts)

export type Builder = (model: Model, at: CFrame, color: Color3) -> number

local Common = {}

Common.BODY = { name = "Body" } :: Parts.Options -- parts in the creature's main color

function Common.eyes(model: Model, at: CFrame, y: number, spacing: number, z: number, size: number, color: Color3)
	for side = -1, 1, 2 do
		Parts.ball(size, color, at * CFrame.new(side * spacing, y, z), model, { material = Enum.Material.Neon })
	end
end

-- The color a little darker / lighter (bellies, shells, stripes).
function Common.shade(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + amount, 0, 1))
end

return table.freeze(Common)
