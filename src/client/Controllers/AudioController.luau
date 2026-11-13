--!strict
-- Plays sound effects and music on this player's client.
-- Sounds come from AudioConfig; any sound with an empty id is just silent.
-- Most sounds are triggered by watching the state the server sends (a kill happened,
-- troops went up, a boss started...), so gameplay code doesn't need to know about audio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local Controllers = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Config = Shared:WaitForChild("Config")
local AudioConfig = require(Config:WaitForChild("AudioConfig"))
local AbilityConfig = require(Config:WaitForChild("AbilityConfig"))
local UIKit = require(Client.UI.UIKit)
local StateController = require(Controllers.StateController)
local InputController = require(Controllers.InputController)

type Snapshot = Types.Snapshot

export type Mode = "All" | "SfxOnly" | "Off"

local sounds: { [string]: Sound } = {}
local music: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}
local currentTrack: string? = nil
local mode: Mode = "All"

local AudioController = {}

local function makeSound(name: string, def: Types.SoundDef, parent: Instance, looped: boolean): Sound?
	if def.id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = def.id
	sound.Volume = def.volume
	sound.Looped = looped
	sound.Parent = parent
	return sound
end

-- Plays a sound effect by name (see AudioConfig.SOUNDS). Safe to call for silent sounds.
function AudioController.play(name: string)
	if mode == "Off" then
		return
	end
	local sound = sounds[name]
	if sound == nil then
		return
	end
	local now = os.clock()
	if now - (lastPlayed[name] or 0) < AudioConfig.MIN_GAP then
		return
	end
	lastPlayed[name] = now
	-- PlayOnRemove on a clone lets the same sound overlap itself (fast clicks).
	local copy = sound:Clone()
	copy.Parent = sound.Parent
	copy.PlayOnRemove = true
	copy:Destroy()
end

-- Switches the background track ("Main", "Boss", "Raid"), fading between them.
function AudioController.setMusic(trackName: string)
	if currentTrack == trackName then
		return
	end
	currentTrack = trackName
	local fade = TweenInfo.new(AudioConfig.MUSIC_FADE_SECONDS)
	for name, track in music do
		local def = AudioConfig.MUSIC[name]
		if name == trackName and mode == "All" then
			if not track.IsPlaying then
				track.Volume = 0
				track:Play()
			end
			TweenService:Create(track, fade, { Volume = def.volume }):Play()
		elseif track.IsPlaying then
			local out = TweenService:Create(track, fade, { Volume = 0 })
			out.Completed:Connect(function()
				if currentTrack ~= name then
					track:Stop()
				end
			end)
			out:Play()
		end
	end
end

function AudioController.getMode(): Mode
	return mode
end

-- Sets the sound mode (saved in Settings): "All", "SfxOnly" (music off) or "Off".
function AudioController.setMode(newMode: Mode)
	if newMode == mode then
		return
	end
	mode = newMode
	local track = currentTrack or "Main"
	currentTrack = nil -- force setMusic to re-apply
	AudioController.setMusic(track)
end

local function trackFor(snapshot: Snapshot): string
	if snapshot.encounter == "Boss" then
		return "Boss"
	elseif snapshot.encounter == "Raid" then
		return "Raid"
	end
	return "Main"
end

local function onStateChanged(snapshot: Snapshot, previous: Snapshot?)
	AudioController.setMusic(trackFor(snapshot))
	if previous == nil then
		return
	end

	if snapshot.encounter ~= previous.encounter then
		if snapshot.encounter == "Boss" then
			AudioController.play("BossStart")
		elseif snapshot.encounter == "Raid" then
			AudioController.play("RaidStart")
		end
	end
	if snapshot.totalKills > previous.totalKills then
		AudioController.play("Kill")
	end
	if snapshot.ascensions > previous.ascensions then
		AudioController.play("Ascend")
	end

	for troopId, count in snapshot.troops do
		if count > (previous.troops[troopId] or 0) then
			AudioController.play("Buy")
			break
		end
	end
	for troopId, troopGear in snapshot.gear do
		local before = previous.gear[troopId]
		if before ~= nil and (troopGear.weapon.level > before.weapon.level or troopGear.armor.level > before.armor.level) then
			AudioController.play("Upgrade")
			break
		end
	end

	-- An ability was used when its readyAt time moves forward.
	for _, abilityId in AbilityConfig.ORDER do
		local now, before = snapshot.abilities[abilityId], previous.abilities[abilityId]
		if now ~= nil and (before == nil or now.readyAt > before.readyAt) then
			AudioController.play(abilityId)
		end
	end
end

function AudioController.start()
	local folder = Instance.new("Folder")
	folder.Name = "GameAudio"
	folder.Parent = SoundService

	for name, def in AudioConfig.SOUNDS do
		local sound = makeSound(name, def, folder, false)
		if sound ~= nil then
			sounds[name] = sound
		end
	end
	for name, def in AudioConfig.MUSIC do
		local track = makeSound(name, def, folder, true)
		if track ~= nil then
			music[name] = track
		end
	end

	UIKit.hooks.onButtonClick = function()
		AudioController.play("UIClick")
	end
	InputController.Tapped:Connect(function()
		AudioController.play("Hit")
	end)
	StateController.Changed:Connect(onStateChanged)
	StateController.Notice:Connect(function(notice: Types.Notice)
		if notice.kind == "BossDefeated" then
			AudioController.play("BossWin")
		elseif notice.kind == "BossFailed" then
			AudioController.play("BossFail")
		elseif notice.kind == "RaidRewards" or notice.kind == "ClanWarRewards" or notice.kind == "CommanderItem" or notice.kind == "ClanJoined" then
			AudioController.play("Reward")
		end
	end)

	AudioController.setMusic("Main")
end

return AudioController
