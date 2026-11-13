--!strict
-- Top-of-screen info: gold, army damage, stage, and the enemy's health bar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BigNum = require(Shared:WaitForChild("BigNum"))
local Types = require(Shared:WaitForChild("Types"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local UIKit = require(script.Parent.UIKit)
local StateController = require(Client.Controllers.StateController)

type Snapshot = Types.Snapshot

-- The "click to attack" hint disappears after this many total kills.
local HINT_UNTIL_KILLS = 15

local Theme = UIKit.Theme
local format = NumberFormat.big

local HudUI = {}

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
		Size = UDim2.new(0, 210, 0, 116),
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
		Position = UDim2.new(0, 0, 0, 46),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = economy,
	})
	local dpsLabel = UIKit.label({
		Text = "",
		TextSize = 14,
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

	-- Center: stage + enemy health.
	local stagePanel = UIKit.panel({
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(0, 300, 0, 86),
		Parent = gui,
	})
	local stageLabel = UIKit.label({
		Text = "Stage 1",
		Font = Theme.FontBold,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 24),
		Parent = stagePanel,
	})
	local hpBack = UIKit.create("Frame", {
		Name = "HpBar",
		BackgroundColor3 = Theme.HpBack,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 28),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = stagePanel,
	}, { UIKit.corner(6) }) :: Frame
	local hpFill = UIKit.create("Frame", {
		Name = "Fill",
		BackgroundColor3 = Theme.HpFill,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = hpBack,
	}, { UIKit.corner(6) }) :: Frame
	local hpLabel = UIKit.label({
		Text = "",
		TextSize = 13,
		Font = Theme.FontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 2,
		Parent = hpBack,
	})
	local enemyCountLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 52),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = stagePanel,
	})

	local hint = UIKit.label({
		Text = "Click anywhere on the battlefield to attack!",
		TextColor3 = Theme.Gold,
		Font = Theme.FontBold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 110),
		Size = UDim2.new(0, 420, 0, 24),
		Parent = gui,
	})

	local function render(snapshot: Snapshot)
		goldLabel.Text = format(snapshot.gold)
		perKillLabel.Text = `+{format(snapshot.goldPerKill)} per kill`
		dpsLabel.Text = `Army DPS: {format(snapshot.armyDps)}`
		tapLabel.Text = `Click damage: {format(snapshot.tapDamage)}`

		stageLabel.Text = `Stage {snapshot.stage}`
		local fraction = 0
		if not BigNum.isZero(snapshot.enemyMaxHp) then
			fraction = math.clamp(BigNum.toNumber(BigNum.div(snapshot.enemyHp, snapshot.enemyMaxHp)), 0, 1)
		end
		hpFill.Size = UDim2.new(fraction, 0, 1, 0)
		hpLabel.Text = `{format(snapshot.enemyHp)} / {format(snapshot.enemyMaxHp)}`
		enemyCountLabel.Text = `Enemy {snapshot.killsInStage + 1} of {snapshot.enemiesPerStage}`

		hint.Visible = snapshot.totalKills < HINT_UNTIL_KILLS
	end

	StateController.Changed:Connect(render)
	local current = StateController.get()
	if current ~= nil then
		render(current)
	end

	gui.Parent = playerGui
end

return HudUI
