--!strict
-- Your avatar as the commander: gives it a sword and swings when you click the
-- battlefield. Visual only and only on your own screen. The server already put the
-- avatar in place (PlotService).
--
-- The swing has two parts:
--   * The sword slashes (always works: we made that weld ourselves).
--   * The arm lifts, if we can find the shoulder joint. Avatars use either classic
--     Motor6D joints or Roblox's newer AnimationConstraint joints; both are handled.
-- What was found is printed once to Output to help debug odd avatars.
-- Commander gear (CommanderConfig): the equipped Weapon restyles the sword; helmets,
-- capes and back items are built on the avatar by Visuals/CommanderGear.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Controllers = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local CommanderConfig = require(Shared:WaitForChild("Config"):WaitForChild("CommanderConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local InputController = require(Controllers.InputController)
local StateController = require(Controllers.StateController)
local CommanderGear = require(Controllers.Parent:WaitForChild("Visuals"):WaitForChild("CommanderGear"))
local LegacyAura = require(Controllers.Parent:WaitForChild("Visuals"):WaitForChild("LegacyAura"))

local SWING_COOLDOWN = 0.3
local SWORD_COLOR = Color3.fromRGB(200, 205, 215)
local SWORD_LENGTH = 4
local RAISE_ANGLE = math.rad(60) -- sword lifted up before the slash
local SLASH_ANGLE = math.rad(-35) -- sword swung down past forward
local ARM_ANGLE = math.rad(80)

type Swing = {
	-- Sword weld: rotates around the grip point in the hand.
	swordWeld: Weld?,
	gripPoint: CFrame,
	-- Shoulder: a Motor6D (tween C0) or an AnimationConstraint (tween Attachment0.CFrame).
	armTarget: Instance?,
	armProperty: string,
	armRest: CFrame,
	armRaised: CFrame,
}

local current: Swing? = nil
local currentSword: BasePart? = nil

local equipped: { [string]: string } = {}
local equippedKey = ""
local legacyCount = 0

-- The sword takes the look of the equipped Weapon item ("Glow" styles are neon).
local function styleSword()
	local sword = currentSword
	if sword == nil then
		return
	end
	local def = CommanderConfig.ITEMS[equipped.Weapon or ""]
	if def ~= nil then
		sword.Color = def.color
		sword.Material = if def.style == "Glow" then Enum.Material.Neon else Enum.Material.Metal
	else
		sword.Color = SWORD_COLOR
		sword.Material = Enum.Material.Metal
	end
end

-- Puts the worn gear on the current avatar (helmet, cape, back) and restyles the sword.
local function applyGear()
	styleSword()
	local character = Players.LocalPlayer.Character
	if character ~= nil then
		CommanderGear.apply(character, equipped, CommanderConfig.ITEMS)
		LegacyAura.apply(character, legacyCount)
	end
end
local lastSwing = 0

local CommanderController = {}

local function swordCFrame(gripPoint: CFrame, angle: number): CFrame
	-- Rotate around the grip, then push the blade out forward from the hand.
	return gripPoint * CFrame.Angles(angle, 0, 0) * CFrame.new(0, 0, -(SWORD_LENGTH / 2 - 0.1))
end

local function addSword(hand: BasePart, gripPoint: CFrame): Weld
	local sword = Instance.new("Part")
	sword.Name = "CommanderSword"
	sword.Size = Vector3.new(0.25, 0.4, SWORD_LENGTH)
	sword.Color = SWORD_COLOR
	sword.Material = Enum.Material.Metal
	sword.CanCollide = false
	sword.CanQuery = false
	sword.CanTouch = false
	sword.Massless = true
	sword.CastShadow = false

	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = sword
	weld.C0 = swordCFrame(gripPoint, 0)
	weld.Parent = sword
	sword.Parent = hand.Parent
	return weld
end

-- Finds the joint that moves `arm`: (instance, property to tween, axis rotation) or nil.
local function findShoulder(character: Model, arm: BasePart, rotation: CFrame): (Instance?, string, CFrame)
	for _, item in character:GetDescendants() do
		if item:IsA("Motor6D") and item.Part1 == arm then
			return item, "C0", rotation
		end
		if item.ClassName == "AnimationConstraint" then
			local attachment1 = (item :: any).Attachment1 :: Attachment?
			local attachment0 = (item :: any).Attachment0 :: Attachment?
			if attachment1 ~= nil and attachment0 ~= nil and attachment1.Parent == arm then
				return attachment0, "CFrame", rotation
			end
		end
	end
	return nil, "", CFrame.identity
end

local function setupCharacter(character: Model)
	current = nil
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid == nil then
		return
	end

	local isR15 = humanoid.RigType == Enum.HumanoidRigType.R15
	local hand = character:WaitForChild(if isR15 then "RightHand" else "Right Arm", 10) :: BasePart?
	local arm = character:WaitForChild(if isR15 then "RightUpperArm" else "Right Arm", 10) :: BasePart?
	-- R15 joints raise the arm forward around X; R6 shoulder joints are turned sideways (Z).
	local armRotation = if isR15 then CFrame.Angles(ARM_ANGLE, 0, 0) else CFrame.Angles(0, 0, ARM_ANGLE)
	local gripPoint = if isR15 then CFrame.new(0, -0.2, 0) else CFrame.new(0, -0.9, 0)

	local swing: Swing = {
		swordWeld = nil,
		gripPoint = gripPoint,
		armTarget = nil,
		armProperty = "",
		armRest = CFrame.identity,
		armRaised = CFrame.identity,
	}

	-- Guard against setting up the same character twice (two swords).
	if hand ~= nil and character:FindFirstChild("CommanderSword") == nil then
		local weld = addSword(hand, gripPoint)
		swing.swordWeld = weld
		currentSword = weld.Part1
		styleSword()
	end

	local jointKind = "none"
	if arm ~= nil then
		local target, property, rotation = findShoulder(character, arm, armRotation)
		if target ~= nil then
			local rest = (target :: any)[property] :: CFrame
			swing.armTarget = target
			swing.armProperty = property
			swing.armRest = rest
			swing.armRaised = rest * rotation
			jointKind = if property == "C0" then "Motor6D" else "AnimationConstraint"
		end
	end

	print(`[Commander] Avatar {if isR15 then "R15" else "R6"}, sword: {hand ~= nil}, shoulder joint: {jointKind}`)
	current = swing
	applyGear()
end

local function swing()
	local state = current
	local now = os.clock()
	if state == nil or now - lastSwing < SWING_COOLDOWN then
		return
	end
	lastSwing = now

	local weld = state.swordWeld
	if weld ~= nil then
		-- Lift, slash down, then return to rest.
		weld.C0 = swordCFrame(state.gripPoint, RAISE_ANGLE)
		local slash = TweenService:Create(weld, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			C0 = swordCFrame(state.gripPoint, SLASH_ANGLE),
		})
		slash.Completed:Connect(function()
			TweenService:Create(weld, TweenInfo.new(0.15), { C0 = swordCFrame(state.gripPoint, 0) }):Play()
		end)
		slash:Play()
	end

	local target = state.armTarget
	if target ~= nil then
		(target :: any)[state.armProperty] = state.armRest
		local info = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
		TweenService:Create(target, info, { [state.armProperty] = state.armRaised }):Play()
	end
end

local equipRemote: RemoteEvent? = nil
local chestRemote: RemoteFunction? = nil

-- Opens a Wardrobe Chest (gold). Yields for the server's roll. Never throws.
function CommanderController.openChest(chestId: string): Types.ChestResult
	local remote = chestRemote
	if remote == nil then
		return { ok = false, reason = "NotReady" }
	end
	local ok, result = pcall(function(): any
		return remote:InvokeServer(chestId)
	end)
	if ok and typeof(result) == "table" then
		return result :: Types.ChestResult
	end
	return { ok = false, reason = "NoResponse" }
end

-- Asks the server to wear an item in a slot ("" = take it off). The server checks you own it.
function CommanderController.equip(slot: string, itemId: string)
	if equipRemote ~= nil then
		equipRemote:FireServer(slot, itemId)
	end
end

function CommanderController.start()
	local player = Players.LocalPlayer
	equipRemote = Remotes.waitForEvent(Remotes.Events.EquipCommander)
	chestRemote = Remotes.waitForFunction(Remotes.Functions.OpenWardrobeChest)
	-- Re-dress the commander whenever the equipped items change.
	StateController.Changed:Connect(function(snapshot: Types.Snapshot)
		local worn = snapshot.commander.equipped
		local key = ""
		for _, slot in CommanderConfig.SLOTS do
			key ..= (worn[slot] or "") .. "|"
		end
		if key ~= equippedKey or snapshot.legacyCount ~= legacyCount then
			equippedKey = key
			equipped = worn
			legacyCount = snapshot.legacyCount
			applyGear()
		end
	end)
	player.CharacterAdded:Connect(function(character: Model)
		setupCharacter(character)
	end)
	if player.Character ~= nil then
		task.spawn(setupCharacter, player.Character)
	end
	InputController.Tapped:Connect(swing)
end

return CommanderController
