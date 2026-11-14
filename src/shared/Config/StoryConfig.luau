--!strict
-- Story mode: "The Hollow King" (owner approved: woven into the main progression, starts
-- on first join). Safe to tweak the text and numbers.
--
-- One chapter per land (AreaConfig THEMES 1-10, stages 1-100). Each chapter has up to three
-- scenes, played once each (StoryService remembers them):
--   Arrive_<n>  the first time you reach the land (Arrive_1 is the prologue on first join)
--   Boss_<n>    right as that land's boss appears the first time
--   Outro_<n>   after you beat that boss the first time (the chapter is then cleared)
-- While an unseen scene plays the server freezes your fight (StageService.pause), so a
-- cutscene can never cost a boss. Lines advance by themselves so AFK players aren't stuck.
-- Clearing a chapter = first win against its boss: +BONUS_PER_CHAPTER damage forever and a
-- one-time REWARD.
--
-- Scene format (played by the client's CutsceneUI):
--   shots = { { cam = <camera>, actions = { <action> }, lines = { { who, text } }, hold = seconds? } }
--   camera: "wide" (the stage), "enemy" (the current enemy), "commander" (your avatar),
--           "sky" (high over the battlefield), or { pos = Vector3, look = Vector3 } (plot offsets)
--   actions (run at the start of the shot, in order):
--     { spawn = name, general = GeneralId, at = Vector3, face = Vector3? }       a General
--     { spawn = name, enemy = kind, at = Vector3, scale = n?, color = Color3?, ghost = bool? }
--     { move = name, to = Vector3, time = seconds }    walk there
--     { anim = name, name = "hop" | "bow" | "fall" | "shake" | "rise" }
--     { effect = "portal" | "roar" | "smoke" | "shockwave" | "sparks" | "dust", at = Vector3 | name }
--     { remove = name, effect = "portal"? }
--   lines: `who` is a CAST key ("Commander" = your own name). Positions are offsets from the
--   plot centre; the stage is the open ground between the camera and the arena (z ~ -27).

export type StoryLine = { who: string, text: string }
export type StoryShot = {
	cam: any,
	actions: { { [string]: any } }?,
	lines: { StoryLine }?,
	hold: number?, -- extra seconds after the lines (or the whole shot when it has none)
}
export type StoryScene = { id: string, chapter: number, kind: string, shots: { StoryShot } }
export type Chapter = { number: number, title: string, bossStage: number }

local HOLLOW = Color3.fromRGB(120, 70, 190)

local StoryConfig = {
	BONUS_PER_CHAPTER = 0.02, -- +2% damage per cleared chapter (all ten: +20%)
	-- One-time reward per cleared chapter (DailyService.grant) plus Relic Dust.
	REWARD = { goldMinutes = 20, scrolls = 2, honorShare = 0.05, honor = 5 },
	REWARD_DUST = 60,
	MAX_PAUSE_SECONDS = 120, -- the server unfreezes the fight after this even without "End"
	LINE_SECONDS_MIN = 2.6, -- each line stays at least this long...
	LINE_SECONDS_PER_CHAR = 0.055, -- ...plus this per character (then advances by itself)
	REQUESTS_BURST = 6,
	REQUESTS_PER_SECOND = 1,

	-- Speakers: display name + name color. "Commander" uses the player's own name.
	CAST = {
		Narrator = { name = "", color = Color3.fromRGB(220, 220, 230) },
		Commander = { name = "", color = Color3.fromRGB(255, 255, 255) },
		Isolde = { name = "Queen Isolde", color = Color3.fromRGB(255, 200, 80) },
		Aldric = { name = "Sir Aldric", color = Color3.fromRGB(110, 170, 255) },
		Lyra = { name = "Lyra Swiftbow", color = Color3.fromRGB(120, 220, 120) },
		King = { name = "The Hollow King", color = Color3.fromRGB(190, 120, 255) },
		Grimbark = { name = "Old Grimbark", color = Color3.fromRGB(150, 220, 90) },
		Tyrant = { name = "The Sand Tyrant", color = Color3.fromRGB(240, 190, 100) },
	} :: { [string]: { name: string, color: Color3 } },

	CHAPTERS = {} :: { Chapter },
	SCENES = {} :: { [string]: StoryScene },
	HOLLOW_COLOR = HOLLOW,
}

local TITLES = {
	"The Rotting Wood",
	"Sands of the Tyrant",
	"The Frozen Pass",
	"Witch of the Mire",
	"Heart of Fire",
	"The Hollow Throne",
	"Ruins of Jade",
	"The Prism Queen",
	"Beneath the Waves",
	"Storm over the Citadel",
}
for number, title in TITLES do
	table.insert(StoryConfig.CHAPTERS, { number = number, title = title, bossStage = number * 10 })
end

-- Stage spots (plot offsets): the open ground in front of the arena, facing the camera.
local CENTER = Vector3.new(0, 0, -27)
local LEFT = Vector3.new(4.5, 0, -26) -- +X is screen LEFT
local RIGHT = Vector3.new(-4.5, 0, -26)
local TOWARD_CAMERA = Vector3.new(0, 0, -1)

local function scene(id: string, chapter: number, kind: string, shots: { StoryShot })
	StoryConfig.SCENES[id] = { id = id, chapter = chapter, kind = kind, shots = shots }
end

---------------------------------------------------------------- Chapter 1: prologue

scene("Arrive_1", 1, "Arrive", {
	{
		cam = "sky",
		lines = {
			{ who = "Narrator", text = "For a thousand years the kingdom of Valdren was guarded by the spirits of its lands." },
			{ who = "Narrator", text = "Then, in the deepest night, the Hollow King woke." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ effect = "portal", at = CENTER },
			{ spawn = "King", enemy = "HollowKing", at = CENTER + Vector3.new(0, 0, 3), scale = 1.4, color = HOLLOW, ghost = true },
			{ effect = "roar", at = "King" },
		},
		lines = {
			{ who = "King", text = "Every guardian will kneel. Every land will rot. Valdren is MINE." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ remove = "King", effect = "smoke" },
			{ spawn = "Isolde", general = "Isolde", at = CENTER, face = TOWARD_CAMERA },
			{ spawn = "Aldric", general = "Aldric", at = LEFT + Vector3.new(0, 0, 6), face = TOWARD_CAMERA },
			{ move = "Aldric", to = LEFT, time = 1.2 },
		},
		lines = {
			{ who = "Isolde", text = "His shadow has already reached the Whispering Forest." },
			{ who = "Isolde", text = "Commander, the last army of Valdren is yours. Drive him out, land by land." },
		},
	},
	{
		cam = "commander",
		lines = {
			{ who = "Commander", text = "Then we march. For Valdren!" },
		},
	},
	{
		cam = "wide",
		actions = {
			{ spawn = "Lyra", general = "Lyra", at = RIGHT + Vector3.new(0, 0, 6), face = TOWARD_CAMERA },
			{ move = "Lyra", to = RIGHT, time = 1 },
			{ anim = "Aldric", name = "bow" },
		},
		lines = {
			{ who = "Aldric", text = "Old Grimbark guards these woods. If the shadow has him, we'll have to cut through." },
			{ who = "Lyra", text = "I'll scout ahead. Train soldiers, Commander. Every sword counts." },
		},
	},
})

scene("Boss_1", 1, "Boss", {
	{
		cam = "enemy",
		actions = { { effect = "roar", at = "enemy" } },
		lines = {
			{ who = "Grimbark", text = "Rrrr... the King... commands... ROOT AND RUIN!" },
			{ who = "Aldric", text = "His eyes are burning with the shadow. Strike hard and he'll come back to himself!" },
		},
	},
})

scene("Outro_1", 1, "Outro", {
	{
		cam = "wide",
		actions = {
			{ spawn = "Grimbark", enemy = "Treant", at = CENTER + Vector3.new(0, 0, 2), scale = 1.1, color = Color3.fromRGB(90, 160, 70) },
			{ effect = "sparks", at = "Grimbark" },
		},
		lines = {
			{ who = "Grimbark", text = "The rot... is gone. You have my thanks, young commander." },
			{ who = "Grimbark", text = "His darkness came from the south. From the burning dunes." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ remove = "Grimbark", effect = "sparks" },
			{ spawn = "Aldric", general = "Aldric", at = LEFT, face = TOWARD_CAMERA },
			{ spawn = "Lyra", general = "Lyra", at = RIGHT, face = TOWARD_CAMERA },
			{ anim = "Lyra", name = "hop" },
		},
		lines = {
			{ who = "Aldric", text = "One guardian freed. Nine to go." },
			{ who = "Lyra", text = "South it is. Pack light, it's hot out there." },
		},
	},
})

---------------------------------------------------------------- Chapter 2

scene("Arrive_2", 2, "Arrive", {
	{
		cam = "wide",
		actions = {
			{ spawn = "Lyra", general = "Lyra", at = CENTER + Vector3.new(0, 0, 6), face = TOWARD_CAMERA },
			{ move = "Lyra", to = CENTER, time = 1 },
			{ effect = "dust", at = CENTER + Vector3.new(6, 0, 4) },
		},
		lines = {
			{ who = "Lyra", text = "The Sunscorch Dunes. Something HUGE is moving under the sand." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ spawn = "Aldric", general = "Aldric", at = LEFT, face = TOWARD_CAMERA },
			{ anim = "Aldric", name = "shake" },
		},
		lines = {
			{ who = "Aldric", text = "The creatures here wear hides like armor. Our arrows will bounce off." },
			{ who = "Aldric", text = "Lean on the swordsmen and knights, Commander." },
		},
	},
})

scene("Boss_2", 2, "Boss", {
	{
		cam = "enemy",
		actions = { { effect = "dust", at = "enemy" }, { effect = "roar", at = "enemy" } },
		lines = {
			{ who = "Tyrant", text = "SSSsss... the King promised me ALL the sand." },
			{ who = "King", text = "Turn back, little commander. The dunes will swallow you whole." },
		},
	},
})

scene("Outro_2", 2, "Outro", {
	{
		cam = "wide",
		actions = {
			{ spawn = "Aldric", general = "Aldric", at = CENTER, face = TOWARD_CAMERA },
			{ effect = "sparks", at = CENTER + Vector3.new(0, 3, -1) },
		},
		lines = {
			{ who = "Aldric", text = "Look at this. A shard of black iron, from his crown." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ spawn = "Isolde", general = "Isolde", at = LEFT, face = TOWARD_CAMERA },
			{ spawn = "Lyra", general = "Lyra", at = RIGHT, face = TOWARD_CAMERA },
		},
		lines = {
			{ who = "Isolde", text = "He feeds on every guardian he corrupts. Each one we free makes him weaker." },
			{ who = "Lyra", text = "Then we keep freeing them. The Frozen Pass is next." },
		},
	},
})

-- Chapters whose scenes aren't written yet still clear (bonus + reward); they simply have
-- no cutscene (S2 adds them).

return StoryConfig
