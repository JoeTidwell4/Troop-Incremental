--!strict
-- The graphics profile visuals should use right now (see GraphicsConfig). Set by
-- SettingsController; read by Environment, Effects, BattlefieldController and
-- DamageNumbersController. Changed fires when the player switches quality.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GraphicsConfig = require(Shared:WaitForChild("Config"):WaitForChild("GraphicsConfig"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

type Profile = GraphicsConfig.Profile

local current: Profile = GraphicsConfig.PROFILES.High

local Quality = {
	Changed = Signal.new() :: Signal.Signal<Profile>,
}

function Quality.get(): Profile
	return current
end

function Quality.set(profile: Profile)
	if profile == current then
		return
	end
	current = profile
	Quality.Changed:Fire(profile)
end

return Quality
