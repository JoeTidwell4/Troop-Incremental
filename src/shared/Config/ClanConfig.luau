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
	-- Honor: `honorShare` of an Ascend's Honor at your best stage, at least `honor`.
	WAR_REWARDS = {
		{ maxRank = 1, honor = 25, honorShare = 0.5, heroChests = 2 },
		{ maxRank = 3, honor = 15, honorShare = 0.3, heroChests = 1 },
		{ maxRank = 10, honor = 8, honorShare = 0.15, packs = 1 },
	} :: { { maxRank: number, honor: number?, honorShare: number?, heroChests: number?, packs: number? } },
	WAR_PARTICIPATION_REWARD = { honor = 3, honorShare = 0.05 } :: { honor: number?, honorShare: number? },

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
	MVP_HONOR_SHARE = 0.1,

	-- Battlefield banner (Phase 11d A): extra decorations unlock at these clan levels.
	BANNER_LEVELS = { finial = 5, pennants = 10, glow = 15, sparkles = 20, crown = 25 } :: { [string]: number },

	-- Clan Tokens (Phase 11d D): a personal currency (kept on Ascend) for the clan shop.
	TOKENS_FOR_RANK = { { maxRank = 1, tokens = 50 }, { maxRank = 3, tokens = 30 }, { maxRank = 10, tokens = 20 } } :: {
		{ maxRank: number, tokens: number }
	},
	TOKENS_PARTICIPATION = 5, -- clan reached WAR_PARTICIPATION_XP but wasn't on the board
	TOKENS_MVP = 10,
	TOKENS_HEAD_TO_HEAD_WIN = 15,
	HEAD_TO_HEAD_WIN_HONOR = 5,
	HEAD_TO_HEAD_HONOR_SHARE = 0.1,
	-- The clan shop. kind "gear" = commander gear (CommanderConfig, unlock kind "clanShop",
	-- bought once); "heroChests" / "packs" = buy as often as you like.
	SHOP = {
		{ id = "ClanWarhelm", kind = "gear", cost = 120 },
		{ id = "ClanCloak", kind = "gear", cost = 120 },
		{ id = "ClanBlade", kind = "gear", cost = 150 },
		{ id = "ClanStandard", kind = "gear", cost = 120 },
		{ id = "HeroChest", kind = "heroChests", amount = 1, cost = 40, displayName = "Hero Chest (Epic+ gear pack)" },
		{ id = "FreePacks", kind = "packs", amount = 2, cost = 15, displayName = "2 Free Gear Packs" },
	} :: { { id: string, kind: string, cost: number, amount: number?, displayName: string? } },

	-- Weekly clan quests (Phase 11d C): 3 shared goals per Clan War week, picked from this
	-- pool by clan + week. target = perMember x members (at least QUEST_MIN_MEMBERS), fixed
	-- when the week's first XP is saved. Members who gave at least QUEST_MIN_XP clan XP
	-- that week can claim each finished quest once (before the week ends).
	QUEST_POOL = {
		{ key = "Bosses", activity = "BossWin", text = "Beat {n} bosses", perMember = 15 },
		{ key = "Kills", activity = "Kill", text = "Defeat {n} enemies", perMember = 4000 },
		{ key = "Raids", activity = "RaidAttack", text = "Make {n} raid attacks", perMember = 3 },
		{ key = "WeakPoints", activity = "WeakPoint", text = "Hit {n} weak points", perMember = 20 },
		{ key = "Donations", activity = "Donate", text = "Donate {n} Supplies", perMember = 150 },
		{ key = "Packs", activity = "PackOpen", text = "Open {n} packs", perMember = 5 },
		{ key = "Abilities", activity = "Ability", text = "Use abilities {n} times", perMember = 30 },
	} :: { { key: string, activity: string, text: string, perMember: number } },
	QUESTS_PER_WEEK = 3,
	QUEST_MIN_MEMBERS = 3,
	QUEST_MIN_XP = if isStudio then 5 else 20,
	QUEST_REWARD = { tokens = 10, goldMinutes = 20 } :: { tokens: number, goldMinutes: number },

	-- Head-to-head (Phase 11d I): each week clans are paired by LAST week's final ranking
	-- (1 v 2, 3 v 4, ... among the top WAR_RESULT_COUNT). More clan XP that week wins; an
	-- unpaired clan with WAR_PARTICIPATION_XP gets a free win (bye).
	WAR_RESULT_COUNT = 50, -- clans kept in each week's locked-in result (board shows WAR_TOP_COUNT)
	OPPONENT_REFRESH = if isStudio then 20 else 120, -- seconds between reads of an opponent's score

	-- Clan chat (Phase 11d H). Filtered with Roblox's strictest (broadcast) filter on the
	-- sender's server before it goes anywhere; players who can't chat (privacy settings,
	-- parental controls) can't send, and messages only reach members Roblox lets that
	-- sender chat with.
	CHAT_MAX_LENGTH = 150,
	CHAT_HISTORY = 30, -- messages kept (1 day) and shown when you open the chat
	CHAT_HISTORY_SECONDS = 86400,
	CHAT_RATE_BURST = 3,
	CHAT_RATE_PER_SECOND = 0.5, -- one message every 2 seconds on average

	-- Cross-server sync (see ClanStore).
	FLUSH_INTERVAL = if isStudio then 10 else 30, -- seconds between sending buffered donations
	POLL_INTERVAL = if isStudio then 15 else 60, -- seconds between re-reading clans with members online
	BROWSE_CACHE_SECONDS = 30,
	BROWSE_COUNT = 20,

	REQUESTS_PER_SECOND = 3,
	REQUESTS_BURST = 6,
}

return table.freeze(ClanConfig)
