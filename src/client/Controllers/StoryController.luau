--!strict
-- Decides when a story scene plays (StoryConfig) and plays it with CutsceneUI:
--   Arrive_<n>  in a normal fight in land n (1-10) that hasn't been watched
--   Boss_<n>    when land n's boss (stage n x 10) appears, before the fight gets going
--   Outro_<n>   once the server says chapter n is cleared (after the boss's death animation)
--   Final_Intro after Outro_10 (until the Hollow King falls); when it ends the final battle
--               starts (StoryRequest "Final"). Retries: ADVENTURE > Story (fightFinal).
--   Ending      once the final battle is won
-- During the final battle the King's TAUNTS show as subtitles at HP marks (no pause).
-- Scenes queue up and play one at a time, never during the loading screen, a chest reveal,
-- a raid or a Tower floor. Each tells the server "Begin" (which freezes the fight the first
-- time) and "End" (unfreeze + remember it as watched).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Areas = require(Shared:WaitForChild("Areas"))
local BigNum = require(Shared:WaitForChild("BigNum"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local StoryConfig = require(Shared:WaitForChild("Config"):WaitForChild("StoryConfig"))
local StateController = require(script.Parent.StateController)
local Cinematic = require(script.Parent.Cinematic)
local CutsceneUI = require(Client.UI.CutsceneUI)
local ChestRevealUI = require(Client.UI.ChestRevealUI)

type Snapshot = Types.Snapshot

local StoryController = {}

local queue: { { id: string, notBefore: number, replay: boolean } } = {}
local queued: { [string]: boolean } = {}
local seenLocally: { [string]: boolean } = {}
local readyAt = math.huge
local request: RemoteFunction? = nil
local nextTaunt = 1 -- the next StoryConfig.FINAL.TAUNTS line to show this fight

local function seen(snapshot: Snapshot?, id: string): boolean
	return seenLocally[id] == true or (snapshot ~= nil and snapshot.storySeen ~= nil and snapshot.storySeen[id] == true)
end

local function enqueue(id: string, front: boolean, delay: number?)
	if queued[id] or StoryConfig.SCENES[id] == nil then
		return
	end
	queued[id] = true
	local entry = { id = id, notBefore = os.clock() + (delay or 0), replay = false }
	if front then
		table.insert(queue, 1, entry)
	else
		table.insert(queue, entry)
	end
end

-- True while a scene plays or is waiting to (TutorialUI holds its lessons meanwhile).
function StoryController.busy(): boolean
	return CutsceneUI.isPlaying() or #queue > 0
end

-- Starts the final battle right now (retries from the Story tab). Returns the result.
function StoryController.fightFinal(): Types.StoryResult
	local remote = request
	if remote == nil then
		return { ok = false, reason = "NotReady" }
	end
	local ok, result = pcall(function()
		return remote:InvokeServer("Final", "Final_Intro")
	end)
	if ok and typeof(result) == "table" then
		return result :: Types.StoryResult
	end
	return { ok = false, reason = "Failed" }
end

-- Replays a scene (no freeze, nothing saved). For the Story tab.
function StoryController.replay(id: string)
	if StoryConfig.SCENES[id] ~= nil and not CutsceneUI.isPlaying() then
		table.insert(queue, 1, { id = id, notBefore = 0, replay = true })
	end
end

local function check(snapshot: Snapshot)
	if snapshot.storySeen ~= nil and next(snapshot.storySeen) == nil then
		seenLocally = {} -- the save was reset (TEST panel): forget what this session watched
	end
	if snapshot.towerFloor > 0 or snapshot.encounter == "Raid" then
		return
	end
	local land = Areas.numberForStage(snapshot.stage)
	if land >= 1 and land <= #StoryConfig.CHAPTERS then
		local prologueWaits = land == 1 and snapshot.bestStage < StoryConfig.PROLOGUE_STAGE
		if snapshot.encounter == "Normal" and not prologueWaits and not seen(snapshot, `Arrive_{land}`) then
			enqueue(`Arrive_{land}`, false)
		elseif snapshot.encounter == "Boss" and snapshot.stage == land * 10 and not seen(snapshot, `Boss_{land}`) then
			enqueue(`Boss_{land}`, true, 0.8) -- let the boss land first
		end
	end
	-- The final battle: the intro after chapter 10's outro, the ending after the win.
	local cleared = snapshot.storyCleared ~= nil and snapshot.storyCleared["10"] == true
	if cleared and not snapshot.storyFinalWon and seen(snapshot, "Outro_10") and not seen(snapshot, "Final_Intro") then
		enqueue("Final_Intro", false, 1)
	end
	if snapshot.storyFinalWon and not seen(snapshot, "Ending") then
		enqueue("Ending", true, 3.5) -- after his death animation
	end
	-- Taunts during the final battle.
	if snapshot.finalBattle and snapshot.encounter == "Boss" then
		local fraction = BigNum.toNumber(BigNum.div(snapshot.enemyHp, snapshot.enemyMaxHp))
		local taunt = StoryConfig.FINAL.TAUNTS[nextTaunt]
		if taunt ~= nil and fraction <= taunt.at and workspace:GetServerTimeNow() >= snapshot.bossIntroUntil then
			nextTaunt += 1
			CutsceneUI.subtitle(taunt.who, taunt.text)
		end
	else
		nextTaunt = 1
	end
	for _, chapter in StoryConfig.CHAPTERS do
		local id = `Outro_{chapter.number}`
		if snapshot.storyCleared ~= nil and snapshot.storyCleared[tostring(chapter.number)] and not seen(snapshot, id) then
			enqueue(id, true, 2.6) -- after the boss's death animation
		end
	end
end

local function playNext()
	local entry = queue[1]
	if entry == nil or os.clock() < entry.notBefore then
		return
	end
	table.remove(queue, 1)
	queued[entry.id] = nil
	local snapshot = StateController.get()
	if not entry.replay and seen(snapshot, entry.id) then
		return
	end
	-- A boss scene only makes sense while that boss is still up.
	local scene = StoryConfig.SCENES[entry.id]
	if not entry.replay and scene.kind == "Boss" and (snapshot == nil or snapshot.encounter ~= "Boss") then
		return
	end
	if not entry.replay and scene.kind == "Arrive" and Cinematic.tutorialOpen then
		entry.notBefore = os.clock() + 1 -- a lesson is on screen: try again in a moment
		table.insert(queue, 1, entry)
		queued[entry.id] = true
		return
	end
	if not entry.replay and (scene.kind == "Arrive" or scene.kind == "Final") and (snapshot == nil or snapshot.encounter ~= "Normal") then
		queued[entry.id] = nil
		return -- try again on a later snapshot
	end
	local remote = request
	if not entry.replay and remote ~= nil then
		task.spawn(function()
			pcall(function()
				remote:InvokeServer("Begin", entry.id)
			end)
		end)
	end
	CutsceneUI.play(scene, function()
		if not entry.replay then
			seenLocally[entry.id] = true
			if remote ~= nil then
				task.spawn(function()
					pcall(function()
						remote:InvokeServer("End", entry.id)
					end)
					-- The final battle starts as soon as its intro is over.
					if scene.kind == "Final" then
						StoryController.fightFinal()
					end
				end)
			end
		end
	end)
end

function StoryController.start()
	request = Remotes.waitForFunction(Remotes.Functions.StoryRequest)
	StateController.Changed:Connect(function(snapshot: Snapshot)
		if readyAt == math.huge then
			readyAt = os.clock() + 1.2 -- first snapshot: let the loading screen go away first
		end
		check(snapshot)
	end)
	RunService.Heartbeat:Connect(function()
		if os.clock() >= readyAt and not CutsceneUI.isPlaying() and not ChestRevealUI.isPlaying() then
			playNext()
		end
	end)
end

return StoryController
