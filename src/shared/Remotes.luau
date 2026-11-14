--!strict
-- Every RemoteEvent / RemoteFunction name in one place. The server creates them
-- (see RemoteService); the client looks them up with the helpers below.
--
-- Tap            client -> server   (tapCount: number)
-- ClientReady    client -> server   ()  "my scripts are loaded, send me my state"
-- UseAbility     client -> server   (abilityId: string)  must be equipped
-- SetAbilitySlot client -> server   (slot: number, abilityId: string)  equip (swaps if it's in another slot)
-- Crit           server -> client   (damage: BigNum)  some of your clicks just crit (for the big number)
-- FightBoss      client -> server   ()  start the next boss now (only valid right before a boss)
-- SetAutoAdvance client -> server   (enabled: boolean)
-- StateSync      server -> client   (snapshot: Types.Snapshot)
-- Notice         server -> client   (notice: Types.Notice)  boss won/lost banners
-- BuyTroop       client -> server, returns Types.BuyResult   (troopId: string, mode: Types.BuyMode)
-- UpgradeGear    client -> server, returns Types.BuyResult   (troopId: string, slot: GearSlot, mode: GearBuyMode)
-- OpenPack       client -> server, returns Types.PackResult  (mode: "Gold" | "Elite" | "Royal" | "Free" | "Hero")
-- UseForge       client -> server, returns Types.PackResult  (troopId: string, slot: GearSlot)  spends an Epic Forge token
-- OpenWardrobeChest client -> server, returns Types.ChestResult (chestId: string)  gold only
-- Ascend         client -> server, returns Types.AscendResult ()
-- BuyHonorUpgrade client -> server, returns Types.BuyResult  (upgradeId: string)
-- BuyAbilityUpgrade client -> server, returns Types.BuyResult (upgradeId: string)  AbilityConfig.UPGRADES, paid in Honor
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
-- WeakPoint      server -> client   (event: Types.WeakPointEvent)  boss/raid weak point spawned or cleared
-- ClanWarSync    server -> client   (view: Types.ClanWarView)  this week's Clan War standings
-- EquipCommander client -> server   (slot: string, itemId: string)  wear commander gear ("" = take off)
-- ClanChatSend   client -> server   (text: string)  a clan chat message
-- ClanChat       server -> client   (messages: { Types.ClanChatMessage }, replace: boolean)  new messages / history
-- HitWeakPoint   client -> server, returns Types.WeakPointResult (id: number)
-- Legacy         client -> server, returns Types.LegacyResult ()  the second prestige (LegacyService)
-- BuyCrownUpgrade client -> server, returns Types.BuyResult (upgradeId: string)  LegacyConfig.UPGRADES, paid in Crowns
-- SkillRequest   client -> server, returns {ok, reason}  (action: "Learn" | "Respec", nodeId: string?)  SkillService
-- GeneralRequest client -> server, returns {ok, reason, ...}  ("Recruit", 1|10) ("Field", slot, generalId|"") ("LevelUp", generalId, max)
-- RelicRequest   client -> server, returns {ok, reason}  (action, arg, extra): Equip(id) Unequip(slot) Upgrade(id) Reroll(id, line) Salvage(id) SalvageBelow(rarityOrder) Lock(id)
-- RelicSync      server -> client   (relics: Types.RelicsData)  the relic inventory, sent only when it changes
-- TutorialSeen   client -> server   (lessonId: string)  a tutorial lesson was finished or skipped
-- CommunityCheck client -> server   ()  the group join prompt closed: re-check membership (CommunityService)
-- FortuneRequest client -> server, returns Types.FortuneResult  ("Spin")  FortuneService
-- MerchantRequest client -> server, returns {ok, reason}  ("Buy", offerIndex)  MerchantService
-- ExpeditionRequest client -> server, returns Types.ExpeditionResult  ("Send", missionId, {generalIds}) ("Collect", slot) ("Reroll")
-- TowerRequest   client -> server, returns Types.TowerResult  ("Climb" | "Leave" | "Tribute")  TowerService
-- ChallengeRequest client -> server, returns Types.ChallengeResult  ("Start", challengeId) ("Leave")  ChallengeService
-- DebugCommand   client -> server, returns {ok, message}  (action: string, arg: any)  STUDIO ONLY
--                test panel (DebugConfig.ACTIONS); the server ignores it in the live game
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
		SetAbilitySlot = "SetAbilitySlot",
		Crit = "Crit",
		RelicSync = "RelicSync",
		TutorialSeen = "TutorialSeen",
		CommunityCheck = "CommunityCheck",
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
		WeakPoint = "WeakPoint",
		ClanWarSync = "ClanWarSync",
		EquipCommander = "EquipCommander",
		ClanChatSend = "ClanChatSend",
		ClanChat = "ClanChat",
		ProgressSync = "ProgressSync",
	}),

	Functions = table.freeze({
		BuyTroop = "BuyTroop",
		UpgradeGear = "UpgradeGear",
		OpenPack = "OpenPack",
		UseForge = "UseForge",
		OpenWardrobeChest = "OpenWardrobeChest",
		Ascend = "Ascend",
		BuyHonorUpgrade = "BuyHonorUpgrade",
		BuyAbilityUpgrade = "BuyAbilityUpgrade",
		HitWeakPoint = "HitWeakPoint",
		DebugCommand = "DebugCommand",
		Legacy = "Legacy",
		BuyCrownUpgrade = "BuyCrownUpgrade",
		SkillRequest = "SkillRequest",
		GeneralRequest = "GeneralRequest",
		RelicRequest = "RelicRequest",
		ChallengeRequest = "ChallengeRequest",
		TowerRequest = "TowerRequest",
		ExpeditionRequest = "ExpeditionRequest",
		FortuneRequest = "FortuneRequest",
		MerchantRequest = "MerchantRequest",
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
