--!strict
-- Commander Level + skill tree (SkillConfig, Phase 13b).
--
-- XP comes from beating bosses (StageService.BossDefeated), and from activities other
-- services record: "AscendStage" (Ascend), "QuestClaim" (daily quest, amount =
-- difficulty), "AchievementClaim", "WeakPoint". The level never resets.
--
-- Learning and respecs go through one `SkillRequest` remote. All the rules (tiers, forks,
-- points) live in Formulas.canLearnSkill so the UI shows exactly what the server allows.
-- Skill effects are read by other services through Formulas.skillEffects(data.skills.ranks)
-- (crits, golden enemies, boss timer/gold, offline, Ascend Honor, ability cooldowns and
-- durations, weak points, loadout slots); the global multipliers are a ModifierService
-- source here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = Shared:WaitForChild("Config")
local SkillConfig = require(Config:WaitForChild("SkillConfig"))
local AbilityConfig = require(Config:WaitForChild("AbilityConfig"))
local DailyConfig = require(Config:WaitForChild("DailyConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)
local ModifierService = require(Services.ModifierService)
local CombatService = require(Services.CombatService)
local StageService = require(Services.StageService)
local ActivityService = require(Services.ActivityService)

type PlayerData = Types.PlayerData
type Result = { ok: boolean, reason: string? }

local SkillService = {}

-- Re-entry guard for the modifier source (army HP itself asks ModifierService).
local computing: { [Player]: boolean } = {}

local function today(): number
	return os.time() // DailyConfig.DAY_SECONDS
end

-- Adds Commander XP and announces any level gained.
function SkillService.addXp(player: Player, xp: number)
	local data = DataService.get(player)
	if data == nil or xp <= 0 then
		return
	end
	local before = Formulas.commanderLevel(data.commanderXp)
	data.commanderXp += xp
	local after = Formulas.commanderLevel(data.commanderXp)
	if after > before then
		RemoteService.fireClient(Remotes.Events.Notice, player, { kind = "LevelUp", stage = 0, level = after })
	end
	DataService.markChanged(player)
end

-- Grand Tactician: fill a newly opened ability slot with something not equipped yet.
local function fillLoadout(data: PlayerData)
	local slots = Formulas.loadoutSlots(data.skills.ranks)
	local loadout = data.abilityLoadout
	for _, abilityId in AbilityConfig.ORDER do
		if #loadout >= slots then
			break
		end
		if table.find(loadout, abilityId) == nil then
			table.insert(loadout, abilityId)
		end
	end
	while #loadout > slots do
		table.remove(loadout)
	end
end

local function learn(data: PlayerData, nodeId: string): Result
	local level = Formulas.commanderLevel(data.commanderXp)
	local ok, reason = Formulas.canLearnSkill(data.skills.ranks, level, nodeId)
	if not ok then
		return { ok = false, reason = reason }
	end
	data.skills.ranks[nodeId] = (data.skills.ranks[nodeId] or 0) + 1
	fillLoadout(data)
	return { ok = true }
end

local function respec(data: PlayerData): Result
	if data.skills.respecDay == today() then
		return { ok = false, reason = "RespecUsed" }
	end
	if next(data.skills.ranks) == nil then
		return { ok = false, reason = "NothingToReset" }
	end
	data.skills.ranks = {}
	data.skills.respecDay = today()
	fillLoadout(data) -- a 4th slot goes away with Grand Tactician
	return { ok = true }
end

local function handle(player: Player, request: { action: string, nodeId: string? }): Result
	local data = DataService.get(player)
	if data == nil then
		return { ok = false, reason = "NotLoaded" }
	end
	local result = if request.action == "Learn" and request.nodeId ~= nil
		then learn(data, request.nodeId)
		elseif request.action == "Respec" then respec(data)
		else { ok = false, reason = "Rejected" }
	if result.ok then
		DataService.markChanged(player)
	end
	return result
end

function SkillService.start()
	-- XP sources.
	StageService.BossDefeated:Connect(function(player: Player, bossStage: number, firstClear: boolean)
		SkillService.addXp(player, Formulas.bossXp(bossStage, firstClear))
	end)
	ActivityService.Recorded:Connect(function(player: Player, activity: string, amount: number)
		local xp = SkillConfig.XP
		if activity == "AscendStage" then
			SkillService.addXp(player, math.floor(amount * xp.ASCEND_PER_STAGE))
		elseif activity == "QuestClaim" then
			SkillService.addXp(player, xp.QUEST[amount] or xp.QUEST[1])
		elseif activity == "AchievementClaim" then
			SkillService.addXp(player, xp.ACHIEVEMENT * amount)
		elseif activity == "WeakPoint" then
			SkillService.addXp(player, xp.WEAK_POINT * amount)
		end
	end)

	-- Global multipliers from skills (and the boss-only ones: Giant Slayer, Last Stand).
	ModifierService.register(function(player: Player): ModifierService.PartialModifiers?
		local data = DataService.get(player)
		if data == nil then
			return nil
		end
		local effects = Formulas.skillEffects(data.skills.ranks)
		local damage = 1 + effects.damage
		if not computing[player] then
			computing[player] = true
			local encounter = StageService.getEncounter(player)
			if encounter ~= nil and encounter.kind ~= "Normal" then
				damage *= 1 + effects.bossDamageDealt
				if effects.lastStand > 0 and encounter.kind == "Boss" then
					local maxHp = CombatService.getMaxHp(player)
					local hp = StageService.getArmyHp(player)
					if not BigNum.isZero(maxHp) and BigNum.toNumber(BigNum.div(hp, maxHp)) < SkillConfig.LAST_STAND_HP then
						damage *= 1 + effects.lastStand
					end
				end
			end
			computing[player] = nil
		end
		return {
			damage = damage,
			armyHp = math.max(0.1, 1 + effects.armyHp),
			gold = 1 + effects.gold,
			tap = 1 + effects.tap,
			bossDamage = math.max(0.1, 1 + effects.bossDamageTaken),
		}
	end)

	SyncService.addSnapshotFields(function(_player: Player, data: PlayerData): { [string]: any }
		return {
			commanderXp = data.commanderXp,
			skillRanks = data.skills.ranks,
			respecReady = data.skills.respecDay ~= today(),
		}
	end)

	RemoteService.onInvoke(
		Remotes.Functions.SkillRequest,
		RateLimiter.new(SkillConfig.REQUESTS_BURST, SkillConfig.REQUESTS_PER_SECOND),
		function(action: unknown, nodeId: unknown): { action: string, nodeId: string? }?
			if action ~= "Learn" and action ~= "Respec" then
				return nil
			end
			if action == "Learn" and (typeof(nodeId) ~= "string" or SkillConfig.NODES[nodeId :: string] == nil) then
				return nil
			end
			return { action = action :: string, nodeId = if typeof(nodeId) == "string" then nodeId else nil }
		end,
		handle,
		{ ok = false, reason = "Rejected" } :: Result
	)
end

return SkillService
