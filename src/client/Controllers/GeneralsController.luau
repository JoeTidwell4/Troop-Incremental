--!strict
-- Stands your fielded Generals on your battlefield (Visuals/GeneralModels), beside your
-- commander, facing the enemy. Rebuilt when the fielded Generals change; a gentle idle
-- sway, and they raise their weapons (a small hop) when you beat a boss.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Controllers = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Plots = require(Shared:WaitForChild("Plots"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local GeneralConfig = require(Shared:WaitForChild("Config"):WaitForChild("GeneralConfig"))
local GeneralModels = require(Controllers.Parent:WaitForChild("Visuals"):WaitForChild("GeneralModels"))
local StateController = require(Controllers.StateController)

type Snapshot = Types.Snapshot

-- Where the three stand (relative to your plot): a column on the commander's side of the
-- arena, behind your troops, looking down the arena at the enemy (+Z).
local SPOTS = { Vector3.new(-21, 0.5, -6), Vector3.new(-21, 0.5, 0), Vector3.new(-21, 0.5, 6) }
local FACING = Vector3.new(0, 0, 1)
local CHEER_SECONDS = 1.5

local GeneralsController = {}

local folder: Folder? = nil
local origin = Vector3.zero
local currentKey = ""
local standing: { { model: Model, home: CFrame, phase: number } } = {}
local cheerUntil = 0

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
			local home = CFrame.lookAt(position, position + FACING)
			model:PivotTo(home)
			table.insert(standing, { model = model, home = home, phase = slot * 1.7 })
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

	-- Idle: a slow breathing sway; after a boss win, a few happy hops.
	RunService.RenderStepped:Connect(function()
		if #standing == 0 then
			return
		end
		local t = os.clock()
		local cheering = t < cheerUntil
		for _, general in standing do
			local sway = math.sin(t * 1.3 + general.phase) * 0.04
			local hop = if cheering then math.abs(math.sin(t * 9 + general.phase)) * 0.8 else 0
			general.model:PivotTo(general.home * CFrame.new(0, hop, 0) * CFrame.Angles(0, sway, 0))
		end
	end)
end

return GeneralsController
