--!strict
-- Saves player settings (graphics quality, sound) in the profile and sends them to the
-- client in the snapshot. Settings are cosmetic; they never affect gameplay.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SettingsConfig = require(Shared:WaitForChild("Config"):WaitForChild("SettingsConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local Validate = require(Server.Util.Validate)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)

type PlayerData = Types.PlayerData
type SettingRequest = { key: string, value: string }

local SettingsService = {}

-- A copy with every setting filled in (old saves or bad values fall back to the default).
local function current(data: PlayerData): { [string]: string }
	local result: { [string]: string } = {}
	for key, allowed in SettingsConfig.OPTIONS do
		local value = data.settings[key]
		result[key] = if value ~= nil and table.find(allowed, value) ~= nil then value else SettingsConfig.DEFAULTS[key]
	end
	return result
end

function SettingsService.start()
	SyncService.addSnapshotFields(function(_player: Player, data: PlayerData): { [string]: any }
		return { settings = current(data) }
	end)

	RemoteService.onEvent(
		Remotes.Events.SetSetting,
		RateLimiter.new(SettingsConfig.REQUESTS_BURST, SettingsConfig.REQUESTS_PER_SECOND),
		function(key: unknown, value: unknown): SettingRequest?
			local validKey = Validate.keyOf(key, SettingsConfig.OPTIONS)
			if validKey == nil then
				return nil
			end
			local validValue = Validate.oneOf(value, SettingsConfig.OPTIONS[validKey])
			if validValue == nil then
				return nil
			end
			return { key = validKey, value = validValue }
		end,
		function(player: Player, request: SettingRequest)
			local data = DataService.get(player)
			if data ~= nil and data.settings[request.key] ~= request.value then
				data.settings[request.key] = request.value
				DataService.markChanged(player)
			end
		end
	)
end

return SettingsService
