--!strict
-- Top-of-screen info: gold, army damage, area + stage, enemy/boss health, boss timer,
-- army HP during boss fights, and the Fight Boss / auto-advance button.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Areas = require(Shared:WaitForChild("Areas"))
local TroopConfig = require(Shared:WaitForChild("Config"):WaitForChild("TroopConfig"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local UIKit = require(script.Parent.UIKit)
local StateController = require(Client.Controllers.StateController)
local BattleController = require(Client.Controllers.BattleController)
local ShopUI = require(script.Parent.ShopUI)
local Layout = require(script.Parent.Layout)
local BattlefieldController = require(Client.Controllers.BattlefieldController)
local Spotlight = require(script.Parent.Spotlight)
local RaidConfig = require(Shared:WaitForChild("Config"):WaitForChild("RaidConfig"))

type Snapshot = Types.Snapshot
type BigNum = BigNum.BigNum

-- The "click to attack" hint disappears after this many total kills.
local HINT_UNTIL_KILLS = 15 -- the first tip ("click to attack") shows until this many kills
local BOSS_HP_COLOR = Color3.fromRGB(170, 60, 220)
local ARMY_HP_COLOR = Color3.fromRGB(60, 190, 90)
local PANEL_HEIGHT_NORMAL = 96
local PANEL_HEIGHT_BOSS = 120
local PANEL_HEIGHT_BOSS_STATUS = 140
local SHIELD_COLOR = Color3.fromRGB(120, 190, 255)
local ENRAGE_COLOR = Color3.fromRGB(255, 70, 70)
local MINION_COLOR = Color3.fromRGB(230, 200, 90)

local Theme = UIKit.Theme
local format = NumberFormat.big

local HudUI = {}

-- Starter tips: walks a new player through the first minutes, one tip at a time.
-- Returns (text, spotlight key) or nil when there's nothing useful to say. The key
-- names the button the tip is about (see Spotlight), which then pulses.
-- Phones get "tap" wording and no keyboard shortcuts.
local TAP = if Layout.compact then "Tap" else "Click"
local function tipFor(snapshot: Snapshot): (string?, string?)
	if snapshot.packs.free > 0 and snapshot.encounter == "Normal" then
		return "You have a free gear pack! Open it in the Packs tab.", "Tab:Packs"
	end
	if snapshot.encounter == "Normal" then
		for _, troopId in TroopConfig.ORDER do
			local def = TroopConfig.TROOPS[troopId]
			if def.unlockStage ~= nil and (snapshot.troops[troopId] or 0) == 0 and Formulas.troopUnlocked(troopId, snapshot.bestStage) then
				return `New troop unlocked: {def.displayName}! Find it in the shop.`, "Tab:Troops"
			end
		end
	end
	if snapshot.ascensions > 0 or snapshot.bestStage >= 25 then
		return nil, nil -- experienced players don't need tips
	end
	if snapshot.totalKills < HINT_UNTIL_KILLS then
		return `{TAP} anywhere on the battlefield to attack!`, nil
	end
	local troops = 0
	for _, count in snapshot.troops do
		troops += count
	end
	if troops == 0 then
		return "Buy a Swordsman in the shop below. Troops fight for you!", "Buy:Swordsman"
	end
	if snapshot.encounter == "Boss" then
		return "Boss fight! Beat it before time runs out. Knights soak up hits.", nil
	end
	if not snapshot.autoAdvance and Formulas.isBossStage(snapshot.stage + 1) then
		return "Got stronger? Press FIGHT BOSS to try again.", "FightBoss"
	end
	if snapshot.bestStage >= 5 and snapshot.bestStage < 10 then
		local how = if Layout.compact then "Tap RALLY" else "Press 1 to Rally"
		return `{how}: double damage for 10 seconds.`, "Ability:Rally"
	end
	local geared = false
	for _, troopGear in snapshot.gear do
		if troopGear.weapon.level > 0 or troopGear.armor.level > 0 then
			geared = true
		end
	end
	if snapshot.bestStage >= 12 and not geared then
		return "Open the Gear tab: weapons and armor make each troop type stronger.", "Tab:Gear"
	end
	if snapshot.bestStage >= 15 and snapshot.bestStage < 20 then
		local how = if Layout.compact then "Tap BARRAGE" else "Press 2 for Barrage"
		return `{how}: a huge burst of damage.`, "Ability:Barrage"
	end
	return nil, nil
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

-- Roblox's player list sits in the top-right corner, where our menu column now is.
-- Rankings live in the TOP window instead. SetCoreGuiEnabled can fail while the core
-- scripts are still loading, so retry for a few seconds.
local function hidePlayerList()
	task.spawn(function()
		for _ = 1, 20 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
			end)
			if ok then
				return
			end
			task.wait(0.5)
		end
	end)
end

function HudUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	hidePlayerList()

	local gui = UIKit.create("ScreenGui", {
		Name = "Hud",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 2, -- above the shop (tips can overlap it on phones), below popups
	}) :: ScreenGui

	-- Right column: gold, damage, army HP. Compact (phones) drops the "GOLD" header and
	-- the click-damage line to save height.
	local compact = Layout.compact
	local economy = UIKit.panel({
		Name = "Economy",
		Position = Layout.columnPosition(0, Layout.ECONOMY_TOP),
		Size = UDim2.new(0, Layout.COLUMN_WIDTH, 0, Layout.ECONOMY_HEIGHT),
		Parent = gui,
	})
	local lineSize = if compact then 13 else 16
	local lineHeight = if compact then 16 else 18
	local y = 0
	-- Adds one text line to the panel and moves down.
	local function line(props: { [string]: any }, height: number): TextLabel
		props.Position = UDim2.new(0, 0, 0, y)
		props.Size = UDim2.new(1, 0, 0, height)
		props.Parent = economy
		y += height
		return UIKit.label(props)
	end
	if not compact then
		line({ Text = "GOLD", TextColor3 = Theme.Muted, TextSize = 14 }, 18)
	end
	local goldLabel = line({
		Text = "0",
		TextColor3 = Theme.Gold,
		Font = Theme.FontBold,
		TextSize = if compact then 28 else 34,
	}, if compact then 30 else 38)
	local perKillLabel = line({ Text = "", TextColor3 = Theme.Muted, TextSize = lineSize, RichText = true }, lineHeight)
	local dpsLabel = line({ Text = "", TextSize = lineSize, RichText = true }, lineHeight)
	local armyHpLabel = line({ Text = "", TextColor3 = ARMY_HP_COLOR, TextSize = lineSize, Font = Theme.FontBold }, lineHeight)
	local tapLabel = line({ Text = "", TextSize = lineSize, Visible = not compact }, if compact then 0 else lineHeight)
	local honorLabel = line({ Text = "", TextColor3 = Theme.Gold, Font = Theme.FontBold, TextSize = lineSize }, lineHeight)

	-- Shows up once Ascending is allowed; opens the Honor tab.
	local ascendButton = UIKit.button({
		Name = "AscendReady",
		Text = "",
		TextSize = 14,
		BackgroundColor3 = Theme.Gold,
		TextColor3 = Theme.Panel,
		Position = Layout.columnPosition(0, Layout.ASCEND_TOP),
		Size = UDim2.new(0, Layout.COLUMN_WIDTH, 0, Layout.ASCEND_HEIGHT),
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
	-- Boss moves: shield / minions / enrage, one line under the army bar.
	local statusLabel = UIKit.label({
		Text = "",
		RichText = true,
		Font = Theme.FontBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 106),
		Size = UDim2.new(1, 0, 0, 16),
		Visible = false,
		Parent = stagePanel,
	})

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
	Spotlight.register("FightBoss", stageButton)
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
		armyHpLabel.Text = if snapshot.encounter == "Boss"
			then `Army HP: {format(snapshot.armyHp)} / {format(snapshot.armyMaxHp)}`
			else `Army HP: {format(snapshot.armyMaxHp)}`
		honorLabel.Text = `Honor: {format(snapshot.honor)}`
		local canAscend = not BigNum.isZero(snapshot.ascendHonor)
		ascendButton.Visible = canAscend
		if canAscend then
			ascendButton.Text = `ASCEND READY: +{format(snapshot.ascendHonor)} Honor`
		end

		local area = Areas.forStage(snapshot.stage)
		local trait = area.theme.trait
		if trait ~= nil then
			local troopName = TroopConfig.TROOPS[trait.troopId].displayName
			local percent = math.floor((1 - trait.damageMultiplier) * 100 + 0.5)
			areaLabel.Text = `Area {area.number}: {area.displayName}  |  {trait.name}: {troopName}s -{percent}%`
		else
			areaLabel.Text = `Area {area.number}: {area.displayName}`
		end
		statusLabel.Visible = false
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

			local status: { string } = {}
			if workspace:GetServerTimeNow() < snapshot.bossShieldUntil then
				table.insert(status, `<font color="#{SHIELD_COLOR:ToHex()}">SHIELD: only clicks + abilities hurt!</font>`)
			end
			if not BigNum.isZero(snapshot.minionHp) then
				table.insert(status, `<font color="#{MINION_COLOR:ToHex()}">Minions {format(snapshot.minionHp)} HP</font>`)
			end
			if snapshot.bossEnraged then
				table.insert(status, `<font color="#{ENRAGE_COLOR:ToHex()}">ENRAGED</font>`)
			end
			statusLabel.Visible = #status > 0
			statusLabel.Text = table.concat(status, "  ")
			stagePanel.Size = UDim2.new(0, 300, 0, if #status > 0 then PANEL_HEIGHT_BOSS_STATUS else PANEL_HEIGHT_BOSS)
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
		local tip, spotlight = tipFor(snapshot)
		hint.Visible = tip ~= nil
		if tip ~= nil then
			hint.Text = tip
		end
		Spotlight.show(spotlight)
	end

	StateController.Changed:Connect(render)

	-- Gold coins fly from a defeated enemy into the gold counter, which pops when they land.
	-- Separate full-screen layer without UI scaling, so screen positions line up exactly.
	local coinLayer = Instance.new("ScreenGui")
	coinLayer.Name = "CoinFly"
	coinLayer.IgnoreGuiInset = true
	coinLayer.ResetOnSpawn = false
	coinLayer.DisplayOrder = 5
	coinLayer.Parent = playerGui
	local lastCoins = 0

	local function flyCoins()
		local now = os.clock()
		local camera = workspace.CurrentCamera
		local enemyPosition = BattlefieldController.getEnemyPosition()
		if now - lastCoins < 0.3 or camera == nil or enemyPosition == nil then
			return
		end
		lastCoins = now
		local screen, onScreen = camera:WorldToViewportPoint(enemyPosition)
		if not onScreen then
			return
		end
		local inset = GuiService:GetGuiInset()
		local target = goldLabel.AbsolutePosition + inset + Vector2.new(30, goldLabel.AbsoluteSize.Y / 2)
		for i = 1, 4 do
			local coin = Instance.new("Frame")
			coin.AnchorPoint = Vector2.new(0.5, 0.5)
			coin.Size = UDim2.fromOffset(14, 14)
			coin.BackgroundColor3 = Theme.Gold
			coin.Position = UDim2.fromOffset(screen.X + math.random(-25, 25), screen.Y + math.random(-15, 15))
			UIKit.create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = coin })
			UIKit.create("UIStroke", { Color = Color3.fromRGB(180, 120, 20), Thickness = 2, Parent = coin })
			coin.Parent = coinLayer
			local tween = TweenService:Create(
				coin,
				TweenInfo.new(0.45 + i * 0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = UDim2.fromOffset(target.X, target.Y), Size = UDim2.fromOffset(8, 8) }
			)
			tween.Completed:Connect(function()
				coin:Destroy()
				if i == 1 then
					UIKit.bump(goldLabel, 0.15)
				end
			end)
			tween:Play()
		end
	end

	StateController.Changed:Connect(function(snapshot: Snapshot, previous: Snapshot?)
		if previous ~= nil and snapshot.totalKills > previous.totalKills then
			flyCoins()
		end
	end)
	local current = StateController.get()
	if current ~= nil then
		render(current)
	end

	gui.Parent = playerGui
end

return HudUI
