--!strict
-- Server entry point: starts every service in dependency order.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Services
local Version = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Version")) :: string

local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local PlotService = require(Services.PlotService)
local CombatService = require(Services.CombatService)
local AbilityService = require(Services.AbilityService)
local HonorService = require(Services.HonorService)
local StageService = require(Services.StageService)
local TroopService = require(Services.TroopService)
local GearService = require(Services.GearService)
local PackService = require(Services.PackService)
local AscendService = require(Services.AscendService)
local TapService = require(Services.TapService)
local SyncService = require(Services.SyncService)
local OfflineService = require(Services.OfflineService)
local WarService = require(Services.WarService)
local FactionService = require(Services.FactionService)
local ClanService = require(Services.ClanService)
local ClanBankService = require(Services.ClanBankService)
local RaidService = require(Services.RaidService)
local LeaderboardService = require(Services.LeaderboardService)

RemoteService.start() -- first: creates the remotes everything else listens to
PlotService.start() -- gives each player a battlefield spot and places their avatar
CombatService.start()
AbilityService.start()
HonorService.start()
StageService.start() -- runs the fight loop; hears ProfileLoaded before Pack/Offline services
TroopService.start()
GearService.start()
PackService.start()
AscendService.start()
TapService.start()
SyncService.start()
OfflineService.start()
WarService.start() -- faction war points, cross-server standings, weekly winner
FactionService.start()
ClanService.start() -- clan membership (cross-server via DataStore + MessagingService)
ClanBankService.start() -- donations and perks
RaidService.start() -- weekly clan raid boss
LeaderboardService.start() -- global top lists + player list stats
DataService.start() -- last: starts loading players once every listener is connected

print(`[Server] Troop-Incremental {Version} booted`)
