--!strict
-- Gives every player their own battlefield spot ("plot") and stands their avatar on it as
-- the commander. Plots are far apart, so you only ever see your own.
--
-- The avatar is anchored in place and movement controls are turned off: the game is
-- played from a fixed camera, so walking around would only fight the camera.
-- The plot number is stored as a Player attribute; the client builds its battlefield there.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Plots = require(Shared:WaitForChild("Plots"))
local WorldConfig = require(Shared:WaitForChild("Config"):WaitForChild("WorldConfig"))

-- Height of the battlefield ground's top surface above the plot center (the client builds
-- a 1-stud-thick ground centered on the plot).
local GROUND_TOP = 0.5
local CHARACTER_LOAD_TIMEOUT = 10

local plotOwners: { [number]: Player } = {}
local playerPlots: { [Player]: number } = {}

local PlotService = {}

local function claimPlot(player: Player): number
	local index = 1
	while plotOwners[index] ~= nil do
		index += 1
	end
	plotOwners[index] = player
	playerPlots[player] = index
	player:SetAttribute(Plots.ATTRIBUTE, index)
	return index
end

local function releasePlot(player: Player)
	local index = playerPlots[player]
	if index ~= nil then
		plotOwners[index] = nil
		playerPlots[player] = nil
	end
end

local function placeCommander(player: Player, character: Model)
	local index = playerPlots[player]
	local humanoid = character:WaitForChild("Humanoid", CHARACTER_LOAD_TIMEOUT) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", CHARACTER_LOAD_TIMEOUT) :: BasePart?
	if index == nil or humanoid == nil or root == nil then
		return
	end

	-- Root part height above the feet: R6 legs are 2 studs; R15 uses HipHeight.
	local rootHeight = if humanoid.RigType == Enum.HumanoidRigType.R6
		then 2 + root.Size.Y / 2
		else humanoid.HipHeight + root.Size.Y / 2

	local origin = Plots.origin(index)
	local position = origin + WorldConfig.COMMANDER_OFFSET + Vector3.new(0, GROUND_TOP + rootHeight, 0)
	local lookAt = origin + WorldConfig.COMMANDER_LOOK_AT
	local facing = CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z))

	humanoid.WalkSpeed = 0
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	root.Anchored = true
	character:PivotTo(facing)
end

local function onPlayerAdded(player: Player)
	claimPlot(player)
	-- No movement controls (keyboard or mobile thumbstick/jump button).
	player.DevComputerMovementMode = Enum.DevComputerMovementMode.Scriptable
	player.DevTouchMovementMode = Enum.DevTouchMovementMode.Scriptable

	player.CharacterAdded:Connect(function(character: Model)
		placeCommander(player, character)
	end)
	if player.Character ~= nil then
		task.spawn(placeCommander, player, player.Character)
	end
end

function PlotService.start()
	Players.CharacterAutoLoads = true
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(releasePlot)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PlotService
