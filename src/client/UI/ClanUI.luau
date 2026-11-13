--!strict
-- The clan window. A "CLAN" button under the WAR button opens it.
--   * Not in a clan: create one (name + tag), or browse/search open clans and join.
--   * In a clan: header with name/tag, Leave, Open/Closed (leader), and tabs:
--     Members | Bank | Raid.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Config = Shared:WaitForChild("Config")
local ClanConfig = require(Config:WaitForChild("ClanConfig"))
local FactionConfig = require(Config:WaitForChild("FactionConfig"))
local AbilityConfig = require(Config:WaitForChild("AbilityConfig"))
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)
local ClanTypes = require(script.Parent.ClanTypes)
local ClanMembersTab = require(script.Parent.ClanMembersTab)
local ClanBankTab = require(script.Parent.ClanBankTab)
local ClanRaidTab = require(script.Parent.ClanRaidTab)
local StateController = require(Client.Controllers.StateController)
local ClanController = require(Client.Controllers.ClanController)

type ClanView = Types.ClanView
type ClanSummary = Types.ClanSummary

local Theme = UIKit.Theme

local FAIL_MESSAGES: { [string]: string } = {
	InClan = "Leave your current clan first.",
	NotInClan = "You're not in a clan.",
	StageTooLow = `Creating a clan needs best stage {ClanConfig.CREATE_MIN_BEST_STAGE}.`,
	NeedFaction = "Join a faction first.",
	BadName = `Names: {ClanConfig.NAME_MIN_LENGTH}-{ClanConfig.NAME_MAX_LENGTH} letters, numbers, spaces.`,
	BadTag = `Tags: {ClanConfig.TAG_MIN_LENGTH}-{ClanConfig.TAG_MAX_LENGTH} letters or numbers.`,
	NameNotAllowed = "That name isn't allowed. Try another.",
	NameTaken = "That name is taken.",
	ClanNotFound = "That clan doesn't exist anymore.",
	ClanClosed = "That clan is closed.",
	ClanFull = "That clan is full.",
	WrongFaction = "That clan is for another faction.",
	NotAllowed = "Your role can't do that.",
	NotAMember = "They're not in the clan anymore.",
	DailyCapReached = "You've hit today's donation cap.",
	CantAfford = "Not enough gold.",
	NotEnoughSupplies = "Not enough Supplies in the bank.",
	MaxReached = "Already maxed.",
	Busy = "One moment...",
	Rejected = "Slow down a little!",
	StoreError = "Couldn't reach Roblox servers. Try again.",
	NoAttacksLeft = "No raid attacks left today.",
	InBoss = "Finish your boss fight first.",
	AlreadyRaiding = "You're already raiding.",
}

local ClanUI = {}

function ClanUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = UIKit.create("ScreenGui", {
		Name = "Clan",
		ResetOnSpawn = false,
		DisplayOrder = 16,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	-- "CLAN" button: left column, menu row (War | Clan | Top).
	local clanPosition, clanSize = Layout.menuSlot("Clan")
	local clanButton = UIKit.button({
		Name = "ClanButton",
		Text = "CLAN",
		TextSize = Layout.MENU_TEXT_SIZE,
		Position = clanPosition,
		Size = clanSize,
		BackgroundColor3 = Theme.Accent,
		Parent = gui,
	})

	local overlay = UIKit.create("Frame", {
		Name = "Overlay",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Active = true,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = gui,
	}) :: Frame
	local window = UIKit.create("Frame", {
		Name = "Window",
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.48, 0),
		Size = Layout.windowSize(0.94, 0.86),
		Parent = overlay,
	}, {
		UIKit.corner(14),
		UIKit.padding(14),
		UIKit.create("UISizeConstraint", { MaxSize = Vector2.new(620, 430) }),
	}) :: Frame

	local title = UIKit.label({
		Text = "Clans",
		Font = Theme.FontBold,
		TextSize = 22,
		Size = UDim2.new(1, -40, 0, 26),
		Parent = window,
	})
	local subtitle = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 13,
		Position = UDim2.new(0, 0, 0, 26),
		Size = UDim2.new(0.6, 0, 0, 16),
		Parent = window,
	})
	local statusLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.HpFill,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0.4, 0, 0, 26),
		Size = UDim2.new(0.6, -40, 0, 16),
		Parent = window,
	})
	local closeButton = UIKit.button({
		Text = "X",
		TextSize = 16,
		BackgroundColor3 = Theme.PanelLight,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(Layout.CLOSE_SIZE, Layout.CLOSE_SIZE),
		Parent = window,
	})

	local statusToken = 0
	local function showStatus(text: string)
		statusToken += 1
		local token = statusToken
		statusLabel.Text = text
		task.delay(3, function()
			if statusToken == token then
				statusLabel.Text = ""
			end
		end)
	end
	local function failMessage(reason: string?): string
		return FAIL_MESSAGES[reason or ""] or "Something went wrong. Try again."
	end
	local context: ClanTypes.Context = {
		showStatus = showStatus,
		failMessage = failMessage,
		request = function(action: string, arg: any?): Types.ClanResult
			local result = ClanController.request(action, arg)
			if not result.ok then
				showStatus(failMessage(result.reason))
			end
			return result
		end,
	}

	local body = UIKit.create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 48),
		Size = UDim2.new(1, 0, 1, -48),
		Parent = window,
	}) :: Frame

	---------------------------------------------------------------- not in a clan
	local noClan = UIKit.create("Frame", {
		Name = "NoClan",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = body,
	}) :: Frame

	local createBox = UIKit.create("Frame", {
		Name = "Create",
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Size = UDim2.new(0.4, -4, 1, 0),
		Parent = noClan,
	}, { UIKit.corner(8), UIKit.padding(10) }) :: Frame
	UIKit.label({ Text = "Create a clan", Font = Theme.FontBold, TextSize = 16, Size = UDim2.new(1, 0, 0, 20), Parent = createBox })

	local function textBox(placeholder: string, y: number, parent: Instance, width: UDim): TextBox
		return UIKit.create("TextBox", {
			Text = "",
			PlaceholderText = placeholder,
			ClearTextOnFocus = false,
			TextColor3 = Theme.Text,
			PlaceholderColor3 = Theme.Muted,
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			Font = Theme.Font,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.new(0, 0, 0, y),
			Size = UDim2.new(width.Scale, width.Offset, 0, 32),
			Parent = parent,
		}, { UIKit.corner(6), UIKit.padding(6) }) :: TextBox
	end
	local nameBox = textBox(`Clan name ({ClanConfig.NAME_MIN_LENGTH}-{ClanConfig.NAME_MAX_LENGTH})`, 28, createBox, UDim.new(1, 0))
	local tagBox = textBox(`Tag ({ClanConfig.TAG_MIN_LENGTH}-{ClanConfig.TAG_MAX_LENGTH})`, 66, createBox, UDim.new(1, 0))
	local requirementLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.Muted,
		TextSize = 12,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Position = UDim2.new(0, 0, 0, 104),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = createBox,
	})
	local createButton = UIKit.button({
		Text = "Create clan",
		TextSize = 15,
		BackgroundColor3 = Theme.Good,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = createBox,
	})

	local joinBox = UIKit.create("Frame", {
		Name = "Join",
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Position = UDim2.new(0.4, 4, 0, 0),
		Size = UDim2.new(0.6, -4, 1, 0),
		Parent = noClan,
	}, { UIKit.corner(8), UIKit.padding(10) }) :: Frame
	UIKit.label({ Text = "Join a clan", Font = Theme.FontBold, TextSize = 16, Size = UDim2.new(1, 0, 0, 20), Parent = joinBox })
	local searchBox = textBox("Search exact clan name", 28, joinBox, UDim.new(1, -150))
	local searchButton = UIKit.button({
		Text = "Search",
		TextSize = 13,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -74, 0, 28),
		Size = UDim2.new(0, 70, 0, 32),
		Parent = joinBox,
	})
	local refreshButton = UIKit.button({
		Text = "Browse",
		TextSize = 13,
		BackgroundColor3 = Theme.Panel,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 28),
		Size = UDim2.new(0, 70, 0, 32),
		Parent = joinBox,
	})
	local results = UIKit.create("ScrollingFrame", {
		Name = "Results",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 68),
		Size = UDim2.new(1, 0, 1, -68),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = joinBox,
	}, {
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	}) :: ScrollingFrame
	local resultRows: { Instance } = {}

	local function showClans(list: { ClanSummary })
		for _, row in resultRows do
			row:Destroy()
		end
		resultRows = {}
		if #list == 0 then
			table.insert(
				resultRows,
				UIKit.label({ Text = "No clans found.", TextColor3 = Theme.Muted, TextSize = 13, Size = UDim2.new(1, 0, 0, 24), Parent = results })
			)
			return
		end
		for order, clan in list do
			local row = UIKit.create("Frame", {
				LayoutOrder = order,
				BackgroundColor3 = Theme.Panel,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -8, 0, 34),
				Parent = results,
			}, { UIKit.corner(6) }) :: Frame
			table.insert(resultRows, row)
			local factionText = if clan.faction ~= "" and FactionConfig.FACTIONS[clan.faction] ~= nil
				then "  " .. FactionConfig.FACTIONS[clan.faction].displayName
				else ""
			UIKit.label({
				Text = `[{clan.tag}] {clan.name}{factionText}`,
				Font = Theme.FontBold,
				TextSize = 13,
				Position = UDim2.new(0, 8, 0, 0),
				Size = UDim2.new(1, -150, 1, 0),
				Parent = row,
			})
			UIKit.label({
				Text = `{clan.memberCount}/{ClanConfig.MAX_MEMBERS}`,
				TextColor3 = Theme.Muted,
				TextSize = 12,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -78, 0, 0),
				Size = UDim2.new(0, 50, 1, 0),
				Parent = row,
			})
			local join = UIKit.button({
				Text = if clan.open then "Join" else "Closed",
				TextSize = 12,
				BackgroundColor3 = if clan.open then Theme.Good else Theme.Disabled,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -4, 0.5, 0),
				Size = UDim2.new(0, 68, 1, -8),
				Parent = row,
			})
			join.Activated:Connect(function()
				if clan.open then
					task.spawn(context.request, "Join", clan.id)
				end
			end)
		end
	end

	local function browse()
		task.spawn(function()
			local result = context.request("Browse")
			if result.ok then
				showClans(result.clans or {})
			end
		end)
	end
	refreshButton.Activated:Connect(browse)
	searchButton.Activated:Connect(function()
		local text = searchBox.Text
		if #text == 0 then
			browse()
			return
		end
		task.spawn(function()
			local result = context.request("Search", text)
			if result.ok then
				showClans(result.clans or {})
			end
		end)
	end)
	createButton.Activated:Connect(function()
		task.spawn(function()
			local result = context.request("Create", { name = nameBox.Text, tag = tagBox.Text })
			if result.ok then
				showStatus("Clan created!")
			end
		end)
	end)

	---------------------------------------------------------------- in a clan
	local inClan = UIKit.create("Frame", {
		Name = "InClan",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = body,
	}) :: Frame
	local content = UIKit.create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 38),
		Size = UDim2.new(1, 0, 1, -38),
		Parent = inClan,
	}) :: Frame

	local tabs: { ClanTypes.Tab } = {
		ClanMembersTab.build(content, context),
		ClanBankTab.build(content, context),
		ClanRaidTab.build(content, context),
	}
	local activeTab = tabs[1]
	local tabButtons: { [ClanTypes.Tab]: TextButton } = {}

	local leaveButton = UIKit.button({
		Text = "Leave clan",
		TextSize = 12,
		BackgroundColor3 = Theme.HpFill,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 96, 0, 30),
		Parent = inClan,
	})
	local openButton = UIKit.button({
		Text = "",
		TextSize = 12,
		BackgroundColor3 = Theme.PanelLight,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -102, 0, 0),
		Size = UDim2.new(0, 110, 0, 30),
		Parent = inClan,
	})

	local function render()
		local view = ClanController.get()
		local snapshot = StateController.get()
		local hasClan = view ~= nil and view.inClan and view.clan ~= nil
		noClan.Visible = not hasClan
		inClan.Visible = hasClan

		if not hasClan or view == nil then
			title.Text = "Clans"
			subtitle.Text = "Team up: share a bank, buy clan perks, and fight a weekly raid boss."
			local best = if snapshot ~= nil then snapshot.bestStage else 0
			local needsFaction = ClanConfig.CLAN_REQUIRES_SAME_FACTION and snapshot ~= nil and snapshot.faction == ""
			requirementLabel.Text = `Needs best stage {ClanConfig.CREATE_MIN_BEST_STAGE} (yours: {best}).`
				.. (if needsFaction then " Join a faction first." else "")
			return
		end
		local clan = view.clan :: Types.ClanRecord
		title.Text = `[{clan.tag}] {clan.name}`
		subtitle.Text = `{clan.memberCount}/{ClanConfig.MAX_MEMBERS} members  |  {if clan.open then "Open" else "Closed"}`
			.. `  |  You: {view.myRole or "Member"}`
		openButton.Visible = view.myRole == "Leader"
		openButton.Text = if clan.open then "Close clan" else "Open clan"

		for tab, button in tabButtons do
			local active = tab == activeTab
			tab.frame.Visible = active
			button.BackgroundColor3 = if active then Theme.Accent else Theme.PanelLight
		end
		activeTab.render(view, snapshot)
	end

	for index, tab in tabs do
		local button = UIKit.button({
			Text = tab.title,
			TextSize = 13,
			BackgroundColor3 = Theme.PanelLight,
			Position = UDim2.new(0, (index - 1) * 86, 0, 0),
			Size = UDim2.new(0, 80, 0, 30),
			Parent = inClan,
		})
		button.Activated:Connect(function()
			activeTab = tab
			render()
		end)
		tabButtons[tab] = button
	end

	local confirmLeave = false
	leaveButton.Activated:Connect(function()
		if not confirmLeave then
			confirmLeave = true
			leaveButton.Text = "Click to confirm"
			task.delay(3, function()
				confirmLeave = false
				leaveButton.Text = "Leave clan"
			end)
			return
		end
		confirmLeave = false
		leaveButton.Text = "Leave clan"
		task.spawn(context.request, "Leave")
	end)
	openButton.Activated:Connect(function()
		local view = ClanController.get()
		if view ~= nil and view.clan ~= nil then
			task.spawn(context.request, "SetOpen", not view.clan.open)
		end
	end)

	clanButton.Activated:Connect(function()
		UIKit.openModal(overlay, window)
		render()
		local view = ClanController.get()
		if view == nil or not view.inClan then
			browse()
		end
	end)
	closeButton.Activated:Connect(function()
		overlay.Visible = false
	end)

	ClanController.Changed:Connect(function(_view: ClanView)
		if overlay.Visible then
			render()
		end
	end)
	StateController.Changed:Connect(function(snapshot: Types.Snapshot, previous: Types.Snapshot?)
		-- A raid attack just started: get the window out of the way so you can fight.
		if snapshot.encounter == "Raid" and (previous == nil or previous.encounter ~= "Raid") then
			overlay.Visible = false
		end
		if overlay.Visible then
			render()
		end
	end)

	gui.Parent = playerGui
end

return ClanUI
