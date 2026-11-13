--!strict
-- ARMY > Skills (Phase 13b): Commander Level, XP bar, skill points, the daily free respec,
-- and the 3-branch tree (SkillConfig). Tap a node to learn one rank. Tiers unlock with
-- points spent in that branch; fork nodes are pick-one. The server checks everything
-- with the same Formulas.canLearnSkill the UI uses.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SkillConfig = require(Shared:WaitForChild("Config"):WaitForChild("SkillConfig"))
local UIKit = require(script.Parent.UIKit)

type Snapshot = Types.Snapshot
type SkillNodeDef = Types.SkillNodeDef

local Theme = UIKit.Theme
local fmt = NumberFormat.number
local XP_COLOR = Color3.fromRGB(120, 200, 255)

local FAIL_MESSAGES: { [string]: string } = {
	NoPoints = "No skill points left. Level up by beating bosses!",
	TierLocked = "Spend more points in this branch first.",
	ForkTaken = "You picked the other option. Respec to switch.",
	MaxReached = "Already maxed.",
	RespecUsed = "Free respec already used today.",
	NothingToReset = "Nothing to reset.",
}

local SkillsTab = {}

local requestRemote: RemoteFunction? = nil

local function request(action: string, nodeId: string?): { ok: boolean, reason: string? }
	local remote = requestRemote
	if remote == nil then
		remote = Remotes.waitForFunction(Remotes.Functions.SkillRequest)
		requestRemote = remote
	end
	local ok, result = pcall(function(): any
		return (remote :: RemoteFunction):InvokeServer(action, nodeId)
	end)
	if ok and typeof(result) == "table" then
		return result
	end
	return { ok = false, reason = "NoResponse" }
end

-- Nodes of a branch, by tier then order.
local function nodesOf(branch: string): { SkillNodeDef }
	local list: { SkillNodeDef } = {}
	for _, def in SkillConfig.NODES do
		if def.branch == branch then
			table.insert(list, def)
		end
	end
	table.sort(list, function(a: SkillNodeDef, b: SkillNodeDef): boolean
		if a.tier ~= b.tier then
			return a.tier < b.tier
		end
		return a.order < b.order
	end)
	return list
end

-- Unspent skill points for a snapshot.
function SkillsTab.unspentPoints(snapshot: Snapshot): number
	local level = Formulas.commanderLevel(snapshot.commanderXp)
	return Formulas.skillPoints(level) - Formulas.skillSpent(snapshot.skillRanks)
end

function SkillsTab.build(parent: Instance): { title: string, frame: Frame, render: (snapshot: Snapshot) -> () }
	local frame = UIKit.create("Frame", {
		Name = "Skills",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = parent,
	}) :: Frame

	---------------------------------------------------------------- header
	local levelLabel = UIKit.label({ Text = "", Font = Theme.FontBold, TextSize = 16, TextColor3 = XP_COLOR, Size = UDim2.new(0.5, 0, 0, 20), Parent = frame })
	local pointsLabel = UIKit.label({
		Text = "",
		Font = Theme.FontBold,
		TextSize = 15,
		TextColor3 = Theme.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0.5, -120, 0, 20),
		Parent = frame,
	})
	local respecButton = UIKit.button({
		Text = "Respec",
		TextSize = 12,
		BackgroundColor3 = Theme.PanelLight,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 112, 0, 22),
		Parent = frame,
	})
	local barBack = UIKit.create("Frame", {
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 24),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = frame,
	}, { UIKit.corner(6) }) :: Frame
	local barFill = UIKit.create("Frame", { BackgroundColor3 = XP_COLOR, BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0), Parent = barBack }, { UIKit.corner(6) }) :: Frame
	local barLabel = UIKit.label({
		Text = "",
		Font = Theme.FontBold,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.6,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 2,
		Parent = barBack,
	})
	local statusLabel = UIKit.label({
		Text = "Earn XP by beating bosses (more for new ones), Ascending, quests and achievements.",
		TextColor3 = Theme.Muted,
		TextSize = 11,
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = frame,
	})

	local function showStatus(text: string, bad: boolean)
		statusLabel.Text = text
		statusLabel.TextColor3 = if bad then Theme.HpFill else Theme.Good
	end

	---------------------------------------------------------------- branches
	local scroller = UIKit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 58),
		Size = UDim2.new(1, 0, 1, -58),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = frame,
	}) :: ScrollingFrame

	type NodeView = { def: SkillNodeDef, button: TextButton, rank: TextLabel, lockLabel: TextLabel? }
	local views: { NodeView } = {}
	local busy = false
	local branchCount = #SkillConfig.BRANCHES

	for index, branch in SkillConfig.BRANCHES do
		local column = UIKit.create("Frame", {
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Position = UDim2.new((index - 1) / branchCount, 3, 0, 0),
			Size = UDim2.new(1 / branchCount, -10, 0, 0),
			Parent = scroller,
		}, { UIKit.create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) }) :: Frame
		UIKit.label({ LayoutOrder = 0, Text = branch.displayName, Font = Theme.FontBold, TextSize = 15, TextColor3 = branch.color, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 18), Parent = column })
		UIKit.label({ LayoutOrder = 1, Text = branch.description, TextColor3 = Theme.Muted, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, Size = UDim2.new(1, 0, 0, 24), Parent = column })

		local lastTier = 0
		for order, def in nodesOf(branch.id) do
			local lockLabel: TextLabel? = nil
			if def.tier ~= lastTier then
				lastTier = def.tier
				local needed = SkillConfig.TIER_POINTS[def.tier] or 0
				if needed > 0 then
					lockLabel = UIKit.label({
						LayoutOrder = order * 2,
						Text = `Tier {def.tier}: {needed} points in {branch.displayName}`,
						TextColor3 = Theme.Muted,
						TextSize = 10,
						TextXAlignment = Enum.TextXAlignment.Center,
						Size = UDim2.new(1, 0, 0, 14),
						Parent = column,
					})
				end
			end
			local button = UIKit.button({
				LayoutOrder = order * 2 + 1,
				Text = "",
				BackgroundColor3 = Theme.PanelLight,
				Size = UDim2.new(1, 0, 0, 56),
				Parent = column,
			})
			local prefix = if def.fork ~= nil then "OR  " else ""
			UIKit.label({ Text = prefix .. def.displayName, Font = Theme.FontBold, TextSize = 13, Position = UDim2.new(0, 6, 0, 3), Size = UDim2.new(1, -52, 0, 16), Parent = button })
			local rank = UIKit.label({ Text = "", Font = Theme.FontBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(1, -50, 0, 3), Size = UDim2.new(0, 44, 0, 16), Parent = button })
			UIKit.label({
				Text = def.description,
				TextColor3 = Theme.Muted,
				TextSize = 10,
				TextWrapped = true,
				TextTruncate = Enum.TextTruncate.None,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.new(0, 6, 0, 20),
				Size = UDim2.new(1, -12, 0, 32),
				Parent = button,
			})
			button.Activated:Connect(function()
				if busy then
					return
				end
				busy = true
				task.spawn(function()
					local result = request("Learn", def.id)
					busy = false
					if result.ok then
						showStatus(`Learned {def.displayName}!`, false)
					else
						showStatus(FAIL_MESSAGES[result.reason or ""] or "Try again in a moment.", true)
					end
				end)
			end)
			table.insert(views, { def = def, button = button, rank = rank, lockLabel = lockLabel })
		end
	end

	local respecArmed = false
	respecButton.Activated:Connect(function()
		if not respecArmed then
			respecArmed = true
			respecButton.Text = "Click to confirm"
			task.delay(3, function()
				respecArmed = false
				respecButton.Text = "Respec"
			end)
			return
		end
		respecArmed = false
		respecButton.Text = "Respec"
		task.spawn(function()
			local result = request("Respec")
			if result.ok then
				showStatus("All skill points refunded. Next free respec tomorrow.", false)
			else
				showStatus(FAIL_MESSAGES[result.reason or ""] or "Try again in a moment.", true)
			end
		end)
	end)

	local function render(snapshot: Snapshot)
		local level, into, need = Formulas.commanderLevel(snapshot.commanderXp)
		levelLabel.Text = `Commander Level {level}`
		if need > 0 then
			barFill.Size = UDim2.new(math.clamp(into / need, 0, 1), 0, 1, 0)
			barLabel.Text = `{fmt(math.floor(into))} / {fmt(need)} XP`
		else
			barFill.Size = UDim2.new(1, 0, 1, 0)
			barLabel.Text = "MAX LEVEL"
		end
		local unspent = SkillsTab.unspentPoints(snapshot)
		pointsLabel.Text = `Skill points: {unspent}`
		respecButton.BackgroundColor3 = if snapshot.respecReady then Theme.PanelLight else Theme.Disabled
		if not respecArmed then
			respecButton.Text = if snapshot.respecReady then "Respec (free)" else "Respec: tomorrow"
		end

		local ranks = snapshot.skillRanks
		for _, view in views do
			local def = view.def
			local current = ranks[def.id] or 0
			local branchColor = Theme.Accent
			for _, branch in SkillConfig.BRANCHES do
				if branch.id == def.branch then
					branchColor = branch.color
				end
			end
			local canLearn, reason = Formulas.canLearnSkill(ranks, level, def.id)
			view.rank.Text = `{current}/{def.maxRank}`
			if current >= def.maxRank then
				view.button.BackgroundColor3 = branchColor
				view.rank.TextColor3 = Theme.Text
			elseif canLearn then
				view.button.BackgroundColor3 = Theme.Good
				view.rank.TextColor3 = Theme.Gold
			elseif current > 0 then
				view.button.BackgroundColor3 = branchColor:Lerp(Theme.PanelLight, 0.5)
				view.rank.TextColor3 = Theme.Text
			else
				view.button.BackgroundColor3 = if reason == "ForkTaken" or reason == "TierLocked" then Theme.Disabled else Theme.PanelLight
				view.rank.TextColor3 = Theme.Muted
			end
			if view.lockLabel ~= nil then
				local needed = SkillConfig.TIER_POINTS[def.tier] or 0
				local spent = Formulas.skillSpent(ranks, def.branch)
				view.lockLabel.TextColor3 = if spent >= needed then Theme.Good else Theme.Muted
			end
		end
	end

	return { title = "Skills", frame = frame, render = render }
end

return SkillsTab
