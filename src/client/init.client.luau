--!strict
-- Client entry point: starts controllers, then UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Controllers = script.Controllers
local UI = script.UI
local Version = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Version")) :: string

local StateController = require(Controllers.StateController)
local InputController = require(Controllers.InputController)
local TroopController = require(Controllers.TroopController)
local BattlefieldController = require(Controllers.BattlefieldController)
local HudUI = require(UI.HudUI)
local TroopShopUI = require(UI.TroopShopUI)

TroopController.start()
InputController.start()
BattlefieldController.start()
HudUI.start()
TroopShopUI.start()
StateController.start() -- last: asks the server for state once everything is listening

print(`[Client] Troop-Incremental {Version} booted`)
