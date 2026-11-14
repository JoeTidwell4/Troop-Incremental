--!strict
-- The Mystery Merchant (camp visitor). Safe to tweak.
--
-- Shows up in the camp at a random time GAP_MIN..GAP_MAX after his last visit (real time,
-- so it counts while you're offline; if he was due while you were away he's there when you
-- log in), stays STAY seconds, brings OFFER_COUNT different offers and sells each once.
-- What's random is WHICH offers he brings; what you buy is exactly what's on the label
-- (no mystery boxes). Prices: gold (kills' worth at your ALL-TIME best stage, because
-- what he sells is kept on Ascend), Relic Dust, Honor. Never Robux.

local RunService = game:GetService("RunService")

local Types = require(script.Parent.Parent.Types)

local isStudio = RunService:IsStudio()

local MerchantConfig = {
	UNLOCK_STAGE = 30,
	FIRST_VISIT = if isStudio then 20 else 300, -- seconds after unlocking: meet him soon
	GAP_MIN = if isStudio then 60 else 3 * 3600,
	GAP_MAX = if isStudio then 120 else 5 * 3600,
	STAY = if isStudio then 180 else 45 * 60,
	OFFER_COUNT = 4,

	-- Offer kinds (weight = how often one shows up; each kind at most once per visit).
	--   General   1 copy of a specific General, paid in Honor (share of an Ascend's Honor
	--             at your best stage, by rarity; minimum `honorMin`)
	--   Relic     a relic of a shown slot + set + rarity (stat lines random), paid in Dust
	--   Scrolls / HeroChest / DustBundle / Cosmetic   paid in gold (`kills`)
	KINDS = {
		{ id = "General", weight = 30 },
		{ id = "Relic", weight = 25 },
		{ id = "Scrolls", weight = 20 },
		{ id = "HeroChest", weight = 15 },
		{ id = "DustBundle", weight = 20 },
		{ id = "Cosmetic", weight = 12 },
	} :: { { id: string, weight: number } },
	GENERAL_RARITY = { Rare = 50, Epic = 35, Legendary = 13, Mythic = 2 } :: { [string]: number },
	GENERAL_HONOR = {
		Rare = { share = 0.08, min = 5 },
		Epic = { share = 0.15, min = 10 },
		Legendary = { share = 0.4, min = 30 },
		Mythic = { share = 1.2, min = 100 },
	} :: { [string]: { share: number, min: number } },
	RELIC = {
		{ rarity = "Epic", weight = 70, dust = 300 },
		{ rarity = "Legendary", weight = 30, dust = 900 },
	} :: { { rarity: string, weight: number, dust: number } },
	SCROLLS = { amount = 3, kills = 400 },
	HERO_CHEST = { kills = 250 },
	DUST_BUNDLE = { amount = 300, kills = 200 },
	COSMETIC_KILLS = 1500,
	-- Commander items only he sells (looks only: no stats). CommanderConfig unlock "merchant".
	COSMETICS = { "WandererHood", "StarweaveCloak", "MoonsilverSaber", "LanternPack" } :: { string },

	REQUESTS_PER_SECOND = 2,
	REQUESTS_BURST = 4,
}

return table.freeze(MerchantConfig)
