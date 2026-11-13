--!strict
-- Your avatar as the commander: gives it a sword and swings its arm when you click the
-- battlefield. Visual only and only on your own screen. The server already put the
-- avatar in place (PlotService).
--
-- Avatars come in two body types: R15 (modern, "RightHand" + "RightShoulder" joint) and
-- R6 (classic, "Right Arm" + "Right Shoulder" joint). Both are handled; if a custom avatar
-- has neither, the sword and swing are skipped and the avatar just stands there.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Controllers = script.Parent
local InputController = require(Controllers.InputController)

local SWING_COOLDOWN = 0.25
local SWING_TIME = 0.12
local SWORD_COLOR = Color3.fromRGB(200, 205, 215)

type Rig = {
	shoulder: Motor6D,
	restC0: CFrame,
	swingC0: CFrame,
}

local rig: Rig? = nil
local lastSwing = 0

local CommanderController = {}

local function addSword(hand: BasePart, gripOffset: CFrame)
	local sword = Instance.new("Part")
	sword.Name = "CommanderSword"
	sword.Size = Vector3.new(0.25, 0.4, 4)
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
	weld.C0 = gripOffset
	weld.Parent = sword
	sword.Parent = hand.Parent
end

local function setupCharacter(character: Model)
	rig = nil
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid == nil then
		return
	end

	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		local hand = character:WaitForChild("RightHand", 10) :: BasePart?
		local upperArm = character:WaitForChild("RightUpperArm", 10)
		local shoulder = if upperArm ~= nil then upperArm:FindFirstChild("RightShoulder") else nil
		if hand ~= nil then
			addSword(hand, CFrame.new(0, -0.2, -1.9))
		end
		if shoulder ~= nil and shoulder:IsA("Motor6D") then
			-- Raise the arm forward by rotating around the shoulder's X axis.
			rig = {
				shoulder = shoulder,
				restC0 = shoulder.C0,
				swingC0 = shoulder.C0 * CFrame.Angles(math.rad(110), 0, 0),
			}
		end
	else
		local arm = character:WaitForChild("Right Arm", 10) :: BasePart?
		local torso = character:WaitForChild("Torso", 10)
		local shoulder = if torso ~= nil then torso:FindFirstChild("Right Shoulder") else nil
		if arm ~= nil then
			addSword(arm, CFrame.new(0, -1, -1.9))
		end
		if shoulder ~= nil and shoulder:IsA("Motor6D") then
			-- R6 shoulder joints are turned sideways, so "forward" is around Z.
			rig = {
				shoulder = shoulder,
				restC0 = shoulder.C0,
				swingC0 = shoulder.C0 * CFrame.Angles(0, 0, math.rad(110)),
			}
		end
	end
end

local function swing()
	local current = rig
	local now = os.clock()
	if current == nil or now - lastSwing < SWING_COOLDOWN then
		return
	end
	lastSwing = now
	current.shoulder.C0 = current.restC0
	local info = TweenInfo.new(SWING_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
	TweenService:Create(current.shoulder, info, { C0 = current.swingC0 }):Play()
end

function CommanderController.start()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(function(character: Model)
		setupCharacter(character)
	end)
	if player.Character ~= nil then
		task.spawn(setupCharacter, player.Character)
	end
	InputController.Tapped:Connect(swing)
end

return CommanderController
