--!strict
-- The commander's Legacy aura: a soft glow and rising sparks in the Legacy rank's color
-- (LegacyConfig.RANKS). Client only, looks only. More particles at higher ranks; Low
-- graphics keeps just the glow.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Formulas"))
local Quality = require(script.Parent.Quality)

local LegacyAura = {}

local NAME = "LegacyAura"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

-- Puts the right aura on the character for `count` Legacies (removes it at 0).
function LegacyAura.apply(character: Model, count: number)
	local root = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
	if root == nil then
		return
	end
	local old = root:FindFirstChild(NAME)
	if old ~= nil then
		old:Destroy()
	end
	local rank = Formulas.legacyRank(count)
	if rank == nil then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = NAME

	local light = Instance.new("PointLight")
	light.Color = rank.color
	light.Range = 10
	light.Brightness = 1.2
	light.Parent = folder

	if Quality.get().particleRate >= 1 then
		local sparks = Instance.new("ParticleEmitter")
		sparks.Texture = SPARK
		sparks.Color = ColorSequence.new(rank.color)
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		sparks.Lifetime = NumberRange.new(1, 1.6)
		sparks.Speed = NumberRange.new(1, 2.5)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Acceleration = Vector3.new(0, 2, 0)
		sparks.Rate = 6 + math.min(count, 20) -- busier as the rank goes up
		sparks.Parent = folder
	end
	folder.Parent = root
end

return LegacyAura
