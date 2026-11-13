--!strict
-- Clan window tab: this week's 3 shared clan quests (ClanConfig.QUEST_POOL). Progress
-- comes from every member on every server (a little delayed). Anyone who gave enough
-- clan XP this week can claim each finished quest once, before the week ends.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local ClanConfig = require(Shared:WaitForChild("Config"):WaitForChild("ClanConfig"))
local UIKit = require(script.Parent.UIKit)
local ClanTypes = require(script.Parent.ClanTypes)
local ClanController = require(Client.Controllers.ClanController)

type ClanView = Types.ClanView

local Theme = UIKit.Theme
local fmt = NumberFormat.number
local QUEST_COLOR = Color3.fromRGB(120, 200, 255)

local ClanQuestsTab = {}

local function questText(key: string, target: number): string
	for _, def in ClanConfig.QUEST_POOL do
		if def.key == key then
			return (string.gsub(def.text, "{n}", fmt(target)))
		end
	end
	return key
end

local function duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local days, hours, minutes = seconds // 86400, (seconds % 86400) // 3600, (seconds % 3600) // 60
	if days > 0 then
		return `{days}d {hours}h`
	elseif hours > 0 then
		return `{hours}h {minutes}m`
	end
	return `{minutes}m {seconds % 60}s`
end

function ClanQuestsTab.build(parent: Instance, context: ClanTypes.Context): ClanTypes.Tab
	local frame = UIKit.create("Frame", {
		Name = "Quests",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = parent,
	}) :: Frame
	local header = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 12,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.new(1, 0, 0, 30),
		Parent = frame,
	})

	type Row = { label: TextLabel, fill: Frame, barLabel: TextLabel, button: TextButton }
	local rows: { Row } = {}
	for index = 1, ClanConfig.QUESTS_PER_WEEK do
		local row = UIKit.create("Frame", {
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 0, 34 + (index - 1) * 66),
			Size = UDim2.new(1, 0, 0, 60),
			Parent = frame,
		}, { UIKit.corner(8), UIKit.padding(8) }) :: Frame
		local label = UIKit.label({ Text = "", Font = Theme.FontBold, TextSize = 14, Size = UDim2.new(1, -130, 0, 18), Parent = row })
		local back = UIKit.create("Frame", {
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 0, 24),
			Size = UDim2.new(1, -130, 0, 18),
			Parent = row,
		}, { UIKit.corner(6) }) :: Frame
		local fill = UIKit.create("Frame", { BackgroundColor3 = QUEST_COLOR, BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0), Parent = back }, { UIKit.corner(6) }) :: Frame
		local barLabel = UIKit.label({
			Text = "",
			Font = Theme.FontBold,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.6,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 2,
			Parent = back,
		})
		local button = UIKit.button({
			Text = "",
			TextSize = 12,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.new(0, 120, 1, 0),
			Parent = row,
		})
		button.Activated:Connect(function()
			task.spawn(function()
				local result = context.request("ClaimClanQuest", index)
				if result.ok then
					context.showStatus(`+{ClanConfig.QUEST_REWARD.tokens} Clan Tokens and some gold!`)
				end
			end)
		end)
		rows[index] = { label = label, fill = fill, barLabel = barLabel, button = button }
	end

	local function render(view: ClanView, _snapshot: Types.Snapshot?)
		local clan = view.clan
		if clan == nil then
			return
		end
		local mine = view.myWeekXp or 0
		local needed = ClanConfig.QUEST_MIN_XP
		header.Text = `Shared goals for the whole clan. Each finished quest: {ClanConfig.QUEST_REWARD.tokens} Clan Tokens + `
			.. `{ClanConfig.QUEST_REWARD.goldMinutes} min of gold for everyone who gave {needed}+ clan XP this week (you: {fmt(mine)}). `
			.. `New quests in {duration(ClanController.warSecondsLeft())}.`
		local quests = clan.quests or {}
		local claims = view.questClaims or {}
		for index, row in rows do
			local quest = quests[index]
			if quest == nil then
				row.label.Text = ""
				row.button.Visible = false
				continue
			end
			row.button.Visible = true
			local done = quest.progress >= quest.target
			row.label.Text = questText(quest.key, quest.target)
			row.fill.Size = UDim2.new(math.clamp(quest.progress / quest.target, 0, 1), 0, 1, 0)
			row.barLabel.Text = `{fmt(math.min(quest.progress, quest.target))} / {fmt(quest.target)}`
			local claimed = claims[tostring(index)] == true
			local canClaim = done and not claimed and mine >= needed
			row.button.Text = if claimed then "Claimed"
				elseif not done then "In progress"
				elseif mine < needed then `Give {needed - mine} more XP`
				else "CLAIM"
			row.button.BackgroundColor3 = if canClaim then Theme.Good else Theme.Disabled
			row.button.AutoButtonColor = canClaim
		end
	end

	return { title = "Quests", frame = frame, render = render }
end

return ClanQuestsTab
