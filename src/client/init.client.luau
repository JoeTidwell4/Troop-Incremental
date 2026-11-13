--!strict
-- Client entry point. Controllers and UI get started from here starting in Phase 1.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Version = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Version")) :: string

print(`[Client] Troop-Incremental {Version} booted`)
