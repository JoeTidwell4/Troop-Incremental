--!strict
-- Plays one story scene (StoryConfig.SCENES): black letterbox bars, the camera cutting
-- between shots (BattlefieldController.focusCamera), part-built actors that walk, hop,
-- bow, fall and vanish, effects, and a dialogue box with the speaker's name.
--
-- Lines type themselves out and advance on their own after a few seconds (so AFK players
-- are never stuck); tap / click to finish a line or go to the next one; SKIP ends the scene.
-- Every other ScreenGui is hidden while it plays and restored afterwards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Plots = require(Shared:WaitForChild("Plots"))
local Config = Shared:WaitForChild("Config")
local StoryConfig = require(Config:WaitForChild("StoryConfig"))
local GeneralConfig = require(Config:WaitForChild("GeneralConfig"))
local WorldConfig = require(Config:WaitForChild("WorldConfig"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Visuals = Client:WaitForChild("Visuals")
local GeneralModels = require(Visuals:WaitForChild("GeneralModels"))
local EnemyModels = require(Visuals:WaitForChild("EnemyModels"))
local Effects = require(Visuals:WaitForChild("Effects"))
local BattlefieldController = require(Client.Controllers.BattlefieldController)
local AudioController = require(Client.Controllers.AudioController)
local Cinematic = require(Client.Controllers.Cinematic)

type Scene = StoryConfig.StoryScene

type Actor = {
	model: Model,
	pos: Vector3, -- feet (world)
	face: Vector3,
	moveFrom: Vector3?,
	moveStart: number,
	moveTime: number,
	anim: string,
	animStart: number,
	phase: number,
}

local GROUND = 0.3 -- the ground's top, relative to the plot centre
local SHOT_GLIDE = 0.7
local TYPE_SPEED = 45 -- characters per second
local BAR_FRACTION = 0.13

local CutsceneUI = {}

local playing = false

function CutsceneUI.isPlaying(): boolean
	return playing
end

local function plotOrigin(): Vector3
	local index = Players.LocalPlayer:GetAttribute(Plots.ATTRIBUTE)
	return Plots.origin(if typeof(index) == "number" then index else 1)
end

-- Camera CFrame for a shot.
local function cameraFor(spec: any, origin: Vector3): CFrame
	if spec == "sky" then
		return CFrame.lookAt(origin + Vector3.new(0, 34, -72), origin + Vector3.new(0, 10, 60))
	elseif spec == "commander" then
		local at = origin + WorldConfig.COMMANDER_OFFSET
		return CFrame.lookAt(at + Vector3.new(1.5, 4.8, 9), at + Vector3.new(0, 3.4, 0))
	elseif spec == "enemy" then
		local top = BattlefieldController.getEnemyPosition()
		if top ~= nil then
			local height = math.max(top.Y - origin.Y, 4)
			local feet = Vector3.new(top.X, origin.Y, top.Z)
			return CFrame.lookAt(feet + Vector3.new(0, height * 0.55, -height * 1.9), feet + Vector3.new(0, height * 0.5, 0))
		end
	elseif typeof(spec) == "table" and typeof(spec.pos) == "Vector3" and typeof(spec.look) == "Vector3" then
		return CFrame.lookAt(origin + spec.pos, origin + spec.look)
	end
	-- "wide": the open ground in front of the arena, where the cast stands.
	return CFrame.lookAt(origin + Vector3.new(0, 5.5, -41), origin + Vector3.new(0, 3.2, -26))
end

function CutsceneUI.play(scene: Scene, onDone: () -> ())
	if playing then
		onDone()
		return
	end
	playing = true
	Cinematic.active = true
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local origin = plotOrigin()
	local camera = workspace.CurrentCamera

	-- Hide the game's UI.
	local hidden: { ScreenGui } = {}
	for _, child in playerGui:GetChildren() do
		if child:IsA("ScreenGui") and child.Enabled then
			child.Enabled = false
			table.insert(hidden, child)
		end
	end

	-- Overlay: letterbox bars, dialogue, skip.
	local gui = Instance.new("ScreenGui")
	gui.Name = "Cutscene"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 40
	gui.Parent = playerGui
	local viewY = if camera ~= nil then camera.ViewportSize.Y else 720
	local textSize = math.clamp(math.floor(viewY * 0.03), 15, 28)

	local function bar(top: boolean): Frame
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = Color3.new(0, 0, 0)
		frame.BorderSizePixel = 0
		frame.AnchorPoint = if top then Vector2.new(0, 1) else Vector2.new(0, 0)
		frame.Position = if top then UDim2.fromScale(0, 0) else UDim2.fromScale(0, 1)
		frame.Size = UDim2.fromScale(1, BAR_FRACTION)
		frame.Parent = gui
		TweenService:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
			Position = if top then UDim2.fromScale(0, BAR_FRACTION) else UDim2.fromScale(0, 1 - BAR_FRACTION),
		}):Play()
		return frame
	end
	bar(true)
	local bottom = bar(false)

	-- Tap anywhere to advance (a full-screen button, so taps never reach the battlefield).
	local catcher = Instance.new("TextButton")
	catcher.BackgroundTransparency = 1
	catcher.Text = ""
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.AutoButtonColor = false
	catcher.Parent = gui

	local box = Instance.new("Frame")
	box.BackgroundColor3 = Color3.fromRGB(14, 12, 20)
	box.BackgroundTransparency = 0.15
	box.AnchorPoint = Vector2.new(0.5, 1)
	box.Position = UDim2.new(0.5, 0, 1, -math.floor(viewY * 0.03))
	box.Size = UDim2.new(0.7, 0, 0, textSize * 4.2)
	box.Visible = false
	box.ZIndex = 2
	box.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = box
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = box
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(900, math.huge)
	sizeLimit.Parent = box
	local speaker = Instance.new("TextLabel")
	speaker.BackgroundTransparency = 1
	speaker.Font = Enum.Font.FredokaOne
	speaker.TextSize = textSize
	speaker.TextXAlignment = Enum.TextXAlignment.Left
	speaker.Position = UDim2.new(0, 16, 0, 8)
	speaker.Size = UDim2.new(1, -32, 0, textSize + 4)
	speaker.ZIndex = 3
	speaker.Parent = box
	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.GothamMedium
	body.TextSize = textSize - 2
	body.TextColor3 = Color3.fromRGB(240, 240, 245)
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.Position = UDim2.new(0, 16, 0, textSize + 14)
	body.Size = UDim2.new(1, -32, 1, -(textSize + 20))
	body.ZIndex = 3
	body.Parent = box

	local skip = Instance.new("TextButton")
	skip.Text = "SKIP  >>"
	skip.Font = Enum.Font.FredokaOne
	skip.TextSize = math.max(14, textSize - 6)
	skip.TextColor3 = Color3.fromRGB(230, 230, 235)
	skip.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	skip.BackgroundTransparency = 0.3
	skip.AnchorPoint = Vector2.new(1, 0)
	skip.Position = UDim2.new(1, -16, BAR_FRACTION, 10)
	skip.Size = UDim2.fromOffset(110, 34)
	skip.ZIndex = 5
	skip.Parent = gui
	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, 8)
	skipCorner.Parent = skip

	local skipped = false
	local advance = false
	skip.Activated:Connect(function()
		skipped = true
	end)
	catcher.Activated:Connect(function()
		advance = true
	end)

	-- Actors.
	local folder = Instance.new("Folder")
	folder.Name = "CutsceneActors"
	folder.Parent = workspace
	local actors: { [string]: Actor } = {}

	local function spotOf(value: any): Vector3?
		if typeof(value) == "Vector3" then
			return origin + value + Vector3.new(0, GROUND, 0)
		elseif value == "enemy" then
			local top = BattlefieldController.getEnemyPosition()
			if top ~= nil then
				return Vector3.new(top.X, (top.Y + origin.Y) / 2, top.Z)
			end
		elseif typeof(value) == "string" then
			local actor = actors[value]
			if actor ~= nil then
				return actor.pos + Vector3.new(0, 3, 0)
			end
		end
		return nil
	end

	local function effect(name: string, at: any)
		local position = spotOf(at)
		if position == nil then
			return
		end
		if name == "portal" then
			Effects.portal(position, 7, StoryConfig.HOLLOW_COLOR, 2.5)
		elseif name == "roar" then
			Effects.roar(position, StoryConfig.HOLLOW_COLOR)
			AudioController.play("BossRoar")
		elseif name == "smoke" or name == "shockwave" then
			Effects.shockwave(position, 9, StoryConfig.HOLLOW_COLOR, 0.7)
		elseif name == "sparks" then
			Effects.hitSparks(position)
			Effects.coinBurst(position)
		elseif name == "dust" then
			Effects.dustRing(position)
		end
	end

	local function spawn(action: { [string]: any })
		local name = action.spawn :: string
		local at = origin + ((action.at :: Vector3?) or Vector3.zero) + Vector3.new(0, GROUND, 0)
		local face = (action.face :: Vector3?) or Vector3.new(0, 0, -1)
		local model: Model? = nil
		if typeof(action.general) == "string" then
			local def = GeneralConfig.GENERALS[action.general]
			if def ~= nil then
				local house = GeneralConfig.HOUSES[Formulas.generalHouse(def.id)]
				local rarity = GeneralConfig.RARITIES[def.rarity]
				model = GeneralModels.build(def, if house ~= nil then house.color else rarity.color, rarity.color, folder)
			end
		elseif typeof(action.enemy) == "string" then
			local color = (action.color :: Color3?) or Color3.fromRGB(120, 120, 130)
			model = (EnemyModels.build(action.enemy, color, (action.scale :: number?) or 1, false, CFrame.new(at), folder))
			if action.ghost and model ~= nil then
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") and part.Transparency < 1 then
						part.Transparency = math.max(part.Transparency, 0.35)
					end
				end
			end
		end
		if model == nil then
			return
		end
		local old = actors[name]
		if old ~= nil then
			old.model:Destroy()
		end
		actors[name] = { model = model, pos = at, face = face, moveFrom = nil, moveStart = 0, moveTime = 0, anim = "", animStart = 0, phase = math.random() * 6 }
	end

	local function run(action: { [string]: any })
		if action.spawn ~= nil then
			spawn(action)
		elseif action.move ~= nil then
			local actor = actors[action.move]
			if actor ~= nil and typeof(action.to) == "Vector3" then
				actor.moveFrom = actor.pos
				actor.pos = origin + action.to + Vector3.new(0, GROUND, 0)
				actor.moveStart = os.clock()
				actor.moveTime = math.max((action.time :: number?) or 1, 0.1)
			end
		elseif action.anim ~= nil then
			local actor = actors[action.anim]
			if actor ~= nil then
				actor.anim = action.name or ""
				actor.animStart = os.clock()
			end
		elseif action.effect ~= nil then
			effect(action.effect, action.at)
		elseif action.remove ~= nil then
			local actor = actors[action.remove]
			if actor ~= nil then
				if typeof(action.effect) == "string" then
					effect(action.effect, action.remove)
				end
				actor.model:Destroy()
				actors[action.remove] = nil
			end
		end
	end

	-- Moves every actor each frame: walking, the current animation, a slight idle sway.
	local stepper = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for _, actor in actors do
			local position = actor.pos
			local lift = 0
			if actor.moveFrom ~= nil then
				local t = math.clamp((now - actor.moveStart) / actor.moveTime, 0, 1)
				position = (actor.moveFrom :: Vector3):Lerp(actor.pos, t)
				lift = if t < 1 then math.abs(math.sin(now * 10)) * 0.35 else 0
				if t >= 1 then
					actor.moveFrom = nil
				end
			end
			local extra = CFrame.new()
			local a = now - actor.animStart
			if actor.anim == "hop" and a < 0.9 then
				lift += math.abs(math.sin(a / 0.9 * math.pi * 2)) * 1.4
			elseif actor.anim == "bow" and a < 1.2 then
				extra = CFrame.Angles(-math.sin(a / 1.2 * math.pi) * 0.45, 0, 0)
			elseif actor.anim == "shake" and a < 0.6 then
				extra = CFrame.new(math.sin(a * 60) * 0.15, 0, 0)
			elseif actor.anim == "fall" then
				extra = CFrame.Angles(math.min(a / 0.5, 1) * math.rad(85), 0, 0)
			elseif actor.anim == "rise" and a < 1 then
				lift -= (1 - a) * 5
			end
			local sway = math.sin(now * 1.6 + actor.phase) * 0.04
			local cf = CFrame.lookAt(position, position + actor.face) * CFrame.new(0, lift, 0) * CFrame.Angles(0, sway, 0) * extra
			actor.model:PivotTo(cf)
		end
	end)

	-- Waits up to `seconds`; returns early on skip, or on a tap when `tappable`.
	local function wait(seconds: number, tappable: boolean)
		local deadline = os.clock() + seconds
		while os.clock() < deadline and not skipped and not (tappable and advance) do
			task.wait()
		end
	end

	local function say(line: StoryConfig.StoryLine)
		local cast = StoryConfig.CAST[line.who] or StoryConfig.CAST.Narrator
		local name = if line.who == "Commander" then player.DisplayName else cast.name
		speaker.Text = name
		speaker.TextColor3 = cast.color
		stroke.Color = cast.color
		speaker.Visible = name ~= ""
		body.Font = if line.who == "Narrator" then Enum.Font.GothamMedium else Enum.Font.Gotham
		box.Visible = true
		-- Type it out.
		advance = false
		local text = line.text
		local started = os.clock()
		while not skipped and not advance do
			local shown = math.floor((os.clock() - started) * TYPE_SPEED)
			if shown >= #text then
				break
			end
			body.Text = string.sub(text, 1, shown)
			task.wait()
		end
		body.Text = text
		advance = false
		-- Hold, then go on by itself.
		local hold = StoryConfig.LINE_SECONDS_MIN + #text * StoryConfig.LINE_SECONDS_PER_CHAR
		wait(hold, true)
		advance = false
	end

	task.spawn(function()
		task.wait(0.4)
		for _, shot in scene.shots do
			if skipped then
				break
			end
			BattlefieldController.focusCamera(cameraFor(shot.cam, origin), SHOT_GLIDE)
			for _, action in shot.actions or {} do
				run(action)
			end
			wait(SHOT_GLIDE * 0.6, false)
			local lines = shot.lines or {}
			for _, line in lines do
				if skipped then
					break
				end
				say(line)
			end
			if shot.hold ~= nil then
				wait(shot.hold, true)
			elseif #lines == 0 then
				wait(1.5, true)
			end
		end

		-- Clean up and hand the game back.
		box.Visible = false
		stepper:Disconnect()
		folder:Destroy()
		BattlefieldController.focusCamera(nil, 0.6)
		task.wait(0.4)
		gui:Destroy()
		for _, screen in hidden do
			if screen.Parent ~= nil then
				screen.Enabled = true
			end
		end
		Cinematic.active = false
		playing = false
		onDone()
	end)
end

return CutsceneUI
