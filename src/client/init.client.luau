--!strict
-- Client entry point: starts controllers, then UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Controllers = script.Controllers
local UI = script.UI
local Version = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Version")) :: string

local StateController = require(Controllers.StateController)
local InputController = require(Controllers.InputController)
local ShopController = require(Controllers.ShopController)
local AbilityController = require(Controllers.AbilityController)
local BattleController = require(Controllers.BattleController)
local BattlefieldController = require(Controllers.BattlefieldController)
local CommanderController = require(Controllers.CommanderController)
local FactionController = require(Controllers.FactionController)
local HudUI = require(UI.HudUI)
local ShopUI = require(UI.ShopUI)
local AbilityBarUI = require(UI.AbilityBarUI)
local NoticeUI = require(UI.NoticeUI)
local PackRevealUI = require(UI.PackRevealUI)
local AscendConfirmUI = require(UI.AscendConfirmUI)
local OfflineEarningsUI = require(UI.OfflineEarningsUI)
local FactionUI = require(UI.FactionUI)

ShopController.start()
InputController.start()
AbilityController.start()
BattleController.start()
BattlefieldController.start() -- waits for the server to assign a plot
CommanderController.start()
FactionController.start()
HudUI.start()
ShopUI.start()
AbilityBarUI.start()
NoticeUI.start()
PackRevealUI.start()
AscendConfirmUI.start()
OfflineEarningsUI.start()
FactionUI.start()
StateController.start() -- last: asks the server for state once everything is listening

print(`[Client] Troop-Incremental {Version} booted`)
