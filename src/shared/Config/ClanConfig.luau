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

	-- Cross-server sync (see ClanStore).
	FLUSH_INTERVAL = if isStudio then 10 else 30, -- seconds between sending buffered donations
	POLL_INTERVAL = if isStudio then 15 else 60, -- seconds between re-reading clans with members online
	BROWSE_CACHE_SECONDS = 30,
	BROWSE_COUNT = 20,

	REQUESTS_PER_SECOND = 3,
	REQUESTS_BURST = 6,
}

return table.freeze(ClanConfig)
