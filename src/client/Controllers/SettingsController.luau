--!strict
-- Player settings: graphics quality and sound. Saved on the server (SetSetting remote,
-- see SettingsService) so they stick between sessions; applied here on the client.
--
-- Graphics "Auto" = Low on phones/tablets and small windows (Layout.compact), else High.
-- Applying a profile sets Lighting.GlobalShadows and Visuals/Quality (which the
-- battlefield, effects and damage numbers read).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Config = Shared:WaitForChild("Config")
local SettingsConfig = require(Config:WaitForChild("SettingsConfig"))
local GraphicsConfig = require(Config:WaitForChild("GraphicsConfig"))
local Layout = require(Client:WaitForChild("UI"):WaitForChild("Layout"))
local Quality = require(Client:WaitForChild("Visuals"):WaitForChild("Quality"))
local StateController = require(script.Parent.StateController)
local AudioController = require(script.Parent.AudioController)

type Snapshot = Types.Snapshot

local values: { [string]: string } = table.clone(SettingsConfig.DEFAULTS)
local loadedSaved = false
local remote: RemoteEvent? = nil

local SettingsController = {
	Changed = Signal.new() :: Signal.Signal<()>,
}

-- "Low" or "High": what "Auto" means on this device, or the player's choice.
function SettingsController.graphicsQuality(): string
	local choice = values.graphics
	if choice == "Auto" then
		return if Layout.compact then "Low" else "High"
	end
	return choice
end

local function apply()
	local profile = GraphicsConfig.PROFILES[SettingsController.graphicsQuality()] or GraphicsConfig.PROFILES.High
	Lighting.GlobalShadows = profile.shadows
	Quality.set(profile)
	AudioController.setMode(values.sound :: AudioController.Mode)
	SettingsController.Changed:Fire()
end

function SettingsController.get(key: string): string
	return values[key] or SettingsConfig.DEFAULTS[key]
end

-- Changes a setting right away on this client and saves it on the server.
function SettingsController.set(key: string, value: string)
	local allowed = SettingsConfig.OPTIONS[key]
	if allowed == nil or table.find(allowed, value) == nil or values[key] == value then
		return
	end
	values[key] = value
	loadedSaved = true -- the player's choice wins over a saved value still on its way
	apply()
	if remote ~= nil then
		remote:FireServer(key, value)
	end
end

function SettingsController.start()
	remote = Remotes.waitForEvent(Remotes.Events.SetSetting)
	apply() -- defaults ("Auto") until the saved settings arrive with the first snapshot
	StateController.Changed:Connect(function(snapshot: Snapshot)
		if loadedSaved then
			return
		end
		loadedSaved = true
		local changed = false
		for key in SettingsConfig.OPTIONS do
			local saved = snapshot.settings[key]
			if saved ~= nil and saved ~= values[key] then
				values[key] = saved
				changed = true
			end
		end
		if changed then
			apply()
		end
	end)
end

return SettingsController
