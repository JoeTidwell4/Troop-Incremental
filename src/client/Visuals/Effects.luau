--!strict
-- One-shot visual effects on the battlefield: hit sparks, gold coin bursts, enemies
-- breaking into pieces, arrows with trails, and dust rings. Client only, cosmetic only.
-- Uses Roblox's built-in particle textures, so no uploaded assets are needed.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Parts = require(script.Parent.Parts)
local Quality = require(script.Parent.Quality)

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local folder: Folder? = nil
local emitterPart: Part? = nil
local emitters: { [string]: ParticleEmitter } = {}

local Effects = {}

local function makeEmitter(name: string, props: { [string]: any }): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Enabled = false
	emitter.Rate = 0
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = emitterPart
	emitters[name] = emitter
	return emitter
end

function Effects.init(parent: Instance)
	local newFolder = Instance.new("Folder")
	newFolder.Name = "Effects"
	newFolder.Parent = parent
	folder = newFolder

	emitterPart = Parts.block(Vector3.new(1, 1, 1), Color3.new(), CFrame.new(), newFolder, { transparency = 1, name = "FxEmitter" })

	makeEmitter("Sparks", {
		Texture = SPARKLE,
		Color = ColorSequence.new(Color3.fromRGB(255, 240, 180)),
		LightEmission = 1,
		Size = NumberSequence.new(0.6, 0),
		Lifetime = NumberRange.new(0.2, 0.35),
		Speed = NumberRange.new(12, 22),
		SpreadAngle = Vector2.new(180, 180),
	})
	makeEmitter("Coins", {
		Texture = SPARKLE,
		Color = ColorSequence.new(Color3.fromRGB(255, 205, 60)),
		LightEmission = 0.6,
		Size = NumberSequence.new(0.7, 0.3),
		Lifetime = NumberRange.new(0.6, 0.9),
		Speed = NumberRange.new(10, 16),
		SpreadAngle = Vector2.new(40, 40),
		Acceleration = Vector3.new(0, -35, 0),
		EmissionDirection = Enum.NormalId.Top,
	})
	makeEmitter("Dust", {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(200, 185, 160)),
		Size = NumberSequence.new(2, 5),
		Transparency = NumberSequence.new(0.5, 1),
		Lifetime = NumberRange.new(0.5, 0.8),
		Speed = NumberRange.new(14, 20),
		SpreadAngle = Vector2.new(5, 180),
		EmissionDirection = Enum.NormalId.Front,
	})
end

local function emitAt(name: string, position: Vector3, count: number)
	local part = emitterPart
	local emitter = emitters[name]
	if part == nil or emitter == nil then
		return
	end
	part.CFrame = CFrame.new(position)
	emitter:Emit(count)
end

function Effects.hitSparks(position: Vector3)
	emitAt("Sparks", position, 8)
end

function Effects.coinBurst(position: Vector3)
	emitAt("Coins", position, 10)
end

-- A ring of dust on the ground (boss slams).
function Effects.dustRing(position: Vector3)
	local part = emitterPart
	local emitter = emitters.Dust
	if part == nil or emitter == nil then
		return
	end
	-- Point the emitter outward in several directions around the ring.
	for i = 0, 5 do
		part.CFrame = CFrame.new(position) * CFrame.Angles(0, i / 6 * math.pi * 2, 0)
		emitter:Emit(3)
	end
end

-- Breaks a model into flying pieces that fade away. The model itself is left as is.
-- Low graphics scales the piece count down (to none).
function Effects.shatter(model: Model, maxPieces: number)
	local target = folder
	maxPieces = math.floor(maxPieces * Quality.get().debris)
	if target == nil or maxPieces <= 0 then
		return
	end
	local center = model:GetPivot().Position
	local count = 0
	for _, item in model:GetDescendants() do
		if count >= maxPieces then
			break
		end
		if item:IsA("BasePart") and item.Transparency < 1 then
			count += 1
			local piece = item:Clone()
			for _, child in piece:GetChildren() do
				child:Destroy()
			end
			piece.Anchored = false
			piece.CanCollide = true
			piece.Parent = target
			local away = (piece.Position - center) * Vector3.new(1, 0, 1)
			local outward = if away.Magnitude > 0.01 then away.Unit else Vector3.new(0, 0, 1)
			piece.AssemblyLinearVelocity = outward * math.random(8, 16) + Vector3.new(0, math.random(12, 22), 0)
			piece.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
			TweenService:Create(piece, TweenInfo.new(0.6, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.5), {
				Transparency = 1,
			}):Play()
			Debris:AddItem(piece, 1.2)
		end
	end
end

-- A round projectile (magic orb or catapult boulder) arcing from `from` to `to`.
function Effects.orb(from: Vector3, to: Vector3, color: Color3, diameter: number, duration: number, glowing: boolean, onHit: (() -> ())?)
	local target = folder
	if target == nil then
		return
	end
	local ball = Parts.ball(diameter, color, CFrame.new(from), target, {
		material = if glowing then Enum.Material.Neon else Enum.Material.Slate,
		name = "Projectile",
	})
	local progress = Instance.new("NumberValue")
	local peak = (to - from).Magnitude * (if glowing then 0.08 else 0.35)
	progress.Changed:Connect(function(t: number)
		ball.CFrame = CFrame.new(from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * peak, 0))
	end)
	local tween = TweenService:Create(progress, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Value = 1 })
	tween.Completed:Connect(function()
		ball:Destroy()
		progress:Destroy()
		if onHit ~= nil then
			onHit()
		end
	end)
	tween:Play()
end

-- An arrow (shaft + tip + glowing trail) flying from `from` to `to`.
function Effects.arrow(from: Vector3, to: Vector3, color: Color3, duration: number, onHit: (() -> ())?)
	local target = folder
	if target == nil then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Arrow"
	local shaft = Parts.block(Vector3.new(0.15, 0.15, 2.2), Color3.fromRGB(140, 100, 60), CFrame.lookAt(from, to), model)
	local tip = Parts.block(Vector3.new(0.3, 0.3, 0.5), color, shaft.CFrame * CFrame.new(0, 0, -1.3), model, {
		material = Enum.Material.Neon,
	})
	local _ = tip -- moves with the shaft via PivotTo
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.1, 1)
	a0.Parent = shaft
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.1, 1)
	a1.Parent = shaft
	local trail = Instance.new("Trail")
	trail.Enabled = Quality.get().trails
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(color)
	trail.LightEmission = 1
	trail.Lifetime = 0.15
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Parent = shaft
	model.PrimaryPart = shaft
	model.Parent = target

	-- Slight arc: rise then fall, done by tweening a number and placing the arrow each step.
	local progress = Instance.new("NumberValue")
	local peak = (to - from).Magnitude * 0.12
	local function place(t: number)
		local flat = from:Lerp(to, t)
		local height = math.sin(t * math.pi) * peak
		local ahead = from:Lerp(to, math.min(1, t + 0.05)) + Vector3.new(0, math.sin(math.min(1, t + 0.05) * math.pi) * peak, 0)
		local position = flat + Vector3.new(0, height, 0)
		if (ahead - position).Magnitude > 0.01 then
			model:PivotTo(CFrame.lookAt(position, ahead))
		end
	end
	progress.Changed:Connect(place)
	local tween = TweenService:Create(progress, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Value = 1 })
	tween.Completed:Connect(function()
		model:Destroy()
		progress:Destroy()
		if onHit ~= nil then
			onHit()
		end
	end)
	tween:Play()
end

return table.freeze(Effects)
