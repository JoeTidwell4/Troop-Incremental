--!strict
-- Shared bits for the creature builders in this folder (see Visuals/EnemyModels).
-- A builder makes a creature at `at` (its feet), facing -Z (toward your troops), in the
-- theme's `color`, and returns its height in studs (before scaling).

local Parts = require(script.Parent.Parent.Parts)

export type Builder = (model: Model, at: CFrame, color: Color3) -> number

local Common = {}

Common.BODY = { name = "Body" } :: Parts.Options -- parts in the creature's main color

-- Eyes facing -Z: a dark socket behind, the glowing iris, and a small white glint so they
-- read as eyes from across the arena.
function Common.eyes(model: Model, at: CFrame, y: number, spacing: number, z: number, size: number, color: Color3)
	for side = -1, 1, 2 do
		local center = at * CFrame.new(side * spacing, y, z)
		Parts.ball(size * 1.35, Color3.fromRGB(20, 15, 25), center * CFrame.new(0, 0, size * 0.25), model) -- socket
		Parts.ball(size, color, center, model, { material = Enum.Material.Neon })
		Parts.ball(size * 0.32, Color3.new(1, 1, 1), center * CFrame.new(side * -0.12 * size, size * 0.2, -size * 0.36), model, { material = Enum.Material.Neon }) -- glint
	end
end

-- The color a little darker / lighter (bellies, shells, stripes).
function Common.shade(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + amount, 0, 1))
end

return table.freeze(Common)
