--!strict
-- Every RemoteEvent / RemoteFunction name in one place. The server creates them
-- (see RemoteService); the client looks them up with the helpers below.
--
-- Tap            client -> server   (tapCount: number)
-- ClientReady    client -> server   ()  "my scripts are loaded, send me my state"
-- UseAbility     client -> server   (abilityId: string)
-- FightBoss      client -> server   ()  start the next boss now (only valid right before a boss)
-- SetAutoAdvance client -> server   (enabled: boolean)
-- StateSync      server -> client   (snapshot: Types.Snapshot)
-- Notice         server -> client   (notice: Types.Notice)  boss won/lost banners
-- BuyTroop       client -> server, returns Types.BuyResult   (troopId: string, mode: Types.BuyMode)
-- UpgradeGear    client -> server, returns Types.BuyResult   (troopId: string, slot: GearSlot, mode: GearBuyMode)
-- OpenPack       client -> server, returns Types.PackResult  (mode: "Gold" | "Free" | "Hero")
-- Ascend         client -> server, returns Types.AscendResult ()
-- BuyHonorUpgrade client -> server, returns Types.BuyResult  (upgradeId: string)
-- ChooseFaction  client -> server, returns Types.FactionResult (factionId: string)
-- WarSync        server -> client   (war: Types.WarState)  shared standings, sent to everyone
-- ClanRequest    client -> server, returns Types.ClanResult (action: string, arg: any)
--                actions: Create(name, tag) Join(clanId) Leave Kick(userId) Promote(userId)
--                Demote(userId) SetOpen(bool) Browse Search(name) Donate(supplies) BuyPerk(perkId)
-- ClanSync       server -> client   (view: Types.ClanView)
-- RaidSync       server -> client   (view: Types.RaidView)  your clan's raid progress
-- LeaderboardSync server -> client  (boards: Types.Leaderboards)  global top lists
-- ProgressRequest client -> server, returns Types.ClanResult-style {ok, reason}
--                (action: "ClaimLogin" | "ClaimQuest" | "RerollQuest" | "ClaimBonus" | "ClaimAchievement", arg)
-- ProgressSync   server -> client   (view: Types.ProgressView)  login calendar, quests, achievements
-- SetPassToggle  client -> server   (passKey: string, enabled: boolean)  Auto Clicker / Auto Abilities on/off
-- SetSetting     client -> server   (key: string, value: string)  saved settings (see SettingsConfig)
--                (Robux purchases are prompted on the client with MarketplaceService and
--                 granted only by the server: ProcessReceipt / PromptGamePassPurchaseFinished)
--                (raid attacks use ClanRequest action "RaidAttack")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {
	FOLDER_NAME = "Remotes",

	Events = table.freeze({
		Tap = "Tap",
		ClientReady = "ClientReady",
		UseAbility = "UseAbility",
		FightBoss = "FightBoss",
		SetAutoAdvance = "SetAutoAdvance",
		StateSync = "StateSync",
		Notice = "Notice",
		WarSync = "WarSync",
		ClanSync = "ClanSync",
		RaidSync = "RaidSync",
		LeaderboardSync = "LeaderboardSync",
		SetPassToggle = "SetPassToggle",
		SetSetting = "SetSetting",
		ProgressSync = "ProgressSync",
	}),

	Functions = table.freeze({
		BuyTroop = "BuyTroop",
		UpgradeGear = "UpgradeGear",
		OpenPack = "OpenPack",
		Ascend = "Ascend",
		BuyHonorUpgrade = "BuyHonorUpgrade",
		ChooseFaction = "ChooseFaction",
		ClanRequest = "ClanRequest",
		ProgressRequest = "ProgressRequest",
	}),
}

local WAIT_TIMEOUT = 30

local function getFolder(): Instance
	local folder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME, WAIT_TIMEOUT)
	if folder == nil then
		error("Remotes folder never appeared. Is the server script running?", 3)
	end
	return folder
end

-- Client helper: waits for a RemoteEvent the server created.
function Remotes.waitForEvent(name: string): RemoteEvent
	local remote = getFolder():WaitForChild(name, WAIT_TIMEOUT)
	if remote == nil or not remote:IsA("RemoteEvent") then
		error(`RemoteEvent "{name}" not found`, 2)
	end
	return remote :: RemoteEvent
end

-- Client helper: waits for a RemoteFunction the server created.
function Remotes.waitForFunction(name: string): RemoteFunction
	local remote = getFolder():WaitForChild(name, WAIT_TIMEOUT)
	if remote == nil or not remote:IsA("RemoteFunction") then
		error(`RemoteFunction "{name}" not found`, 2)
	end
	return remote :: RemoteFunction
end

return table.freeze(Remotes)
