--!strict
-- Server entry point: starts every service in dependency order.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Services
local Version = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Version")) :: string

-- This is a commander game viewed from a fixed camera, so players don't get an avatar (yet:
-- Phase 2b adds the avatar as the commander on the battlefield).
Players.CharacterAutoLoads = false

local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local CombatService = require(Services.CombatService)
local AbilityService = require(Services.AbilityService)
local StageService = require(Services.StageService)
local TroopService = require(Services.TroopService)
local TapService = require(Services.TapService)
local SyncService = require(Services.SyncService)

RemoteService.start() -- first: creates the remotes everything else listens to
CombatService.start()
AbilityService.start()
StageService.start() -- runs the fight loop; hears ProfileLoaded for every player
TroopService.start()
TapService.start()
SyncService.start()
DataService.start() -- last: starts loading players once every listener is connected

print(`[Server] Troop-Incremental {Version} booted`)
