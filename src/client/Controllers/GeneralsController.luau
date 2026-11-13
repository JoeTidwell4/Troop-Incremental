--!strict
-- Stands your fielded Generals on your battlefield (Visuals/GeneralModels), beside your
-- commander, facing the enemy. Rebuilt when the fielded Generals change. They attack the
-- enemy every few seconds in their own style (arrows, orbs, coins, boulders, sword and
-- lance slashes: wind-up, release, follow-through), sway while idle and hop when you
-- beat a boss. Cosmetic only: their bonuses are applied on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Controllers = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Plots = require(Shared:WaitForChild("Plots"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local GeneralConfig = require(Shared:WaitForChild("Config"):WaitForChild("GeneralConfig"))
local Visuals = Controllers.Parent:WaitForChild("Visuals")
local GeneralModels = require(Visuals:WaitForChild("GeneralModels"))
local Effects = require(Visuals:WaitForChild("Effects"))
local StateController = require(Controllers.StateController)
local BattlefieldController = require(Controllers.BattlefieldController)

type Snapshot = Types.Snapshot

-- Where the three stand (relative to your plot): a column on the commander's side of the
-- arena, behind your troops, looking down the arena at the enemy (+Z).
local SPOTS = { Vector3.new(-21, 0.5, -6), Vector3.new(-21, 0.5, 0), Vector3.new(-21, 0.5, 6) }
local ENEMY_SPOT = Vector3.new(0, 0.5, 14) -- where the enemy stands (BattlefieldController)
local CHEER_SECONDS = 1.5
local ATTACK_SECONDS = 0.6
local RELEASE_AT = 0.35 -- fraction of the attack when the shot leaves
local ATTACK_GAP = NumberRange.new(2.2, 3.5)
local GOLD = Color3.fromRGB(255, 205, 70)

type Standing = {
	model: Model,
	home: CFrame,
	phase: number,
	style: GeneralModels.AttackStyle,
	color: Color3, -- projectile color (House / rarity)
	nextAttack: number,
	attackStart: number, -- 0 = not attacking
	released: boolean,
}

local GeneralsController = {}

local folder: Folder? = nil
local origin = Vector3.zero
local currentKey = ""
local standing: { Standing } = {}
local attackPose: (style: GeneralModels.AttackStyle, progress: number) -> CFrame
local release: (general: Standing, target: Vector3) -> ()
local cheerUntil = 0
local random = Random.new()

-- The body's motion during an attack (0..1): wind back, then lunge / snap forward.
-- (The model's front is -Z, so "forward" is negative Z.)
attackPose = function(style: GeneralModels.AttackStyle, progress: number): CFrame
	local windup = math.clamp(progress / RELEASE_AT, 0, 1)
	local follow = math.clamp((progress - RELEASE_AT) / (1 - RELEASE_AT), 0, 1)
	local back = math.sin(windup * math.pi * 0.5) * (1 - follow) -- 0 -> 1 -> 0
	local snap = math.sin(follow * math.pi) -- 0 -> 1 -> 0 after the release
	if style == "Melee" or style == "Lance" then
		local reach = if style == "Lance" then 3 else 1.6
		return CFrame.new(0, 0, back * 0.5 - snap * reach) * CFrame.Angles(math.rad(10) * back - math.rad(22) * snap, math.rad(25) * back - math.rad(35) * snap, 0)
	elseif style == "Boulder" then
		-- Heave from low, throw overhead.
		return CFrame.new(0, -back * 0.4, -snap * 0.6) * CFrame.Angles(math.rad(20) * back - math.rad(25) * snap, 0, 0)
	end
	-- Arrows, orbs, coins: lean back to aim, then snap forward.
	return CFrame.new(0, 0, back * 0.35 - snap * 0.5) * CFrame.Angles(math.rad(12) * back - math.rad(12) * snap, 0, 0)
end

-- The shot itself, fired at the release point of the attack.
release = function(general: Standing, target: Vector3)
	local from = (general.model:GetPivot() * GeneralModels.handOffset()).Position
	local style = general.style
	if style == "Arrow" then
		Effects.arrow(from, target, general.color, 0.45, function()
			Effects.hitSparks(target)
		end)
	elseif style == "Orb" then
		Effects.orb(from, target, general.color, 0.9, 0.55, true, function()
			Effects.hitSparks(target)
		end)
	elseif style == "Coin" then
		Effects.orb(from, target, general.color, 0.6, 0.5, true, function()
			Effects.coinBurst(target)
		end)
	elseif style == "Boulder" then
		Effects.orb(from + Vector3.new(0, 1.5, 0), target, Color3.fromRGB(120, 110, 100), 1.6, 0.8, false, function()
			Effects.dustRing(target - Vector3.new(0, 1, 0))
		end)
	else
		-- Sword and lance: a glowing slash wave in the House color flies to the enemy.
		Effects.orb(from, target, general.color, 1.1, 0.35, true, function()
			Effects.hitSparks(target)
		end)
	end
end

local function rebuild(snapshot: Snapshot)
	local target = folder
	if target == nil then
		return
	end
	local fielded = snapshot.generals.fielded
	local key = table.concat(fielded, ",")
	if key == currentKey then
		return
	end
	currentKey = key
	target:ClearAllChildren()
	standing = {}
	for slot, generalId in fielded do
		local def = GeneralConfig.GENERALS[generalId]
		local spot = SPOTS[slot]
		if def ~= nil and spot ~= nil then
			local house = GeneralConfig.HOUSES[Formulas.generalHouse(generalId)]
			local rarity = GeneralConfig.RARITIES[def.rarity]
			local houseColor = if house ~= nil then house.color else rarity.color
			local model = GeneralModels.build(def, houseColor, rarity.color, target)
			local position = origin + spot
			-- Turned to look at the enemy (flat, so they don't lean).
			local enemy = origin + ENEMY_SPOT
			local home = CFrame.lookAt(position, Vector3.new(enemy.X, position.Y, enemy.Z))
			model:PivotTo(home)
			local style = GeneralModels.attackStyle(def)
			table.insert(standing, {
				model = model,
				home = home,
				phase = slot * 1.7,
				style = style,
				color = if style == "Coin" then GOLD elseif style == "Orb" then rarity.color else houseColor,
				nextAttack = os.clock() + slot * 0.8 + random:NextNumber(0.5, 1.5),
				attackStart = 0,
				released = false,
			})
		end
	end
end

function GeneralsController.start()
	local player = Players.LocalPlayer
	task.spawn(function()
		local index = player:GetAttribute(Plots.ATTRIBUTE)
		while typeof(index) ~= "number" do
			player:GetAttributeChangedSignal(Plots.ATTRIBUTE):Wait()
			index = player:GetAttribute(Plots.ATTRIBUTE)
		end
		origin = Plots.origin(index :: number)
		local newFolder = Instance.new("Folder")
		newFolder.Name = "Generals"
		newFolder.Parent = workspace
		folder = newFolder
		local snapshot = StateController.get()
		if snapshot ~= nil then
			rebuild(snapshot)
		end
	end)
	StateController.Changed:Connect(function(snapshot: Snapshot)
		rebuild(snapshot)
	end)
	StateController.Notice:Connect(function(notice: Types.Notice)
		if notice.kind == "BossDefeated" then
			cheerUntil = os.clock() + CHEER_SECONDS
		end
	end)

	-- Every frame: idle sway, boss-win hops, and attacks.
	RunService.RenderStepped:Connect(function()
		if #standing == 0 then
			return
		end
		local t = os.clock()
		local cheering = t < cheerUntil
		local target = BattlefieldController.getEnemyPosition()
		for _, general in standing do
			local sway = math.sin(t * 1.3 + general.phase) * 0.04
			local hop = if cheering then math.abs(math.sin(t * 9 + general.phase)) * 0.8 else 0
			local pose = CFrame.new()

			-- Start an attack when it's time and there's something to hit.
			-- (target is nil while there's no enemy model, e.g. between a boss's exit and the next enemy)
			if general.attackStart == 0 and target ~= nil and not cheering and t >= general.nextAttack then
				general.attackStart = t
				general.released = false
			end
			if general.attackStart > 0 then
				local progress = (t - general.attackStart) / ATTACK_SECONDS
				if progress >= 1 then
					general.attackStart = 0
					general.nextAttack = t + random:NextNumber(ATTACK_GAP.Min, ATTACK_GAP.Max)
				else
					pose = attackPose(general.style, progress)
					if not general.released and progress >= RELEASE_AT and target ~= nil then
						general.released = true
						release(general, target)
					end
				end
			end
			general.model:PivotTo(general.home * CFrame.new(0, hop, 0) * CFrame.Angles(0, sway, 0) * pose)
		end
	end)
end

return GeneralsController
