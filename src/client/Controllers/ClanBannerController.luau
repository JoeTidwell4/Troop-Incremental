--!strict
-- Stands your clan's banner on your battlefield (Visuals/ClanBanner) and keeps it in step
-- with the clan: color, emblem, tag and level. Removed when you're not in a clan. The flag
-- sways gently in the wind.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Controllers = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Plots = require(Shared:WaitForChild("Plots"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local ClanConfig = require(Shared:WaitForChild("Config"):WaitForChild("ClanConfig"))
local CampConfig = require(Shared:WaitForChild("Config"):WaitForChild("CampConfig"))
local ClanBanner = require(Controllers.Parent:WaitForChild("Visuals"):WaitForChild("ClanBanner"))
local ClanController = require(Controllers.ClanController)

type ClanView = Types.ClanView

-- Where the banner stands: the Clan sign's spot in the camp (CampConfig), which hides its
-- own stand while you're in a clan.
local OFFSET = Vector3.new(-30, 0.5, 10)
for _, sign in CampConfig.SIGNS do
	if sign.key == "Clan" then
		OFFSET = sign.offset
	end
end

local ClanBannerController = {}

local folder: Folder? = nil
local current: Model? = nil
local flag: BasePart? = nil
local hinge = CFrame.new()
local currentKey = ""
local origin = Vector3.zero

local function rebuild(view: ClanView?)
	local clan = if view ~= nil and view.inClan then view.clan else nil
	local key = ""
	local level = 0
	if clan ~= nil then
		level = Formulas.clanLevel(clan.xp or 0)
		key = `{clan.id}:{clan.color or 6}:{clan.emblem or 1}:{clan.tag}:{level}`
	end
	if key == currentKey then
		return
	end
	currentKey = key
	if current ~= nil then
		current:Destroy()
		current, flag = nil, nil
	end
	local target = folder
	if clan == nil or target == nil then
		return
	end
	local model, flagPart, flagHinge = ClanBanner.build(target, CFrame.new(origin + OFFSET), {
		color = ClanConfig.COLORS[clan.color or 6] or ClanConfig.COLORS[1],
		emblem = ClanConfig.EMBLEMS[clan.emblem or 1] or "",
		tag = clan.tag,
		level = level,
	})
	current, flag, hinge = model, flagPart, flagHinge
end

function ClanBannerController.start()
	local player = Players.LocalPlayer
	task.spawn(function()
		local index = player:GetAttribute(Plots.ATTRIBUTE)
		while typeof(index) ~= "number" do
			player:GetAttributeChangedSignal(Plots.ATTRIBUTE):Wait()
			index = player:GetAttribute(Plots.ATTRIBUTE)
		end
		origin = Plots.origin(index :: number)
		local newFolder = Instance.new("Folder")
		newFolder.Name = "ClanBanner"
		newFolder.Parent = workspace
		folder = newFolder
		rebuild(ClanController.get())
	end)
	ClanController.Changed:Connect(rebuild)

	-- Gentle sway: the flag turns a little around the pole.
	RunService.RenderStepped:Connect(function()
		local part = flag
		if part ~= nil and part.Parent ~= nil then
			local t = os.clock()
			local sway = math.sin(t * 1.7) * 0.12 + math.sin(t * 3.1) * 0.04
			part.CFrame = hinge * CFrame.Angles(0, sway, 0) * CFrame.new(part.Size.X / 2, 0, 0)
		end
	end)
end

return ClanBannerController
