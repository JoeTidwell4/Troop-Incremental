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
local StageService = require(Services.StageService)
local TroopService = require(Services.TroopService)
local GearService = require(Services.GearService)
local PackService = require(Services.PackService)
local TapService = require(Services.TapService)
local SyncService = require(Services.SyncService)

RemoteService.start() -- first: creates the remotes everything else listens to
PlotService.start() -- gives each player a battlefield spot and places their avatar
CombatService.start()
AbilityService.start()
StageService.start() -- runs the fight loop; hears ProfileLoaded before PackService
TroopService.start()
GearService.start()
PackService.start()
TapService.start()
SyncService.start()
DataService.start() -- last: starts loading players once every listener is connected

print(`[Server] Troop-Incremental {Version} booted`)
