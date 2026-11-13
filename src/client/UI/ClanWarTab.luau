--!strict
-- Clan window tab: clan level (XP bar + member bonus) and the weekly Clan War league
-- (your clan's XP and rank this week, your contribution, the countdown, the rewards, and
-- the top clans board). Display only; the server decides levels, ranks and rewards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local ClanConfig = require(Shared:WaitForChild("Config"):WaitForChild("ClanConfig"))
local UIKit = require(script.Parent.UIKit)
local ClanTypes = require(script.Parent.ClanTypes)
local ClanController = require(Client.Controllers.ClanController)

type ClanView = Types.ClanView

local Theme = UIKit.Theme
local fmt = NumberFormat.number
local XP_COLOR = Color3.fromRGB(120, 200, 255)

local ClanWarTab = {}

local function duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local days = seconds // 86400
	local hours = (seconds % 86400) // 3600
	local minutes = (seconds % 3600) // 60
	if days > 0 then
		return `{days}d {hours}h`
	elseif hours > 0 then
		return `{hours}h {minutes}m`
	end
	return `{minutes}m {seconds % 60}s`
end

local function rewardText(): string
	local lines: { string } = {}
	local previous = 0
	for _, tier in ClanConfig.WAR_REWARDS do
		local place = if tier.maxRank == previous + 1 then `#{tier.maxRank}` else `#{previous + 1}-{tier.maxRank}`
		local parts: { string } = {}
		if tier.honor ~= nil then
			table.insert(parts, `{tier.honor} Honor`)
		end
		if tier.heroChests ~= nil then
			table.insert(parts, `{tier.heroChests} Hero Chest{if tier.heroChests == 1 then "" else "s"}`)
		end
		if tier.packs ~= nil then
			table.insert(parts, `{tier.packs} free pack{if tier.packs == 1 then "" else "s"}`)
		end
		table.insert(lines, `{place}: {table.concat(parts, " + ")}`)
		previous = tier.maxRank
	end
	local participation = ClanConfig.WAR_PARTICIPATION_REWARD.honor or 0
	table.insert(lines, `Any clan with {fmt(ClanConfig.WAR_PARTICIPATION_XP)}+ XP: {participation} Honor`)
	local tokenParts: { string } = {}
	local previousRank = 0
	for _, tier in ClanConfig.TOKENS_FOR_RANK do
		local place = if tier.maxRank == previousRank + 1 then `#{tier.maxRank}` else `#{previousRank + 1}-{tier.maxRank}`
		table.insert(tokenParts, `{place} {tier.tokens}`)
		previousRank = tier.maxRank
	end
	table.insert(lines, `Clan Tokens: {table.concat(tokenParts, ", ")}, others {ClanConfig.TOKENS_PARTICIPATION}, MVP +{ClanConfig.TOKENS_MVP}`)
	table.insert(lines, `Head-to-head win: +{ClanConfig.TOKENS_HEAD_TO_HEAD_WIN} tokens, +{ClanConfig.HEAD_TO_HEAD_WIN_HONOR} Honor`)
	return table.concat(lines, "\n")
end

function ClanWarTab.build(parent: Instance, _context: ClanTypes.Context): ClanTypes.Tab
	local frame = UIKit.create("Frame", {
		Name = "War",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = parent,
	}) :: Frame

	local left = UIKit.create("Frame", {
		Name = "Level",
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Size = UDim2.new(0.55, -4, 1, 0),
		Parent = frame,
	}, { UIKit.corner(8), UIKit.padding(10) }) :: Frame

	local function line(y: number, height: number, props: { [string]: any }): TextLabel
		props.Position = UDim2.new(0, 0, 0, y)
		props.Size = UDim2.new(1, 0, 0, height)
		props.Parent = left
		return UIKit.label(props)
	end

	local levelLabel = line(0, 20, { Text = "", Font = Theme.FontBold, TextSize = 17, TextColor3 = Theme.Gold })
	local barBack = UIKit.create("Frame", {
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 22),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = left,
	}, { UIKit.corner(6) }) :: Frame
	local barFill = UIKit.create("Frame", {
		BackgroundColor3 = XP_COLOR,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		Parent = barBack,
	}, { UIKit.corner(6) }) :: Frame
	local barLabel = UIKit.label({
		Text = "",
		Font = Theme.FontBold,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.6,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 2,
		Parent = barBack,
	})
	local bonusLabel = line(40, 16, { Text = "", TextColor3 = Theme.Muted, TextSize = 12 })
	line(62, 18, { Text = "CLAN WAR THIS WEEK", Font = Theme.FontBold, TextSize = 14 })
	local clanWeekLabel = line(82, 16, { Text = "", TextSize = 13, RichText = true })
	local myLabel = line(100, 30, {
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 12,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local matchupLabel = line(132, 16, { Text = "", TextSize = 12, RichText = true })
	local endsLabel = line(150, 16, { Text = "", Font = Theme.FontBold, TextSize = 13, TextColor3 = XP_COLOR })
	line(170, 110, {
		Text = rewardText(),
		TextColor3 = Theme.Muted,
		TextSize = 11,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	local right = UIKit.create("Frame", {
		Name = "Top",
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Position = UDim2.new(0.55, 4, 0, 0),
		Size = UDim2.new(0.45, -4, 1, 0),
		Parent = frame,
	}, { UIKit.corner(8), UIKit.padding(10) }) :: Frame
	UIKit.label({ Text = "Top clans this week", Font = Theme.FontBold, TextSize = 14, Size = UDim2.new(1, 0, 0, 18), Parent = right })
	local topLabels: { TextLabel } = {}
	for i = 1, ClanConfig.WAR_TOP_COUNT do
		topLabels[i] = UIKit.label({
			Text = "",
			TextSize = 12,
			Position = UDim2.new(0, 0, 0, 20 + (i - 1) * 20),
			Size = UDim2.new(1, 0, 0, 18),
			Parent = right,
		})
	end

	local function render(view: ClanView, _snapshot: Types.Snapshot?)
		local clan = view.clan
		if clan == nil then
			return
		end
		local level, into, need = Formulas.clanLevel(clan.xp or 0)
		levelLabel.Text = `Clan Level {level}`
		if need > 0 then
			barFill.Size = UDim2.new(math.clamp(into / need, 0, 1), 0, 1, 0)
			barLabel.Text = `{fmt(into)} / {fmt(need)} XP to level {level + 1}`
		else
			barFill.Size = UDim2.new(1, 0, 1, 0)
			barLabel.Text = "MAX LEVEL"
		end
		local gold, damage = Formulas.clanLevelBonus(level)
		bonusLabel.Text = `Every member: +{math.floor((gold - 1) * 100 + 0.5)}% gold, +{math.floor((damage - 1) * 100 + 0.5)}% damage`

		local war = ClanController.getWar()
		local rankText = if war ~= nil and war.myRank ~= nil then `<b>#{war.myRank}</b>` else "not on the board yet"
		clanWeekLabel.Text = `Clan XP: {fmt(clan.weekXp or 0)}  |  Rank: {rankText}`
		local mine = view.myWeekXp or 0
		local needed = ClanConfig.WAR_MIN_CONTRIBUTION
		local status = if mine >= needed then "you'll get this week's rewards" else `{needed - mine} more for rewards`
		myLabel.Text = `You: {fmt(mine)} XP this week ({status}). Today: {view.myDayXp or 0}/{ClanConfig.XP_DAILY_CAP}.`
		local matchup = if war ~= nil then war.matchup else nil
		if matchup == nil then
			matchupLabel.Text = "Head-to-head: opponent announced once last week's results are in."
		elseif matchup.bye then
			matchupLabel.Text = "Head-to-head: no opponent this week. Reach the participation XP for a free win."
		else
			local theirs = matchup.opponentXp or 0
			local ours = clan.weekXp or 0
			local color = if ours > theirs then "#78DC78" elseif ours < theirs then "#FF7878" else "#DDDDDD"
			matchupLabel.Text = `Head-to-head vs [{matchup.opponentTag or "?"}] {matchup.opponentName or "?"}: `
				.. `<font color="{color}"><b>{fmt(ours)}</b> vs <b>{fmt(theirs)}</b></font>`
		end
		endsLabel.Text = `Week ends in {duration(ClanController.warSecondsLeft())}`

		local top = if war ~= nil then war.top else {}
		for i, label in topLabels do
			local entry = top[i]
			if entry ~= nil then
				label.Text = `{entry.rank}. [{entry.tag}] {entry.name}   {fmt(entry.xp)} XP`
				label.TextColor3 = if entry.clanId == clan.id then Theme.Gold elseif i == 1 then XP_COLOR else Theme.Text
			else
				label.Text = if i == 1 then "No clans on the board yet." else ""
				label.TextColor3 = Theme.Muted
			end
		end
	end

	return {
		title = "War",
		frame = frame,
		render = render,
	}
end

return ClanWarTab
