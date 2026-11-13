--!strict
-- Sound effects and music. Client only; nothing here affects gameplay.
--
-- HOW TO ADD A SOUND: put its asset id in `id`, like "rbxassetid://1234567890".
-- An empty id ("") means that sound is simply silent, so it's safe to fill these in
-- one at a time. Volume is 0 to 1.
--
-- Note: Roblox only plays audio your game is allowed to use (audio uploaded by Roblox
-- itself, by you, or shared with your game). If a sound doesn't play, Output will show a
-- warning about that asset.

local Types = require(script.Parent.Parent.Types)

type SoundDef = Types.SoundDef

local AudioConfig = {
	SOUNDS = {
		Hit = { id = "", volume = 0.35 }, -- you click an enemy
		Kill = { id = "", volume = 0.4 }, -- an enemy dies
		Buy = { id = "", volume = 0.5 }, -- you train troops
		Upgrade = { id = "", volume = 0.5 }, -- gear level up
		PackOpen = { id = "", volume = 0.6 }, -- pack starts shuffling
		PackRare = { id = "", volume = 0.7 }, -- pack reveal: Rare or better
		PackCommon = { id = "", volume = 0.5 }, -- pack reveal: Common/Uncommon
		BossStart = { id = "", volume = 0.6 },
		BossWin = { id = "", volume = 0.7 },
		BossFail = { id = "", volume = 0.6 },
		Rally = { id = "", volume = 0.6 },
		Barrage = { id = "", volume = 0.6 },
		Plunder = { id = "", volume = 0.6 },
		Frenzy = { id = "", volume = 0.6 },
		ShieldWall = { id = "", volume = 0.6 },
		Bounty = { id = "", volume = 0.6 },
		Execute = { id = "", volume = 0.6 },
		WarDrums = { id = "", volume = 0.6 },
		Fortify = { id = "", volume = 0.6 },
		Ascend = { id = "", volume = 0.8 },
		RaidStart = { id = "", volume = 0.6 },
		Purchase = { id = "", volume = 0.7 }, -- Robux purchase went through
		UIClick = { id = "", volume = 0.3 }, -- any UI button
		WeakPointHit = { id = "", volume = 0.6 }, -- you tapped a boss weak point in time
		BossSlam = { id = "", volume = 0.5 }, -- a boss attack lands on your army
		BossRoar = { id = "", volume = 0.6 }, -- a boss arrives, enrages, or a raid boss rises
		Reward = { id = "", volume = 0.6 }, -- you claim a reward (daily, quests, achievements, clan, raid)
	} :: { [string]: SoundDef },

	MUSIC = {
		Main = { id = "rbxassetid://91381492411905", volume = 0.25 }, -- normal fighting (HB Opus, Classical House Nocturne)
		Boss = { id = "", volume = 0.3 }, -- boss fights
		Raid = { id = "", volume = 0.3 }, -- clan raid attacks
		-- A track with no id falls back to Main, so the music never cuts out.
	} :: { [string]: SoundDef },

	-- The same sound can't play more often than this (seconds), so mashing doesn't blast.
	MIN_GAP = 0.06,
	MUSIC_FADE_SECONDS = 1,
}

return table.freeze(AudioConfig)
