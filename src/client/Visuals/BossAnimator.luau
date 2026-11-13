--!strict
-- Boss and raid boss animations (client only, cosmetic). The enemy models are solid
-- part-built pieces, so every move is the whole model leaning, jumping, spinning and
-- squashing around its feet, plus effects (shockwaves, portals, smoke, loot).
--
-- BattlefieldController owns the model and calls:
--   BossAnimator.setTarget(height)        a new boss/raid model appeared
--   BossAnimator.play(name, callbacks?)   start a move ("Entrance", "Rise", "Stomp", "Sweep",
--                                         "Projectile", "Flinch", "Roar", "ShieldCast", "Sink")
--   BossAnimator.sample(now)              each frame: (offset from home, scale multiplier)
-- One move plays at a time; a new move replaces the current one, except that the
-- entrance can't be interrupted. Moves can fire callbacks at a point in their timeline
-- (e.g. "impact" when a stomp lands) so the controller can add effects and shake.

local BossAnimator = {}

export type Callbacks = { [string]: () -> () }

type Move = {
	duration: number,
	pose: (t: number, height: number) -> (CFrame, number),
	events: { { at: number, name: string } }?,
	locked: boolean?, -- can't be interrupted
}

local function easeOut(t: number): number
	return 1 - (1 - t) ^ 3
end

local function easeIn(t: number): number
	return t ^ 3
end

-- 0 -> 1 -> 0 over t.
local function bump(t: number): number
	return math.sin(math.clamp(t, 0, 1) * math.pi)
end

-- t mapped into [from, to] -> [0, 1], clamped.
local function span(t: number, from: number, to: number): number
	return math.clamp((t - from) / (to - from), 0, 1)
end

local MOVES: { [string]: Move } = {
	-- Drops from the sky, lands with a squash, then roars.
	Entrance = {
		duration = 1.6,
		locked = true,
		events = { { at = 0.3, name = "land" }, { at = 0.55, name = "roar" } },
		pose = function(t: number, height: number): (CFrame, number)
			if t < 0.3 then
				local fall = easeIn(t / 0.3)
				return CFrame.new(0, (1 - fall) * height * 6, 0), 1
			end
			local squash = bump(span(t, 0.3, 0.45)) * 0.12
			local roar = bump(span(t, 0.55, 0.95))
			return CFrame.new(0, 0, roar * 0.4) * CFrame.Angles(math.rad(-14) * roar, 0, 0), 1 - squash + roar * 0.08
		end,
	},
	-- Raid boss: climbs up out of the ground.
	Rise = {
		duration = 1.4,
		locked = true,
		events = { { at = 0.05, name = "rumble" }, { at = 0.85, name = "roar" } },
		pose = function(t: number, height: number): (CFrame, number)
			local up = easeOut(span(t, 0, 0.8))
			local shake = (1 - up) * math.sin(t * 90) * 0.3
			return CFrame.new(shake, (up - 1) * height * 1.1, 0), 1
		end,
	},
	-- Jumps and slams the ground.
	Stomp = {
		duration = 0.85,
		events = { { at = 0.55, name = "impact" } },
		pose = function(t: number, height: number): (CFrame, number)
			if t < 0.25 then
				local crouch = bump(t / 0.5) * 0.1 -- dips down before jumping
				return CFrame.new(0, 0, 0), 1 - crouch
			elseif t < 0.55 then
				local air = span(t, 0.25, 0.55)
				local y = math.sin(air * math.pi) * height * 0.35 -- up and back down
				return CFrame.new(0, y, -air * 1.5), 1.02
			end
			local land = span(t, 0.55, 1)
			local squash = bump(math.min(1, land * 2.5)) * 0.14
			return CFrame.new(0, 0, -1.5 * (1 - land)), 1 - squash
		end,
	},
	-- Winds up turned away, then swings across.
	Sweep = {
		duration = 0.8,
		events = { { at = 0.5, name = "impact" } },
		pose = function(t: number, _height: number): (CFrame, number)
			local wind = easeOut(span(t, 0, 0.4))
			local swing = easeIn(span(t, 0.4, 0.55))
			local back = span(t, 0.55, 1)
			local yaw = math.rad(35) * wind - math.rad(70) * swing + math.rad(35) * back
			local lunge = bump(span(t, 0.4, 0.8)) * 2.5
			return CFrame.new(0, 0, -lunge) * CFrame.Angles(0, yaw, 0), 1
		end,
	},
	-- Leans back, then throws forward (the controller launches the projectile).
	Projectile = {
		duration = 0.75,
		events = { { at = 0.45, name = "throw" } },
		pose = function(t: number, _height: number): (CFrame, number)
			local lean = easeOut(span(t, 0, 0.4)) * (1 - span(t, 0.45, 0.6))
			local snap = bump(span(t, 0.45, 0.75))
			local pitch = math.rad(-18) * lean + math.rad(14) * snap
			return CFrame.Angles(pitch, 0, 0), 1 + snap * 0.05
		end,
	},
	-- Knocked back by a weak point hit.
	Flinch = {
		duration = 0.35,
		pose = function(t: number, _height: number): (CFrame, number)
			local hit = bump(t)
			return CFrame.new(0, 0, hit * 1.2) * CFrame.Angles(math.rad(-12) * hit, 0, math.rad(6) * hit), 1 - hit * 0.05
		end,
	},
	-- Rears back and roars (enrage, raid phase change).
	Roar = {
		duration = 0.9,
		events = { { at = 0.3, name = "roar" } },
		pose = function(t: number, _height: number): (CFrame, number)
			local rear = bump(t)
			local tremble = math.sin(t * 70) * 0.02 * rear
			return CFrame.Angles(math.rad(-16) * rear, 0, tremble), 1 + rear * 0.12
		end,
	},
	-- Rises a little and spins while the shield forms.
	ShieldCast = {
		duration = 0.6,
		events = { { at = 0.15, name = "cast" } },
		pose = function(t: number, _height: number): (CFrame, number)
			return CFrame.new(0, bump(t) * 1.5, 0) * CFrame.Angles(0, easeOut(t) * math.pi * 2, 0), 1
		end,
	},
	-- Raid boss: sinks back into the ground when the attack ends.
	Sink = {
		duration = 1,
		locked = true,
		pose = function(t: number, height: number): (CFrame, number)
			return CFrame.new(math.sin(t * 80) * 0.2, -easeIn(t) * height * 1.2, 0), 1
		end,
	},
}

local current: { move: Move, start: number, fired: { [number]: boolean }, callbacks: Callbacks? }? = nil
local height = 6
local extraScale = 1 -- enrage growth, eased toward target
local extraScaleTarget = 1

-- A new boss model appeared: forget the old one's moves.
function BossAnimator.setTarget(newHeight: number)
	height = newHeight
	current = nil
	extraScale = 1
	extraScaleTarget = 1
end

-- True while a move that can't be interrupted (entrance, rise, sink) is playing.
function BossAnimator.busy(): boolean
	return current ~= nil and current.move.locked == true
end

-- `startAt` (os.clock time) can be in the future: until then the move holds its first
-- pose (an entering boss waits high in the sky, a raid boss underground).
function BossAnimator.play(name: string, callbacks: Callbacks?, startAt: number?)
	local move = MOVES[name]
	if move == nil or BossAnimator.busy() then
		return
	end
	current = { move = move, start = startAt or os.clock(), fired = {}, callbacks = callbacks }
end

-- Enraged bosses grow a bit and stay that way.
function BossAnimator.setEnraged(on: boolean)
	extraScaleTarget = if on then 1.15 else 1
end

-- Where the model should be this frame, relative to its home: (offset, scale multiplier).
function BossAnimator.sample(now: number, dt: number): (CFrame, number)
	extraScale += (extraScaleTarget - extraScale) * math.min(1, dt * 4)
	local playing = current
	if playing == nil then
		return CFrame.new(), extraScale
	end
	local t = math.max(0, (now - playing.start) / playing.move.duration)
	local events = playing.move.events
	if events ~= nil then
		for index, event in events do
			if t >= event.at and not playing.fired[index] then
				playing.fired[index] = true
				local callback = if playing.callbacks ~= nil then playing.callbacks[event.name] else nil
				if callback ~= nil then
					task.spawn(callback)
				end
			end
		end
	end
	if t >= 1 then
		current = nil
		local done = if playing.callbacks ~= nil then playing.callbacks.done else nil
		if done ~= nil then
			task.spawn(done)
		end
		return CFrame.new(), extraScale
	end
	local offset, scale = playing.move.pose(t, height)
	return offset, scale * extraScale
end

return BossAnimator
