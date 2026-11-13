--!strict
-- The Studio-only test panel's server side (DebugConfig, UI/DebugPanelUI).
--
-- SAFETY: does nothing at all outside Studio: every request is refused there before
-- any command runs. Studio has its own separate saves
-- (Util/StoreNames), so these cheats can never reach the live game's players, clans or
-- leaderboards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = Shared:WaitForChild("Config")
local DebugConfig = require(Config:WaitForChild("DebugConfig"))
local DailyConfig = require(Config:WaitForChild("DailyConfig"))
local CommanderConfig = require(Config:WaitForChild("CommanderConfig"))
local BossConfig = require(Config:WaitForChild("BossConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local StoreNames = require(Server.Util.StoreNames)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local StageService = require(Services.StageService)
local DailyService = require(Services.DailyService)
local RaidService = require(Services.RaidService)
local ClanWarService = require(Services.ClanWarService)
local ClanShopService = require(Services.ClanShopService)

type PlayerData = Types.PlayerData
type Result = { ok: boolean, message: string }

local DebugService = {}

local function done(message: string): Result
	return { ok = true, message = message }
end

local function failed(message: string): Result
	return { ok = false, message = message }
end

-- Jumps to a stage. Bosses below it count as beaten (without handing out their free
-- packs, use "+10 packs" for that), and the all-time best goes up so troops unlock.
local function setStage(player: Player, data: PlayerData, stage: number): Result
	stage = math.clamp(math.floor(stage), 1, DebugConfig.MAX_STAGE)
	data.stage = stage
	data.killsInStage = 0
	data.highestStage = math.max(data.highestStage, stage)
	data.bestStage = math.max(data.bestStage, stage)
	local bossesBelow = ((stage - 1) // BossConfig.BOSS_EVERY) * BossConfig.BOSS_EVERY
	data.highestBossDefeated = math.max(data.highestBossDefeated, bossesBelow)
	data.packs.rewardedBossStage = math.max(data.packs.rewardedBossStage, bossesBelow)
	StageService.restart(player)
	return done(`Now on stage {stage}.`)
end

local ACTIONS: { [string]: (player: Player, data: PlayerData, arg: number?) -> Result } = {
	Stage = function(player, data, arg)
		return setStage(player, data, arg or data.stage)
	end,
	NextBoss = function(player, data)
		local every = BossConfig.BOSS_EVERY
		return setStage(player, data, (data.stage // every + 1) * every)
	end,
	Kill = function(player)
		StageService.debugKill(player)
		return done("Killed it.")
	end,
	FailBoss = function(player)
		if StageService.debugFailBoss(player) then
			return done("Boss lost.")
		end
		return failed("You're not in a boss fight.")
	end,
	GoldMinutes = function(player, data, arg)
		DailyService.grant(player, data, { goldMinutes = arg or 10 }, "Debug")
		return done(`+{arg} minutes of gold.`)
	end,
	GoldTimes = function(_player, data, arg)
		data.gold = BigNum.add(BigNum.mulNumber(data.gold, arg or 10), BigNum.fromNumber(1000))
		return done(`Gold x{arg}.`)
	end,
	Honor = function(_player, data, arg)
		local amount = BigNum.fromNumber(arg or 100)
		data.honor = BigNum.add(data.honor, amount)
		data.stats.honorEarned = BigNum.add(data.stats.honorEarned, amount)
		return done(`+{arg} Honor.`)
	end,
	Packs = function(_player, data, arg)
		data.packs.free += arg or 10
		return done(`+{arg} free packs.`)
	end,
	HeroChests = function(_player, data, arg)
		data.packs.hero += arg or 5
		return done(`+{arg} Hero Chests.`)
	end,
	Forge = function(_player, data, arg)
		data.packs.forge += arg or 3
		return done(`+{arg} Epic Forge tokens.`)
	end,
	ClanTokens = function(player, _data, arg)
		ClanShopService.addTokens(player, arg or 200)
		return done(`+{arg} Clan Tokens.`)
	end,
	NewDay = function(player, data)
		-- As if a day passed: the login reward is ready (streak continues) and new quests.
		local today = os.time() // DailyConfig.DAY_SECONDS
		data.daily.lastClaimDay = today - 1
		data.quests.day = -1
		DailyService.markDirty(player)
		return done("New day: login reward and quests are ready.")
	end,
	RaidAttacks = function(player)
		RaidService.debugRefill(player)
		return done("Raid attacks refilled.")
	end,
	ClanXp = function(player, _data, arg)
		if ClanWarService.debugAddXp(player, arg or 200) then
			return done(`+{arg} clan XP (shows up within a few seconds).`)
		end
		return failed("Join a clan first.")
	end,
	ClanQuests = function(player)
		if ClanWarService.debugFinishQuests(player) then
			return done("Clan quests filled (a few seconds to save).")
		end
		return failed("Join a clan first.")
	end,
	Wardrobe = function(_player, data)
		for itemId in CommanderConfig.ITEMS do
			data.commander.owned[itemId] = true
		end
		return done("Every wardrobe item unlocked.")
	end,
	Wipe = function(player)
		DataService.debugWipe(player)
		task.delay(0.5, function()
			if player.Parent == Players then
				player:Kick("Test save wiped. Stop and press Play again for a brand-new save.")
			end
		end)
		return done("Wiping...")
	end,
}

local function handle(player: Player, request: { action: string, arg: number? }): Result
	if not StoreNames.isStudio() then
		return failed("Studio only.")
	end
	local data = DataService.get(player)
	local action = ACTIONS[request.action]
	if data == nil or action == nil then
		return failed("Unknown command.")
	end
	local result = action(player, data, request.arg)
	DataService.markChanged(player)
	return result
end

function DebugService.start()
	-- Connected in the live game too, so stray requests get "Studio only." straight away
	-- instead of piling up unanswered; `handle` refuses everything outside Studio.
	RemoteService.onInvoke(
		Remotes.Functions.DebugCommand,
		RateLimiter.new(10, 5),
		function(action: unknown, arg: unknown): { action: string, arg: number? }?
			if typeof(action) ~= "string" then
				return nil
			end
			if arg ~= nil and (typeof(arg) ~= "number" or arg ~= arg or math.abs(arg :: number) > 1e12) then
				return nil
			end
			return { action = action :: string, arg = arg :: number? }
		end,
		handle,
		failed("Too fast.")
	)
	if not StoreNames.isStudio() then
		return
	end
	print("[DebugService] Studio test panel is on (Studio uses its own separate saves).")
end

return DebugService
