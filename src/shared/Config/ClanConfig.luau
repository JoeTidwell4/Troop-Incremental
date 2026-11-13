--!strict
-- Clans: membership, roles, the clan bank (Supplies), and clan perks. Safe to tweak.
--
-- Supplies: you donate gold, but it's converted to Supplies at "how many kills that gold is
-- worth at your best stage this run" (gold / gold-per-kill). So 100 Supplies costs a new
-- player and a veteran the same effort. Each member can donate up to DONATION_DAILY_CAP
-- Supplies per day, so dumping gold right before Ascending can't flood the bank.
--
-- CLAN_REQUIRES_SAME_FACTION: when true, a clan takes its creator's faction, only that
-- faction can join, and members must leave their clan before switching faction.

local RunService = game:GetService("RunService")

local Types = require(script.Parent.Parent.Types)

local isStudio = RunService:IsStudio()

local ClanConfig = {
	CLAN_REQUIRES_SAME_FACTION = false,

	MAX_MEMBERS = 20,
	CREATE_MIN_BEST_STAGE = 20,
	NAME_MIN_LENGTH = 3,
	NAME_MAX_LENGTH = 20,
	TAG_MIN_LENGTH = 2,
	TAG_MAX_LENGTH = 4,

	DONATION_DAILY_CAP = 500, -- Supplies per member per day
	DONATION_DAY_SECONDS = if isStudio then 300 else 86400,
	DONATION_PRESETS = { 10, 50, 100 } :: { number },

	-- Clan perks, bought with Supplies by the Leader or Officers. Multipliers apply per level.
	PERK_ORDER = { "Muster", "Treasury", "Bulwark", "Warbanners" } :: { string },
	PERKS = {
		Muster = {
			id = "Muster",
			displayName = "Muster",
			description = "x1.1 army damage per level",
			baseCost = 200,
			costGrowth = 1.6,
			maxLevel = 10,
			damageMultiplier = 1.1,
		},
		Treasury = {
			id = "Treasury",
			displayName = "Treasury",
			description = "x1.1 gold per level",
			baseCost = 200,
			costGrowth = 1.6,
			maxLevel = 10,
			goldMultiplier = 1.1,
		},
		Bulwark = {
			id = "Bulwark",
			displayName = "Bulwark",
			description = "x1.1 army HP per level",
			baseCost = 200,
			costGrowth = 1.6,
			maxLevel = 10,
			armyHpMultiplier = 1.1,
		},
		Warbanners = {
			id = "Warbanners",
			displayName = "Warbanners",
			description = "x1.1 clan raid damage per level",
			baseCost = 300,
			costGrowth = 1.6,
			maxLevel = 10,
			raidMultiplier = 1.1,
		},
	} :: { [string]: Types.ClanPerkDef },

	-- Clan XP and levels (Phase 10c, ClanWarService). Members earn XP for their clan by
	-- playing; each member adds at most XP_DAILY_CAP per day so one grinder (or alts)
	-- can't carry a clan. Kill and Donate XP are per kill / per Supply (fractions add up).
	XP_PER_ACTIVITY = {
		BossWin = 10,
		RaidAttack = 15,
		WeakPoint = 2,
		Kill = 0.02,
		Donate = 0.2,
	} :: { [string]: number },
	XP_DAILY_CAP = if isStudio then 60 else 200,
	-- XP to go from level L to L+1 = LEVEL_XP_BASE * LEVEL_XP_GROWTH ^ (L - 1).
	LEVEL_XP_BASE = if isStudio then 30 else 500,
	LEVEL_XP_GROWTH = 1.15,
	MAX_LEVEL = 25,
	LEVEL_GOLD_BONUS = 0.02, -- +2% gold per clan level for every member
	LEVEL_DAMAGE_BONUS = 0.02, -- +2% damage per clan level

	-- Weekly Clan War league: clans ranked by XP earned that week (Monday 00:00 UTC).
	WAR_WEEK_ANCHOR = 345600,
	WAR_WEEK_SECONDS = if isStudio then 600 else 7 * 86400,
	WAR_FINALIZE_DELAY = if isStudio then 60 else 600, -- wait for late flushes before results
	WAR_TOP_COUNT = 10,
	WAR_BOARD_REFRESH = if isStudio then 20 else 120, -- seconds between leaderboard reads
	WAR_MIN_CONTRIBUTION = if isStudio then 10 else 100, -- your XP to that clan that week, to get rewards
	WAR_PARTICIPATION_XP = if isStudio then 30 else 500, -- clan XP that week for the small reward
	WAR_REWARDS = {
		{ maxRank = 1, honor = 25, heroChests = 2 },
		{ maxRank = 3, honor = 15, heroChests = 1 },
		{ maxRank = 10, honor = 8, packs = 1 },
	} :: { { maxRank: number, honor: number?, heroChests: number?, packs: number? } },
	WAR_PARTICIPATION_REWARD = { honor = 3 } :: { honor: number? },

	-- Customization (Phase 11d B): picked by the Leader or Officers. Shown in the clan
	-- window and on every member's battlefield banner. Emblems are emoji so they work in
	-- the UI and on the 3D banner without uploaded images.
	COLORS = {
		Color3.fromRGB(200, 55, 50),
		Color3.fromRGB(230, 130, 40),
		Color3.fromRGB(235, 200, 60),
		Color3.fromRGB(70, 170, 80),
		Color3.fromRGB(50, 160, 170),
		Color3.fromRGB(60, 110, 210),
		Color3.fromRGB(120, 70, 200),
		Color3.fromRGB(200, 80, 170),
		Color3.fromRGB(60, 60, 70),
		Color3.fromRGB(235, 235, 240),
	} :: { Color3 },
	EMBLEMS = { "⚔️", "🛡️", "👑", "⭐", "🔥", "💀", "🐉", "🦅", "🐺", "🌙", "⚡", "💎" } :: { string },
	MOTTO_MAX_LENGTH = 60,

	-- Join requests (Phase 11d E): closed clans take requests instead of instant joins.
	MAX_REQUESTS = 20, -- pending requests a clan keeps
	REQUEST_EXPIRE_SECONDS = 7 * 86400,

	-- Member MVP (Phase 11d F): last week's top contributor gets this much Honor (with the
	-- Clan War rewards) and a star in the member list.
	MVP_HONOR = 5,

	-- Battlefield banner (Phase 11d A): extra decorations unlock at these clan levels.
	BANNER_LEVELS = { finial = 5, pennants = 10, glow = 15, sparkles = 20, crown = 25 } :: { [string]: number },

	-- Cross-server sync (see ClanStore).
	FLUSH_INTERVAL = if isStudio then 10 else 30, -- seconds between sending buffered donations
	POLL_INTERVAL = if isStudio then 15 else 60, -- seconds between re-reading clans with members online
	BROWSE_CACHE_SECONDS = 30,
	BROWSE_COUNT = 20,

	REQUESTS_PER_SECOND = 3,
	REQUESTS_BURST = 6,
}

return table.freeze(ClanConfig)
