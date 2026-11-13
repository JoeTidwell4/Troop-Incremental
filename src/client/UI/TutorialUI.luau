--!strict
-- Tutorial lessons (TutorialConfig): watches for each lesson's trigger, queues it, and
-- shows it as a small card (title, text, Back / Next / Skip) that never pauses the game.
-- Each card can glow a button (Spotlight.override) and open a window (Spotlight.open).
-- When a lesson is finished or skipped the server remembers it (TutorialSeen), so it
-- shows once per account. GuideUI can replay any lesson with TutorialUI.play.
--
-- The card sits at the bottom, or at the top when the glowing button is in the lower half
-- of the screen (so it never covers what it points at).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local BigNum = require(Shared:WaitForChild("BigNum"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local TutorialConfig = require(Shared:WaitForChild("Config"):WaitForChild("TutorialConfig"))
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)
local Spotlight = require(script.Parent.Spotlight)
local ChestRevealUI = require(script.Parent.ChestRevealUI)
local StateController = require(Client.Controllers.StateController)
local ClanController = require(Client.Controllers.ClanController)
local RelicController = require(Client.Controllers.RelicController)

type Snapshot = Types.Snapshot
type Lesson = Types.TutorialLesson

local Theme = UIKit.Theme
local CARD_COLOR = Color3.fromRGB(255, 205, 70)

local TutorialUI = {}

local seenLocally: { [string]: boolean } = {} -- finished this session (before the server echoes it)
local queued: { [string]: boolean } = {}
local queue: { string } = {}
local current: Lesson? = nil
local step = 1
local replaying = false
local readyAt = math.huge -- don't start lessons until the game has loaded
local seenRemote: RemoteEvent? = nil

local showStep: () -> () = function() end

local function isSeen(snapshot: Snapshot?, lessonId: string): boolean
	if seenLocally[lessonId] then
		return true
	end
	return snapshot ~= nil and snapshot.tutorialSeen[lessonId] == true
end

local function enqueue(lessonId: string, front: boolean?)
	if queued[lessonId] or (current ~= nil and current.id == lessonId) then
		return
	end
	queued[lessonId] = true
	if front then
		table.insert(queue, 1, lessonId)
	else
		table.insert(queue, lessonId)
	end
end

-- Queues every unseen lesson whose trigger (`when`) is true right now / just happened.
local function trigger(snapshot: Snapshot?, when: string)
	for _, lesson in TutorialConfig.LESSONS do
		if lesson.when == when and not isSeen(snapshot, lesson.id) then
			if when ~= "stage" or (snapshot ~= nil and snapshot.bestStage >= lesson.stage) then
				enqueue(lesson.id)
			end
		end
	end
end

local function finish(markSeen: boolean)
	local lesson = current
	current = nil
	Spotlight.override(nil)
	if lesson ~= nil and markSeen and not replaying then
		seenLocally[lesson.id] = true
		if seenRemote ~= nil then
			seenRemote:FireServer(lesson.id)
		end
	end
	replaying = false
end

-- Replays a lesson from the GUIDE (shown next, even if already seen).
function TutorialUI.play(lessonId: string)
	if TutorialConfig.BY_ID[lessonId] == nil then
		return
	end
	if current ~= nil then
		finish(true)
	end
	current = TutorialConfig.BY_ID[lessonId]
	step = 1
	replaying = true
	showStep()
end

-- Snapshot-based triggers.
local function checkSnapshot(snapshot: Snapshot)
	trigger(snapshot, "stage")
	if snapshot.encounter == "Boss" then
		trigger(snapshot, "boss")
		if snapshot.bossShieldUntil > workspace:GetServerTimeNow() then
			trigger(snapshot, "bossShield")
		end
		if snapshot.bossEnraged then
			trigger(snapshot, "bossEnrage")
		end
		if not BigNum.isZero(snapshot.minionHp) then
			trigger(snapshot, "bossMinions")
		end
	end
	if snapshot.encounter == "Normal" and not snapshot.autoAdvance then
		trigger(snapshot, "farming")
	end
	if snapshot.enemyGolden then
		trigger(snapshot, "golden")
	end
	if snapshot.packs.free > 0 then
		trigger(snapshot, "freePack")
	end
	local level = Formulas.commanderLevel(snapshot.commanderXp)
	if Formulas.skillPoints(level) - Formulas.skillSpent(snapshot.skillRanks) > 0 then
		trigger(snapshot, "skillPoint")
	end
	if not BigNum.isZero(snapshot.ascendHonor) then
		trigger(snapshot, "ascendReady")
	end
	if snapshot.legacyCrowns > 0 then
		trigger(snapshot, "legacyReady")
	end
	if snapshot.ascensions >= 1 then
		trigger(snapshot, "ascended")
	end
	if snapshot.challengeActive ~= "" then
		trigger(snapshot, "inChallenge")
	end
	local clan = ClanController.get()
	if clan ~= nil and clan.inClan then
		trigger(snapshot, "inClan")
	end
end

function TutorialUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	seenRemote = Remotes.waitForEvent(Remotes.Events.TutorialSeen)

	local gui = UIKit.create("ScreenGui", {
		Name = "Tutorial",
		ResetOnSpawn = false,
		DisplayOrder = 20, -- above the windows it opens, below reveals (21)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui
	local card = UIKit.panel({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(0, if Layout.compact then 420 else 470, 0, 118),
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	})
	UIKit.create("UIStroke", { Color = CARD_COLOR, Thickness = 2, Parent = card })
	local title = UIKit.label({ Text = "", Font = Theme.FontBold, TextSize = 16, TextColor3 = CARD_COLOR, Size = UDim2.new(1, -70, 0, 20), Parent = card })
	local counter = UIKit.label({ Text = "", TextSize = 12, TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 64, 0, 20), Parent = card })
	local body = UIKit.label({
		Text = "",
		TextSize = 14,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 0, 0, 22),
		Size = UDim2.new(1, 0, 1, -58),
		Parent = card,
	})
	local skipButton = UIKit.button({ Text = "Skip", TextSize = 13, BackgroundColor3 = Theme.PanelLight, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(0, 70, 0, 30), Parent = card })
	local backButton = UIKit.button({ Text = "Back", TextSize = 13, BackgroundColor3 = Theme.PanelLight, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -108, 1, 0), Size = UDim2.new(0, 70, 0, 30), Parent = card })
	local nextButton = UIKit.button({ Text = "Next", TextSize = 13, BackgroundColor3 = Theme.Good, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.new(0, 100, 0, 30), Parent = card })

	showStep = function()
		local lesson = current
		if lesson == nil then
			card.Visible = false
			return
		end
		local data = lesson.steps[step]
		title.Text = lesson.title
		counter.Text = if #lesson.steps > 1 then `{step}/{#lesson.steps}` else ""
		body.Text = (string.gsub(data.text, "{tap}", if Layout.compact then "Tap" else "Click"))
		backButton.Visible = step > 1
		nextButton.Text = if step < #lesson.steps then "Next" else "Got it!"
		if data.open ~= nil then
			Spotlight.open(data.open)
		end
		Spotlight.override(data.spotlight)
		card.Visible = true
		UIKit.bump(card, 0.06)
	end

	nextButton.Activated:Connect(function()
		local lesson = current
		if lesson == nil then
			return
		end
		if step < #lesson.steps then
			step += 1
			showStep()
		else
			finish(true)
			card.Visible = false
		end
	end)
	backButton.Activated:Connect(function()
		if current ~= nil and step > 1 then
			step -= 1
			showStep()
		end
	end)
	skipButton.Activated:Connect(function()
		finish(true)
		card.Visible = false
	end)

	-- Triggers.
	StateController.Changed:Connect(function(snapshot: Snapshot)
		if readyAt == math.huge then
			readyAt = os.clock() + 1.5 -- first snapshot: let the loading screen go away first
		end
		checkSnapshot(snapshot)
	end)
	StateController.Notice:Connect(function(notice: Types.Notice)
		if notice.kind == "OfflineEarnings" then
			trigger(StateController.get(), "offline")
		end
	end)
	RelicController.Dropped:Connect(function()
		trigger(StateController.get(), "relic")
	end)

	-- Show the next queued lesson when nothing else is on screen; keep the card clear of
	-- the glowing button.
	local waitingSince = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if current == nil and #queue > 0 and now >= readyAt and not ChestRevealUI.isPlaying() then
			if waitingSince == 0 then
				waitingSince = now
			elseif now - waitingSince >= TutorialConfig.SHOW_DELAY then
				waitingSince = 0
				local lessonId = table.remove(queue, 1) :: string
				queued[lessonId] = nil
				if not isSeen(StateController.get(), lessonId) then
					current = TutorialConfig.BY_ID[lessonId]
					step = 1
					replaying = false
					showStep()
				end
			end
		end
		if card.Visible and current ~= nil then
			local data = current.steps[step]
			local target = if data.spotlight ~= nil then Spotlight.targetOf(data.spotlight) else nil
			local camera = workspace.CurrentCamera
			local lowTarget = target ~= nil and camera ~= nil and target.AbsolutePosition.Y > camera.ViewportSize.Y * 0.5
			card.AnchorPoint = if lowTarget then Vector2.new(0.5, 0) else Vector2.new(0.5, 1)
			card.Position = if lowTarget then UDim2.new(0.5, 0, 0, 64) else UDim2.new(0.5, 0, 1, -8)
		end
	end)

	gui.Parent = playerGui
end

return TutorialUI
