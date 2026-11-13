--!strict
-- Top-of-screen info: gold, army damage, area + stage, enemy/boss health, boss timer,
-- army HP during boss fights, and the Fight Boss / auto-advance button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Areas = require(Shared:WaitForChild("Areas"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local UIKit = require(script.Parent.UIKit)
local StateController = require(Client.Controllers.StateController)
local BattleController = require(Client.Controllers.BattleController)
local ShopUI = require(script.Parent.ShopUI)
local RaidConfig = require(Shared:WaitForChild("Config"):WaitForChild("RaidConfig"))

type Snapshot = Types.Snapshot
type BigNum = BigNum.BigNum

-- The "click to attack" hint disappears after this many total kills.
local HINT_UNTIL_KILLS = 15 -- the first tip ("click to attack") shows until this many kills
local BOSS_HP_COLOR = Color3.fromRGB(170, 60, 220)
local ARMY_HP_COLOR = Color3.fromRGB(60, 190, 90)
local PANEL_HEIGHT_NORMAL = 96
local PANEL_HEIGHT_BOSS = 120

local Theme = UIKit.Theme
local format = NumberFormat.big

local HudUI = {}

-- Starter tips: walks a new player through the first minutes, one tip at a time.
-- Returns nil when there's nothing useful to say.
local function tipFor(snapshot: Snapshot): string?
	if snapshot.packs.free > 0 and snapshot.encounter == "Normal" then
		return "You have a free gear pack! Open it in the Packs tab."
	end
	if snapshot.ascensions > 0 or snapshot.bestStage >= 25 then
		return nil -- experienced players don't need tips
	end
	if snapshot.totalKills < HINT_UNTIL_KILLS then
		return "Click anywhere on the battlefield to attack!"
	end
	local troops = 0
	for _, count in snapshot.troops do
		troops += count
	end
	if troops == 0 then
		return "Buy a Swordsman in the shop below. Troops fight for you!"
	end
	if snapshot.encounter == "Boss" then
		return "Boss fight! Beat it before time runs out. Knights soak up hits."
	end
	if not snapshot.autoAdvance and Formulas.isBossStage(snapshot.stage + 1) then
		return "Got stronger? Press FIGHT BOSS to try again."
	end
	if snapshot.bestStage >= 5 and snapshot.bestStage < 10 then
		return "Press 1 to Rally: double damage for 10 seconds."
	end
	local geared = false
	for _, troopGear in snapshot.gear do
		if troopGear.weapon.level > 0 or troopGear.armor.level > 0 then
			geared = true
		end
	end
	if snapshot.bestStage >= 12 and not geared then
		return "Open the Gear tab: weapons and armor make each troop type stronger."
	end
	if snapshot.bestStage >= 15 and snapshot.bestStage < 20 then
		return "Press 2 for Barrage: a huge burst of damage."
	end
	return nil
end

local function fraction(value: BigNum, max: BigNum): number
	if BigNum.isZero(max) then
		return 0
	end
	return math.clamp(BigNum.toNumber(BigNum.div(value, max)), 0, 1)
end

-- A bar with a fill and centered text. Returns (back, fill, label).
local function makeBar(parent: Instance, y: number, height: number, fillColor: Color3): (Frame, Frame, TextLabel)
	local back = UIKit.create("Frame", {
		BackgroundColor3 = Theme.HpBack,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, y),
		Size = UDim2.new(1, 0, 0, height),
		Parent = parent,
	}, { UIKit.corner(6) }) :: Frame
	local fill = UIKit.create("Frame", {
		Name = "Fill",
		BackgroundColor3 = fillColor,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = back,
	}, { UIKit.corner(6) }) :: Frame
	local label = UIKit.label({
		Text = "",
		TextSize = 13,
		Font = Theme.FontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.6,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 2,
		Parent = back,
	})
	return back, fill, label
end

function HudUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = UIKit.create("ScreenGui", {
		Name = "Hud",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	-- Left column: gold + damage.
	local economy = UIKit.panel({
		Name = "Economy",
		Position = UDim2.new(0, 12, 0, 12),
		Size = UDim2.new(0, 210, 0, 134),
		Parent = gui,
	})
	UIKit.label({ Text = "GOLD", TextColor3 = Theme.Muted, TextSize = 13, Size = UDim2.new(1, 0, 0, 16), Parent = economy })
	local goldLabel = UIKit.label({
		Text = "0",
		TextColor3 = Theme.Gold,
		Font = Theme.FontBold,
		TextSize = 28,
		Position = UDim2.new(0, 0, 0, 16),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = economy,
	})
	local perKillLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 13,
		RichText = true,
		Position = UDim2.new(0, 0, 0, 46),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = economy,
	})
	local dpsLabel = UIKit.label({
		Text = "",
		TextSize = 14,
		RichText = true,
		Position = UDim2.new(0, 0, 0, 66),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = economy,
	})
	local tapLabel = UIKit.label({
		Text = "",
		TextSize = 14,
		Position = UDim2.new(0, 0, 0, 82),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = economy,
	})
	local honorLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.Gold,
		Font = Theme.FontBold,
		TextSize = 14,
		Position = UDim2.new(0, 0, 0, 100),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = economy,
	})

	-- Shows up once Ascending is allowed; opens the Honor tab.
	local ascendButton = UIKit.button({
		Name = "AscendReady",
		Text = "",
		TextSize = 14,
		BackgroundColor3 = Theme.Gold,
		TextColor3 = Theme.Panel,
		Position = UDim2.new(0, 12, 0, 12 + 134 + 6),
		Size = UDim2.new(0, 210, 0, 34),
		Visible = false,
		Parent = gui,
	})
	ascendButton.Activated:Connect(function()
		ShopUI.openTab("Honor")
	end)

	-- Center column: stage panel, then the stage button, then the hint.
	local column = UIKit.create("Frame", {
		Name = "Center",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(0, 420, 0, 220),
		Parent = gui,
	}, {
		UIKit.create("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	})

	local stagePanel = UIKit.panel({
		Name = "Stage",
		LayoutOrder = 1,
		Size = UDim2.new(0, 300, 0, PANEL_HEIGHT_NORMAL),
		Parent = column,
	})
	local areaLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 14),
		Parent = stagePanel,
	})
	local stageLabel = UIKit.label({
		Text = "Stage 1",
		Font = Theme.FontBold,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 14),
		Size = UDim2.new(1, 0, 0, 24),
		Parent = stagePanel,
	})
	local _, hpFill, hpLabel = makeBar(stagePanel, 40, 20, Theme.HpFill)
	local infoLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 63),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = stagePanel,
	})
	local armyBack, armyFill, armyLabel = makeBar(stagePanel, 84, 18, ARMY_HP_COLOR)

	local stageButton = UIKit.button({
		Name = "StageButton",
		LayoutOrder = 2,
		Text = "",
		TextSize = 14,
		Size = UDim2.new(0, 200, 0, 30),
		Parent = column,
	})

	local hint = UIKit.label({
		Text = "Click anywhere on the battlefield to attack!",
		LayoutOrder = 3,
		TextColor3 = Theme.Gold,
		Font = Theme.FontBold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		Size = UDim2.new(1, 0, 0, 24),
		Parent = column,
	})

	-- What the stage button does right now (set in render).
	local buttonAction: () -> () = function() end
	stageButton.Activated:Connect(function()
		buttonAction()
	end)

	local function renderStageButton(snapshot: Snapshot)
		if snapshot.encounter ~= "Normal" then
			stageButton.Visible = false
			return
		end
		stageButton.Visible = true
		if snapshot.autoAdvance then
			stageButton.Text = "Auto-advance: ON"
			stageButton.BackgroundColor3 = Theme.PanelLight
			buttonAction = function()
				BattleController.setAutoAdvance(false)
			end
		elseif Formulas.isBossStage(snapshot.stage + 1) then
			stageButton.Text = "FIGHT BOSS!"
			stageButton.BackgroundColor3 = Theme.HpFill
			buttonAction = function()
				BattleController.fightBoss()
			end
		else
			stageButton.Text = "Auto-advance: OFF"
			stageButton.BackgroundColor3 = Theme.Disabled
			buttonAction = function()
				BattleController.setAutoAdvance(true)
			end
		end
	end

	local function render(snapshot: Snapshot)
		goldLabel.Text = format(snapshot.gold)
		local goldBonus = if snapshot.goldMultiplier > 1
			then ` <font color="#FFCD46">(x{snapshot.goldMultiplier})</font>`
			else ""
		perKillLabel.Text = `+{format(snapshot.goldPerKill)} per kill{goldBonus}`
		local damageBonus = if snapshot.damageMultiplier > 1
			then ` <font color="#FFCD46">(x{snapshot.damageMultiplier})</font>`
			else ""
		dpsLabel.Text = `Army DPS: {format(snapshot.armyDps)}{damageBonus}`
		tapLabel.Text = `Click damage: {format(snapshot.tapDamage)}`
		honorLabel.Text = `Honor: {format(snapshot.honor)}`
		local canAscend = not BigNum.isZero(snapshot.ascendHonor)
		ascendButton.Visible = canAscend
		if canAscend then
			ascendButton.Text = `ASCEND READY: +{format(snapshot.ascendHonor)} Honor`
		end

		local area = Areas.forStage(snapshot.stage)
		areaLabel.Text = `Area {area.number}: {area.displayName}`
		hpFill.Size = UDim2.new(fraction(snapshot.enemyHp, snapshot.enemyMaxHp), 0, 1, 0)
		hpLabel.Text = `{format(snapshot.enemyHp)} / {format(snapshot.enemyMaxHp)}`

		if snapshot.encounter == "Raid" then
			stageLabel.Text = `CLAN RAID: {RaidConfig.BOSS_NAME}`
			stageLabel.TextColor3 = RaidConfig.BOSS_COLOR
			hpFill.BackgroundColor3 = RaidConfig.BOSS_COLOR
			local timeLeft = math.max(0, math.ceil(snapshot.bossEndsAt - workspace:GetServerTimeNow()))
			hpLabel.Text = `{snapshot.raidUnitsLive} / {RaidConfig.UNITS_CAP_PER_ATTACK} raid units`
			infoLabel.Text = `Time left: {timeLeft}s  |  Click and use abilities!`
			infoLabel.TextColor3 = if timeLeft <= 10 then Theme.HpFill else Theme.Muted
			armyBack.Visible = false
			stagePanel.Size = UDim2.new(0, 300, 0, PANEL_HEIGHT_NORMAL)
		elseif snapshot.encounter == "Boss" then
			stageLabel.Text = `BOSS: {area.bossName}`
			stageLabel.TextColor3 = BOSS_HP_COLOR
			hpFill.BackgroundColor3 = BOSS_HP_COLOR
			local timeLeft = math.max(0, math.ceil(snapshot.bossEndsAt - workspace:GetServerTimeNow()))
			infoLabel.Text = `Time left: {timeLeft}s  |  Boss hits for {format(snapshot.bossDps)}/s`
			infoLabel.TextColor3 = if timeLeft <= 10 then Theme.HpFill else Theme.Muted
			armyBack.Visible = true
			armyFill.Size = UDim2.new(fraction(snapshot.armyHp, snapshot.armyMaxHp), 0, 1, 0)
			armyLabel.Text = `Army HP {format(snapshot.armyHp)} / {format(snapshot.armyMaxHp)}`
			stagePanel.Size = UDim2.new(0, 300, 0, PANEL_HEIGHT_BOSS)
		else
			stageLabel.Text = `Stage {snapshot.stage}`
			stageLabel.TextColor3 = Theme.Text
			hpFill.BackgroundColor3 = Theme.HpFill
			infoLabel.Text = `Enemy {snapshot.killsInStage + 1} of {snapshot.enemiesPerStage}`
			infoLabel.TextColor3 = Theme.Muted
			armyBack.Visible = false
			stagePanel.Size = UDim2.new(0, 300, 0, PANEL_HEIGHT_NORMAL)
		end

		renderStageButton(snapshot)
		local tip = tipFor(snapshot)
		hint.Visible = tip ~= nil
		if tip ~= nil then
			hint.Text = tip
		end
	end

	StateController.Changed:Connect(render)
	local current = StateController.get()
	if current ~= nil then
		render(current)
	end

	gui.Parent = playerGui
end

return HudUI
