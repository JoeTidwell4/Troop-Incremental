--!strict
-- Your clan's banner on your battlefield: a pole with a flag in the clan color showing the
-- emblem and tag. Higher clan levels add decorations (ClanConfig.BANNER_LEVELS): a gold
-- finial, pennants, a glowing trim, sparkles, and finally a crown. Client only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Parts = require(script.Parent.Parts)
local Quality = require(script.Parent.Quality)
local ClanConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ClanConfig"))

export type Info = { color: Color3, emblem: string, tag: string, level: number }

local POLE_HEIGHT = 14
local FLAG_SIZE = Vector3.new(5.5, 3.8, 0.15)
local GOLD = Color3.fromRGB(255, 205, 70)

local ClanBanner = {}

-- Writes the emblem and tag on one face of the flag.
local function decorate(flag: BasePart, face: Enum.NormalId, info: Info)
	local surface = Instance.new("SurfaceGui")
	surface.Face = face
	surface.CanvasSize = Vector2.new(220, 150)
	surface.LightInfluence = 0
	surface.Parent = flag
	local emblem = Instance.new("TextLabel")
	emblem.BackgroundTransparency = 1
	emblem.Size = UDim2.new(1, 0, 0.7, 0)
	emblem.Text = info.emblem
	emblem.TextScaled = true
	emblem.Font = Enum.Font.GothamBold
	emblem.Parent = surface
	local tag = Instance.new("TextLabel")
	tag.BackgroundTransparency = 1
	tag.Position = UDim2.new(0, 0, 0.68, 0)
	tag.Size = UDim2.new(1, 0, 0.3, 0)
	tag.Text = `[{info.tag}]`
	tag.TextScaled = true
	tag.Font = Enum.Font.FredokaOne
	tag.TextColor3 = Color3.new(1, 1, 1)
	tag.TextStrokeTransparency = 0.3
	tag.Parent = surface
end

-- Builds the banner standing at `at` (its foot). Returns (model, flag part, flag hinge):
-- the controller sways the flag around the hinge.
function ClanBanner.build(parent: Instance, at: CFrame, info: Info): (Model, BasePart, CFrame)
	local model = Parts.model("ClanBanner", parent)
	local levels = ClanConfig.BANNER_LEVELS
	Parts.block(Vector3.new(2.4, 0.8, 2.4), Color3.fromRGB(110, 110, 115), at * CFrame.new(0, 0.4, 0), model, { material = Enum.Material.Slate })
	Parts.cylinder(POLE_HEIGHT, 0.35, Color3.fromRGB(95, 70, 45), at * CFrame.new(0, POLE_HEIGHT / 2 + 0.8, 0), model, { material = Enum.Material.Wood })
	local top = at * CFrame.new(0, POLE_HEIGHT + 0.8, 0)

	-- The flag hangs off the pole to the right (+X), just below the top.
	local hinge = top * CFrame.new(0.2, -FLAG_SIZE.Y / 2 - 0.3, 0)
	local flag = Parts.block(FLAG_SIZE, info.color, hinge * CFrame.new(FLAG_SIZE.X / 2, 0, 0), model, {
		material = Enum.Material.Fabric,
		name = "Flag",
	})
	decorate(flag, Enum.NormalId.Front, info)
	decorate(flag, Enum.NormalId.Back, info)

	if info.level >= levels.glow then
		-- Glowing gold trim around the flag (welded so it sways with it).
		for _, edge in {
			{ size = Vector3.new(FLAG_SIZE.X, 0.18, 0.2), offset = Vector3.new(0, FLAG_SIZE.Y / 2, 0) },
			{ size = Vector3.new(FLAG_SIZE.X, 0.18, 0.2), offset = Vector3.new(0, -FLAG_SIZE.Y / 2, 0) },
			{ size = Vector3.new(0.18, FLAG_SIZE.Y, 0.2), offset = Vector3.new(FLAG_SIZE.X / 2, 0, 0) },
		} do
			local trim = Parts.block(edge.size, GOLD, flag.CFrame * CFrame.new(edge.offset), model, { material = Enum.Material.Neon })
			trim.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = flag
			weld.Part1 = trim
			weld.Parent = trim
		end
	end
	if info.level >= levels.pennants then
		for i = 1, 2 do
			Parts.wedge(Vector3.new(0.1, 1.4, 1.2), GOLD, at * CFrame.new(0.3, POLE_HEIGHT * 0.45 - i * 1.6, 0) * CFrame.Angles(0, math.rad(90), math.rad(90)), model, {
				material = Enum.Material.Fabric,
			})
		end
	end
	if info.level >= levels.crown then
		Parts.cylinder(0.4, 1.3, GOLD, top * CFrame.new(0, 0.3, 0), model, { material = Enum.Material.Neon })
		for i = 0, 4 do
			local angle = i / 5 * math.pi * 2
			Parts.wedge(Vector3.new(0.25, 0.6, 0.3), GOLD, top * CFrame.new(math.sin(angle) * 0.5, 0.8, math.cos(angle) * 0.5) * CFrame.Angles(0, angle, 0), model, {
				material = Enum.Material.Neon,
			})
		end
	elseif info.level >= levels.finial then
		Parts.ball(0.9, GOLD, top * CFrame.new(0, 0.3, 0), model, { material = Enum.Material.Neon })
	end
	if info.level >= levels.sparkles and Quality.get().particleRate >= 1 then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(GOLD)
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new(0.4, 0)
		emitter.Rate = 8
		emitter.Lifetime = NumberRange.new(1, 1.6)
		emitter.Speed = NumberRange.new(0.5, 1.5)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Parent = flag
	end
	return model, flag, hinge
end

return ClanBanner
