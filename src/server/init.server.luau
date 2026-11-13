--!strict
-- Server entry point. Services get started from here starting in Phase 1.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Version = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Version")) :: string

print(`[Server] Troop-Incremental {Version} booted`)
