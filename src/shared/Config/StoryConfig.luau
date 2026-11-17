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
	-- The prologue (Arrive_1) waits until a new player has reached this stage (about a
	-- minute of play), so they're fighting and killing things before any cutscene. Added
	-- after the first ad run: the ad system judges the first minutes, and a cutscene on
	-- join is the first thing new players hit.
	PROLOGUE_STAGE = 3,
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
		Brannoc = { name = "Brannoc Ironhide", color = Color3.fromRGB(170, 180, 200) },
		Morwen = { name = "Morwen the Arcane", color = Color3.fromRGB(190, 140, 255) },
		Rook = { name = "Old Rook", color = Color3.fromRGB(210, 160, 90) },
		Garrick = { name = "Garrick Stormrider", color = Color3.fromRGB(230, 120, 80) },
		Seren = { name = "Seren Goldhand", color = Color3.fromRGB(255, 215, 90) },
		Thessa = { name = "Thessa", color = Color3.fromRGB(255, 120, 170) },
		Varkas = { name = "Varkas the Conqueror", color = Color3.fromRGB(220, 70, 60) },
		Marshal = { name = "The Eternal Marshal", color = Color3.fromRGB(255, 90, 120) },
		Wyrm = { name = "The Frost Wyrm", color = Color3.fromRGB(150, 210, 255) },
		Hag = { name = "The Bog Hag", color = Color3.fromRGB(160, 220, 90) },
		Titan = { name = "The Magma Colossus", color = Color3.fromRGB(255, 130, 50) },
		Idol = { name = "The Jade Idol", color = Color3.fromRGB(110, 230, 160) },
		Prism = { name = "The Prism Queen", color = Color3.fromRGB(230, 140, 255) },
		Kraken = { name = "The Deep Kraken", color = Color3.fromRGB(200, 90, 150) },
		Griffin = { name = "The Stormcrown Griffin", color = Color3.fromRGB(130, 170, 255) },
	} :: { [string]: { name: string, color: Color3 } },

	-- The final battle (after Outro_10): the Hollow King's true form. A one-off fight (not a
	-- stage), started from the Final_Intro scene or ADVENTURE > Story; retry any time.
	FINAL = {
		HP_MULTIPLIER = 2.5, -- x the stage-100 boss's HP
		DPS_MULTIPLIER = 1.5, -- x the stage-100 boss's damage (still clamped like every boss)
		BOSS_STAGE = 100,
		TIME_LIMIT = 60, -- seconds (+ boss timer bonuses)
		WEAKEN_PER_FAIL = 0.1, -- each lost attempt takes 10% off his HP...
		WEAKEN_MAX = 0.5, -- ...up to 50%
		SCALE = 2.6, -- model size (normal bosses are 2)
		BONUS = 0.05, -- +5% damage forever once he falls
		REWARD = { scrolls = 10, heroChests = 2, honorShare = 0.25, honor = 25, goldMinutes = 60 },
		REWARD_DUST = 300,
		COSMETICS = { "HollowCrown", "ValdrenBanner" }, -- looks only (CommanderConfig)
		-- Shouted mid-fight (a subtitle, nothing pauses) when his HP drops below each mark.
		TAUNTS = {
			{ at = 0.99, who = "King", text = "KNEEL." },
			{ at = 0.75, who = "King", text = "Ten shards... I need only ONE army to rebuild my crown. Yours." },
			{ at = 0.5, who = "Isolde", text = "He's bleeding shadow! Keep pressing, Commander!" },
			{ at = 0.25, who = "King", text = "NO! I am ETERNAL! I am the dark beneath every land!" },
			{ at = 0.08, who = "Marshal", text = "Now! Finish what I could not!" },
		},
	},

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

---------------------------------------------------------------- Chapter 3: The Frozen Pass

scene("Arrive_3", 3, "Arrive", {
	{
		cam = "wide",
		actions = {
			{ spawn = "Brannoc", general = "Brannoc", at = CENTER + Vector3.new(0, 0, 6), face = TOWARD_CAMERA },
			{ move = "Brannoc", to = CENTER, time = 1.4 },
			{ spawn = "Aldric", general = "Aldric", at = LEFT, face = TOWARD_CAMERA },
		},
		lines = {
			{ who = "Brannoc", text = "Brannoc Ironhide, shield of the northern watch. You're the commander they're singing about?" },
			{ who = "Aldric", text = "The very same. What's waiting for us up the pass?" },
		},
	},
	{
		cam = "wide",
		actions = { { anim = "Brannoc", name = "shake" } },
		lines = {
			{ who = "Brannoc", text = "The beasts up here are quick. Too quick for heavy knights to pin down." },
			{ who = "Brannoc", text = "And the Wyrm... when it's wounded, it goes wild. Finish it fast once it starts to fall." },
		},
	},
})

scene("Boss_3", 3, "Boss", {
	{
		cam = "enemy",
		actions = { { effect = "roar", at = "enemy" } },
		lines = {
			{ who = "Wyrm", text = "COLD... so cold... the King's voice freezes my heart..." },
			{ who = "Brannoc", text = "Hold the line! When it's nearly down it will rage, so hit it with everything!" },
		},
	},
})

scene("Outro_3", 3, "Outro", {
	{
		cam = "wide",
		actions = {
			{ spawn = "Wyrm", enemy = "FrostWyrm", at = CENTER + Vector3.new(0, 0, 4), scale = 1, color = Color3.fromRGB(170, 215, 255) },
			{ effect = "sparks", at = "Wyrm" },
		},
		lines = {
			{ who = "Wyrm", text = "The ice in my heart has melted. I remember my oath to these mountains." },
			{ who = "Wyrm", text = "Beware the swamp below. The witch there sold herself to him willingly." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ remove = "Wyrm", effect = "sparks" },
			{ spawn = "Brannoc", general = "Brannoc", at = LEFT, face = TOWARD_CAMERA },
			{ anim = "Brannoc", name = "bow" },
		},
		lines = {
			{ who = "Brannoc", text = "My shield is yours, Commander. Lead on." },
		},
	},
})

---------------------------------------------------------------- Chapter 4: Witch of the Mire

scene("Arrive_4", 4, "Arrive", {
	{
		cam = "wide",
		actions = {
			{ effect = "portal", at = CENTER },
			{ spawn = "Morwen", general = "Morwen", at = CENTER, face = TOWARD_CAMERA },
			{ anim = "Morwen", name = "rise" },
		},
		lines = {
			{ who = "Morwen", text = "Morwen of the Arcane Circle. The swamp stinks of dark magic, Commander. His magic." },
			{ who = "Morwen", text = "The creatures here come in swarms. Your swordsmen will be buried under them." },
		},
	},
	{
		cam = "wide",
		actions = { { spawn = "Lyra", general = "Lyra", at = RIGHT, face = TOWARD_CAMERA } },
		lines = {
			{ who = "Lyra", text = "And the Hag calls her pets out of the mud once she's hurt. Kill the little ones fast." },
		},
	},
})

scene("Boss_4", 4, "Boss", {
	{
		cam = "enemy",
		actions = { { effect = "portal", at = "enemy" } },
		lines = {
			{ who = "Hag", text = "Hee hee hee! The King gave me POWER, child. What did he give you? A tin sword?" },
			{ who = "Morwen", text = "Her minions shield her. Cut them down, then the witch is yours!" },
		},
	},
})

scene("Outro_4", 4, "Outro", {
	{
		cam = "wide",
		actions = {
			{ spawn = "Hag", enemy = "BogHag", at = CENTER + Vector3.new(0, 0, 4), scale = 0.9, color = Color3.fromRGB(90, 120, 70) },
			{ anim = "Hag", name = "shake" },
		},
		lines = {
			{ who = "Hag", text = "No... no! He promised I'd never grow old... he LIED..." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ remove = "Hag", effect = "smoke" },
			{ spawn = "Morwen", general = "Morwen", at = LEFT, face = TOWARD_CAMERA },
			{ spawn = "Aldric", general = "Aldric", at = RIGHT, face = TOWARD_CAMERA },
		},
		lines = {
			{ who = "Morwen", text = "Gone back into the mud. She chose her master." },
			{ who = "Aldric", text = "Another shard of his crown. Four lands free. Next, the fire peaks." },
		},
	},
})

---------------------------------------------------------------- Chapter 5: Heart of Fire

scene("Arrive_5", 5, "Arrive", {
	{
		cam = "wide",
		actions = {
			{ spawn = "Rook", general = "Rook", at = CENTER + Vector3.new(0, 0, 5), face = TOWARD_CAMERA },
			{ move = "Rook", to = CENTER, time = 1.6 },
			{ effect = "dust", at = CENTER + Vector3.new(-5, 0, 3) },
		},
		lines = {
			{ who = "Rook", text = "Hah! Old Rook, engineer. I build the things that knock down walls." },
			{ who = "Rook", text = "Arrows just bounce off these lava beasts. You want rocks. Big rocks." },
		},
	},
	{
		cam = "wide",
		actions = { { spawn = "Brannoc", general = "Brannoc", at = LEFT, face = TOWARD_CAMERA } },
		lines = {
			{ who = "Brannoc", text = "The Colossus raises a barrier of fire. While it's up, only your own blade gets through." },
			{ who = "Brannoc", text = "Keep clicking, Commander. Your strikes are what break it." },
		},
	},
})

scene("Boss_5", 5, "Boss", {
	{
		cam = "enemy",
		actions = { { effect = "shockwave", at = "enemy" }, { effect = "roar", at = "enemy" } },
		lines = {
			{ who = "Titan", text = "BURN. EVERYTHING. BURNS." },
			{ who = "Rook", text = "Big fella. Good. Big things fall loud!" },
		},
	},
})

scene("Outro_5", 5, "Outro", {
	{
		cam = "wide",
		actions = {
			{ spawn = "Titan", enemy = "MagmaTitan", at = CENTER + Vector3.new(0, 0, 5), scale = 0.9, color = Color3.fromRGB(90, 80, 75) },
			{ effect = "dust", at = "Titan" },
		},
		lines = {
			{ who = "Titan", text = "The fire... is calm now. I can hear the mountain again." },
			{ who = "Titan", text = "He waits in the Shadow Keep. Go. End him." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ remove = "Titan", effect = "dust" },
			{ spawn = "Isolde", general = "Isolde", at = CENTER, face = TOWARD_CAMERA },
			{ spawn = "Aldric", general = "Aldric", at = LEFT, face = TOWARD_CAMERA },
			{ spawn = "Rook", general = "Rook", at = RIGHT, face = TOWARD_CAMERA },
		},
		lines = {
			{ who = "Isolde", text = "Five guardians freed, and five shards of his crown. He is weaker than he has been in an age." },
			{ who = "Isolde", text = "To the Shadow Keep, Commander. Bring him down." },
		},
	},
})

---------------------------------------------------------------- Chapter 6: The Hollow Throne

scene("Arrive_6", 6, "Arrive", {
	{
		cam = "sky",
		lines = {
			{ who = "Narrator", text = "The Shadow Keep. No bird sings here. No wind blows. Only the throne, and the one who waits on it." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ spawn = "Garrick", general = "Garrick", at = CENTER + Vector3.new(0, 0, 7), face = TOWARD_CAMERA },
			{ move = "Garrick", to = CENTER, time = 0.9 },
			{ effect = "dust", at = CENTER },
		},
		lines = {
			{ who = "Garrick", text = "Garrick Stormrider, and the cavalry of the east! We rode day and night to join you." },
			{ who = "Garrick", text = "His shadow-knights are fast, too fast for heavy knights. Let my riders run them down." },
		},
	},
})

scene("Boss_6", 6, "Boss", {
	{
		cam = "enemy",
		actions = { { effect = "roar", at = "enemy" }, { effect = "portal", at = "enemy" } },
		lines = {
			{ who = "King", text = "So. The little commander climbs all the way to my throne." },
			{ who = "King", text = "You freed five of my pets. Let us see you free YOURSELF." },
			{ who = "Isolde", text = "He shields, he summons, he rages. Everything you have learned, Commander. Now!" },
		},
	},
})

scene("Outro_6", 6, "Outro", {
	{
		cam = "wide",
		actions = {
			{ spawn = "King", enemy = "HollowKing", at = CENTER + Vector3.new(0, 0, 4), scale = 1.2, color = HOLLOW, ghost = true },
			{ anim = "King", name = "shake" },
			{ effect = "smoke", at = "King" },
		},
		lines = {
			{ who = "King", text = "Ha... HA HA HA. Did you think THIS was me? A shadow. A puppet. A drop of my power." },
			{ who = "King", text = "My true form waits above the clouds, in the Sky Citadel. Come and die there, Commander." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ remove = "King", effect = "portal" },
			{ spawn = "Isolde", general = "Isolde", at = CENTER, face = TOWARD_CAMERA },
			{ spawn = "Garrick", general = "Garrick", at = LEFT, face = TOWARD_CAMERA },
			{ spawn = "Aldric", general = "Aldric", at = RIGHT, face = TOWARD_CAMERA },
		},
		lines = {
			{ who = "Aldric", text = "He's gone. And the lands beyond are still his." },
			{ who = "Isolde", text = "Then we free them too, one by one, until his citadel stands alone in the sky." },
			{ who = "Garrick", text = "My riders are ready. Where to?" },
		},
	},
})

---------------------------------------------------------------- Chapter 7: Ruins of Jade

scene("Arrive_7", 7, "Arrive", {
	{
		cam = "wide",
		actions = {
			{ spawn = "Seren", general = "Seren", at = CENTER + Vector3.new(0, 0, 5), face = TOWARD_CAMERA },
			{ move = "Seren", to = CENTER, time = 1.2 },
			{ effect = "sparks", at = CENTER + Vector3.new(0, 2, 0) },
		},
		lines = {
			{ who = "Seren", text = "Seren Goldhand. My Golden Fleet funds your war now, Commander. Consider it an investment." },
			{ who = "Seren", text = "These ruins swallow anything with wheels. Your siege engines will sink in the vines." },
		},
	},
	{
		cam = "wide",
		actions = { { spawn = "Morwen", general = "Morwen", at = LEFT, face = TOWARD_CAMERA } },
		lines = {
			{ who = "Morwen", text = "The Idol both summons and shields. Watch for both." },
		},
	},
})

scene("Boss_7", 7, "Boss", {
	{
		cam = "enemy",
		actions = { { effect = "shockwave", at = "enemy" } },
		lines = {
			{ who = "Idol", text = "I. WAS. WORSHIPPED. Now I. OBEY. Kneel, or be crushed." },
		},
	},
})

scene("Outro_7", 7, "Outro", {
	{
		cam = "wide",
		actions = {
			{ spawn = "Idol", enemy = "JadeIdol", at = CENTER + Vector3.new(0, 0, 5), scale = 0.8, color = Color3.fromRGB(80, 200, 130) },
			{ effect = "sparks", at = "Idol" },
		},
		lines = {
			{ who = "Idol", text = "The chains of his voice are broken. The jungle will remember you, Commander." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ remove = "Idol", effect = "sparks" },
			{ spawn = "Seren", general = "Seren", at = LEFT, face = TOWARD_CAMERA },
			{ spawn = "Lyra", general = "Lyra", at = RIGHT, face = TOWARD_CAMERA },
		},
		lines = {
			{ who = "Lyra", text = "There's a cave under the ruins. And it's... glowing." },
			{ who = "Seren", text = "Crystal. Priceless. And, I suspect, very angry." },
		},
	},
})

---------------------------------------------------------------- Chapter 8: The Prism Queen

scene("Arrive_8", 8, "Arrive", {
	{
		cam = "wide",
		actions = {
			{ spawn = "Thessa", general = "Thessa", at = CENTER + Vector3.new(0, 0, 4), face = TOWARD_CAMERA },
			{ anim = "Thessa", name = "hop" },
		},
		lines = {
			{ who = "Thessa", text = "Thessa, bladedancer. I go where the fighting is thickest, and I heard it was here." },
			{ who = "Thessa", text = "The crystals reflect spells right back. Your mages will fight half-blind in these caves." },
		},
	},
	{
		cam = "wide",
		actions = { { spawn = "Morwen", general = "Morwen", at = LEFT, face = TOWARD_CAMERA }, { anim = "Morwen", name = "shake" } },
		lines = {
			{ who = "Morwen", text = "Hmph. Then the steel does the work this time." },
		},
	},
})

scene("Boss_8", 8, "Boss", {
	{
		cam = "enemy",
		actions = { { effect = "sparks", at = "enemy" } },
		lines = {
			{ who = "Prism", text = "Look at you, so dull. So ordinary. I will make you SHINE... forever, in crystal." },
			{ who = "Thessa", text = "She hides behind her barriers, then rages when cornered. Strike between the two!" },
		},
	},
})

scene("Outro_8", 8, "Outro", {
	{
		cam = "wide",
		actions = {
			{ spawn = "Prism", enemy = "PrismQueen", at = CENTER + Vector3.new(0, 0, 5), scale = 0.8, color = Color3.fromRGB(200, 170, 255) },
			{ effect = "sparks", at = "Prism" },
		},
		lines = {
			{ who = "Prism", text = "My children... are free. Forgive the queen who forgot them." },
			{ who = "Prism", text = "The sea beyond is darkest of all. The Kraken was the first he took." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ remove = "Prism", effect = "sparks" },
			{ spawn = "Thessa", general = "Thessa", at = RIGHT, face = TOWARD_CAMERA },
			{ spawn = "Aldric", general = "Aldric", at = LEFT, face = TOWARD_CAMERA },
		},
		lines = {
			{ who = "Aldric", text = "Eight shards. He must feel every one of them leave him." },
		},
	},
})

---------------------------------------------------------------- Chapter 9: Beneath the Waves

scene("Arrive_9", 9, "Arrive", {
	{
		cam = "wide",
		actions = {
			{ spawn = "Varkas", general = "Varkas", at = CENTER + Vector3.new(0, 0, 6), face = TOWARD_CAMERA },
			{ move = "Varkas", to = CENTER, time = 1.6 },
		},
		lines = {
			{ who = "Varkas", text = "Varkas. I conquered half the known world before your queen was born, Commander." },
			{ who = "Varkas", text = "I do not kneel. But I will fight beside anyone who fights HIM." },
		},
	},
	{
		cam = "wide",
		actions = { { spawn = "Garrick", general = "Garrick", at = LEFT, face = TOWARD_CAMERA }, { anim = "Garrick", name = "shake" } },
		lines = {
			{ who = "Garrick", text = "Horses on wet rocks... my riders will be slipping all over this reef." },
			{ who = "Varkas", text = "Then they walk. The Kraken calls its spawn and rages when bloodied. We crush both." },
		},
	},
})

scene("Boss_9", 9, "Boss", {
	{
		cam = "enemy",
		actions = { { effect = "shockwave", at = "enemy" }, { effect = "roar", at = "enemy" } },
		lines = {
			{ who = "Kraken", text = "The deep remembers everything... it remembers how you all DROWN." },
		},
	},
})

scene("Outro_9", 9, "Outro", {
	{
		cam = "wide",
		actions = {
			{ spawn = "Kraken", enemy = "Kraken", at = CENTER + Vector3.new(0, 0, 6), scale = 0.7, color = Color3.fromRGB(110, 150, 190) },
			{ effect = "sparks", at = "Kraken" },
		},
		lines = {
			{ who = "Kraken", text = "Light... I see light again. The deep is quiet." },
			{ who = "Kraken", text = "Only his citadel remains. It floats above the storm. You will need wings, or courage." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ remove = "Kraken", effect = "sparks" },
			{ spawn = "Isolde", general = "Isolde", at = CENTER, face = TOWARD_CAMERA },
			{ spawn = "Varkas", general = "Varkas", at = LEFT, face = TOWARD_CAMERA },
			{ spawn = "Aldric", general = "Aldric", at = RIGHT, face = TOWARD_CAMERA },
		},
		lines = {
			{ who = "Isolde", text = "Nine shards. Nine guardians home. One citadel left." },
			{ who = "Varkas", text = "Then we go up." },
		},
	},
})

---------------------------------------------------------------- Chapter 10: Storm over the Citadel

scene("Arrive_10", 10, "Arrive", {
	{
		cam = "sky",
		lines = {
			{ who = "Narrator", text = "Above the storm, the Sky Citadel. The last place in Valdren still bound to the Hollow King." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ effect = "portal", at = CENTER },
			{ spawn = "Marshal", general = "Marshal", at = CENTER, face = TOWARD_CAMERA },
			{ anim = "Marshal", name = "rise" },
			{ spawn = "Aldric", general = "Aldric", at = LEFT, face = TOWARD_CAMERA },
		},
		lines = {
			{ who = "Marshal", text = "I am the Eternal Marshal. I led the first army of Valdren, a thousand years ago." },
			{ who = "Marshal", text = "I sealed him away once. I could not finish it. Perhaps you can." },
			{ who = "Aldric", text = "A legend... standing with us." },
		},
	},
	{
		cam = "wide",
		actions = { { anim = "Marshal", name = "bow" } },
		lines = {
			{ who = "Marshal", text = "The winds up here scatter arrows. And his Griffin knows every trick he ever taught. Shield, swarm and rage." },
		},
	},
})

scene("Boss_10", 10, "Boss", {
	{
		cam = "enemy",
		actions = { { effect = "roar", at = "enemy" }, { effect = "shockwave", at = "enemy" } },
		lines = {
			{ who = "Griffin", text = "SKREEEE! None pass the storm! None reach my master!" },
			{ who = "Marshal", text = "Bring it down, Commander, and the citadel's gate falls with it!" },
		},
	},
})

scene("Outro_10", 10, "Outro", {
	{
		cam = "wide",
		actions = {
			{ spawn = "Griffin", enemy = "Griffin", at = CENTER + Vector3.new(0, 0, 6), scale = 0.8, color = Color3.fromRGB(200, 210, 240) },
			{ effect = "sparks", at = "Griffin" },
		},
		lines = {
			{ who = "Griffin", text = "The storm in my mind... has passed. I am sorry, little commander." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ remove = "Griffin", effect = "sparks" },
			{ effect = "portal", at = CENTER + Vector3.new(0, 0, 3) },
			{ spawn = "King", enemy = "HollowKing", at = CENTER + Vector3.new(0, 0, 4), scale = 1.6, color = HOLLOW },
			{ effect = "roar", at = "King" },
		},
		lines = {
			{ who = "King", text = "ENOUGH." },
			{ who = "King", text = "Ten shards. Ten guardians. You have taken everything from me, Commander." },
			{ who = "King", text = "Then I will take everything from YOU. Come to the top of my citadel. We end this." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ remove = "King", effect = "smoke" },
			{ spawn = "Isolde", general = "Isolde", at = CENTER, face = TOWARD_CAMERA },
			{ spawn = "Marshal", general = "Marshal", at = LEFT, face = TOWARD_CAMERA },
			{ spawn = "Aldric", general = "Aldric", at = RIGHT, face = TOWARD_CAMERA },
		},
		lines = {
			{ who = "Isolde", text = "This is it, Commander. Everything Valdren has is behind you." },
			{ who = "Commander", text = "Then let's finish it." },
		},
	},
})

---------------------------------------------------------------- The final battle and the ending

scene("Final_Intro", 10, "Final", {
	{
		cam = "sky",
		lines = {
			{ who = "Narrator", text = "The top of the Sky Citadel. Above the storm, above the world, the Hollow King waits." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ effect = "portal", at = CENTER + Vector3.new(0, 0, 4) },
			{ spawn = "King", enemy = "HollowKing", at = CENTER + Vector3.new(0, 0, 5), scale = 2, color = HOLLOW },
			{ anim = "King", name = "rise" },
			{ effect = "roar", at = "King" },
		},
		lines = {
			{ who = "King", text = "So. The little commander finally stands before me. Not a shadow. Not a puppet. ME." },
			{ who = "King", text = "A thousand years in the dark, I watched your kind. Tiny lives. Tiny kingdoms." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ spawn = "Isolde", general = "Isolde", at = LEFT + Vector3.new(0, 0, -3), face = Vector3.new(0, 0, 1) },
			{ spawn = "Marshal", general = "Marshal", at = RIGHT + Vector3.new(0, 0, -3), face = Vector3.new(0, 0, 1) },
			{ effect = "shockwave", at = "King" },
		},
		lines = {
			{ who = "Marshal", text = "I sealed you once, Hollow King. This time there will be no seal. Only an end." },
			{ who = "Isolde", text = "Every land you poisoned is free. Every guardian stands with us. You are alone." },
		},
	},
	{
		cam = "commander",
		lines = {
			{ who = "Commander", text = "For Valdren. CHARGE!" },
		},
	},
	{
		cam = "wide",
		actions = { { anim = "King", name = "shake" }, { effect = "roar", at = "King" } },
		lines = {
			{ who = "King", text = "Then COME. And BREAK." },
		},
	},
})

scene("Ending", 10, "Ending", {
	{
		cam = "wide",
		actions = {
			{ spawn = "King", enemy = "HollowKing", at = CENTER + Vector3.new(0, 0, 5), scale = 1.6, color = HOLLOW, ghost = true },
			{ anim = "King", name = "shake" },
			{ effect = "smoke", at = "King" },
		},
		lines = {
			{ who = "King", text = "Impossible... my crown... my CROWN..." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ anim = "King", name = "fall" },
			{ effect = "sparks", at = "King" },
			{ effect = "shockwave", at = "King" },
		},
		lines = {
			{ who = "Narrator", text = "The crown shattered, and its shards flew home to the lands they were stolen from." },
		},
	},
	{
		cam = "sky",
		actions = { { remove = "King", effect = "sparks" } },
		lines = {
			{ who = "Narrator", text = "In the forest, the dunes, the ice and the sea, the guardians woke from the dark and remembered their oaths." },
		},
	},
	{
		cam = "wide",
		actions = {
			{ spawn = "Isolde", general = "Isolde", at = CENTER, face = TOWARD_CAMERA },
			{ spawn = "Aldric", general = "Aldric", at = LEFT, face = TOWARD_CAMERA },
			{ spawn = "Lyra", general = "Lyra", at = RIGHT, face = TOWARD_CAMERA },
			{ anim = "Isolde", name = "bow" },
		},
		lines = {
			{ who = "Isolde", text = "Valdren is free. You did what no one has done in a thousand years, Commander." },
			{ who = "Aldric", text = "Not bad for someone who started with one swordsman." },
			{ who = "Lyra", text = "So... what now?" },
		},
	},
	{
		cam = "wide",
		actions = {
			{ spawn = "Marshal", general = "Marshal", at = CENTER + Vector3.new(0, 0, 5), face = TOWARD_CAMERA },
			{ effect = "portal", at = CENTER + Vector3.new(0, 0, 5) },
		},
		lines = {
			{ who = "Marshal", text = "Now? Beyond the sea, the old lands stir. Darker things than he slept there." },
			{ who = "Marshal", text = "The army of Valdren will be needed again. Rest well, Commander. Then march on." },
		},
	},
	{
		cam = "sky",
		lines = {
			{ who = "Narrator", text = "THE HOLLOW KING: THE END. The war goes on beyond stage 100, and the legend of the Commander grows." },
		},
	},
})


return StoryConfig
