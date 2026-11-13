--!strict
-- Achievements: permanent goals that pay Honor. When a goal is reached it's marked
-- "unlocked" in the save (so it stays claimable even if an Ascend later resets, say,
-- your troop count); claiming grants the Honor and marks it "claimed".
-- Goals are re-checked whenever the player's state changes (at most once a second).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local AchievementConfig = require(Shared:WaitForChild("Config"):WaitForChild("AchievementConfig"))
local DataService = require(Services.DataService)
local DailyService = require(Services.DailyService)
local WarService = require(Services.WarService)

type PlayerData = Types.PlayerData
type AchievementDef = Types.AchievementDef

local BY_ID: { [string]: AchievementDef } = {}
for _, def in AchievementConfig.LIST do
	BY_ID[def.id] = def
end

local lastCheck: { [Player]: number } = {}

local AchievementService = {}

-- How far along the player is toward an achievement (compared against def.target).
local function current(data: PlayerData, def: AchievementDef): number
	local kind = def.kind
	if kind == "bestStage" then
		return data.bestStage
	elseif kind == "stat" then
		local value = (data.stats :: any)[def.key or ""]
		return if typeof(value) == "number" then value else 0
	elseif kind == "lifetime" then
		return data.lifetime[def.key or ""] or 0
	elseif kind == "troop" then
		return data.troops[def.key or ""] or 0
	elseif kind == "legendary" then
		for _, troopGear in data.gear do
			if troopGear.weapon.rarity >= 5 or troopGear.armor.rarity >= 5 then
				return 1
			end
		end
		return 0
	elseif kind == "clan" then
		return if data.clanId ~= "" then 1 else 0
	elseif kind == "faction" then
		return if data.faction ~= "" then 1 else 0
	elseif kind == "warWin" then
		return if WarService.hasWinnerBonus(data) then 1 else 0
	end
	return 0
end

local function check(player: Player, data: PlayerData)
	local changed = false
	for _, def in AchievementConfig.LIST do
		if data.achievements[def.id] == nil and current(data, def) >= def.target then
			data.achievements[def.id] = "unlocked"
			changed = true
		end
	end
	if changed then
		DailyService.markDirty(player)
	end
end

function AchievementService.start()
	DataService.Changed:Connect(function(player: Player)
		local now = os.clock()
		if now - (lastCheck[player] or 0) < 1 then
			return
		end
		lastCheck[player] = now
		local data = DataService.get(player)
		if data ~= nil then
			check(player, data)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastCheck[player] = nil
	end)

	DailyService.registerAction("ClaimAchievement", function(player: Player, data: PlayerData, id: any)
		local def = if typeof(id) == "string" then BY_ID[id] else nil
		if def == nil then
			return { ok = false, reason = "Rejected" }
		end
		if data.achievements[def.id] ~= "unlocked" then
			return { ok = false, reason = if data.achievements[def.id] == "claimed" then "AlreadyClaimed" else "NotDone" }
		end
		data.achievements[def.id] = "claimed"
		DailyService.grant(player, data, { honor = def.honor, honorShare = def.honorShare }, "Achievement")
		return { ok = true }
	end)

	DailyService.addViewFields(function(_player: Player, data: PlayerData): { [string]: any }
		local list: { [string]: { current: number, status: string } } = {}
		for _, def in AchievementConfig.LIST do
			list[def.id] = {
				current = math.min(current(data, def), def.target),
				status = data.achievements[def.id] or "locked",
			}
		end
		return { achievements = list }
	end)
end

return AchievementService
