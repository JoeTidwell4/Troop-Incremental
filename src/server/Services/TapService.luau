--!strict
-- Receives batched taps from clients and turns them into commander damage.
--
-- Two limits stop autoclickers from breaking the economy:
--   1. Message rate: at most TAP_PACKETS_PER_SECOND tap messages per player.
--   2. Tap rate: at most TAP_MAX_PER_SECOND taps per player (TAP_BURST short burst).
-- Taps over the limit are silently dropped. An autoclicker can at best match a very
-- fast human, which is the intended ceiling.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Remotes = require(Shared:WaitForChild("Remotes"))
local CombatConfig = require(Shared:WaitForChild("Config"):WaitForChild("CombatConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local Validate = require(Server.Util.Validate)
local RemoteService = require(Services.RemoteService)
local CombatService = require(Services.CombatService)

local TapService = {}

function TapService.start()
	local packetLimiter = RateLimiter.new(CombatConfig.TAP_PACKETS_BURST, CombatConfig.TAP_PACKETS_PER_SECOND)
	local tapLimiter = RateLimiter.new(CombatConfig.TAP_BURST, CombatConfig.TAP_MAX_PER_SECOND)

	RemoteService.onEvent(Remotes.Events.Tap, packetLimiter, function(count: unknown): number?
		return Validate.integer(count, 1, CombatConfig.TAP_MAX_PER_PACKET)
	end, function(player: Player, count: number)
		local granted = tapLimiter:take(player, count)
		if granted > 0 then
			CombatService.applyTaps(player, granted)
		end
	end)
end

return TapService
