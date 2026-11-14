--!strict
-- ADVENTURE > Expeditions (ExpeditionConfig): teams away (time left / Collect), the
-- mission board (length, reward, favored House, Send), and a team picker of spare
-- Generals (not fielded, not away) with the power preview. The Scout Party can always go
-- on one mission. The server decides everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Config = Shared:WaitForChild("Config")
local ExpeditionConfig = require(Config:WaitForChild("ExpeditionConfig"))
local GeneralConfig = require(Config:WaitForChild("GeneralConfig"))
local RelicConfig = require(Config:WaitForChild("RelicConfig"))
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)
local Spotlight = require(script.Parent.Spotlight)
local AudioController = require(Client.Controllers.AudioController)
local StateController = require(Client.Controllers.StateController)
local ExpeditionController = require(Client.Controllers.ExpeditionController)
local NoticeUI = require(script.Parent.NoticeUI)

type Snapshot = Types.Snapshot
type Mission = Types.ExpeditionMission

local Theme = UIKit.Theme
local COLOR = Color3.fromRGB(90, 190, 140)
local ROW_HEIGHT = if Layout.compact then 50 else 44

local FAIL_MESSAGES: { [string]: string } = {
	Locked = `Expeditions open at best stage {ExpeditionConfig.UNLOCK_STAGE}.`,
	NoSlots = "All your teams are out. Collect one first.",
	NoMission = "That mission is gone. Pick another.",
	ScoutsBusy = "The Scout Party is already out. Send Generals instead.",
	Busy = "One of those Generals is already away.",
	Fielded = "Fielded Generals are busy fighting. Unfield them in ARMY > Generals.",
	NotBack = "Not back yet.",
	NoRerolls = "No reroll left today.",
	Rejected = "Slow down a little!",
}

local ExpeditionsTab = {}

local function timeText(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	if seconds >= 3600 then
		return `{seconds // 3600}h {(seconds % 3600) // 60}m`
	elseif seconds >= 60 then
		return `{seconds // 60}m {seconds % 60}s`
	end
	return `{seconds}s`
end

-- "+65 Relic Dust" for a mission at a reward scale.
local function rewardText(mission: Mission, scale: number, bestStage: number): string
	local base = ExpeditionConfig.DURATIONS[mission.duration].rewards[mission.reward]
	local amount = Formulas.expeditionAmount(mission, scale)
	if mission.reward == "Dust" then
		return `+{amount} Relic Dust`
	elseif mission.reward == "Gold" then
		return `{amount} min of gold`
	elseif mission.reward == "Honor" then
		return `+{NumberFormat.big(Formulas.scaledHonor(bestStage, amount, 1))} Honor`
	elseif mission.reward == "Scrolls" then
		return `+{amount} Recruit Scroll{if amount == 1 then "" else "s"}`
	elseif mission.reward == "Relic" then
		return `A {RelicConfig.RARITIES[base].name}+ relic`
	end
	return `+{amount} Hero Chest`
end

local function bonusOdds(): string
	local total = 0
	for _, entry in ExpeditionConfig.BONUS do
		total += entry.weight
	end
	local parts: { string } = {}
	for _, entry in ExpeditionConfig.BONUS do
		table.insert(parts, `{entry.text} {math.floor(entry.weight / total * 100 + 0.5)}%`)
	end
	return "Bonus when a team returns: " .. table.concat(parts, "  |  ")
end

function ExpeditionsTab.build(parent: Instance): { title: string, frame: Frame, render: (snapshot: Snapshot) -> () }
	local frame = UIKit.create("Frame", {
		Name = "Expeditions",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = parent,
	}) :: Frame
	local lockedLabel = UIKit.label({
		Text = `Expeditions open at best stage {ExpeditionConfig.UNLOCK_STAGE}.`,
		TextColor3 = Theme.Muted,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 60),
		Size = UDim2.new(1, 0, 0, 20),
		Visible = false,
		Parent = frame,
	})
	local list = UIKit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = frame,
	}, { UIKit.create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }) }) :: ScrollingFrame

	local message = UIKit.label({
		Text = "",
		TextColor3 = Theme.HpFill,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.new(0.7, 0, 0, 16),
		ZIndex = 5,
		Parent = frame,
	})
	local messageToken = 0
	local function say(reason: string?)
		messageToken += 1
		local token = messageToken
		message.Text = FAIL_MESSAGES[reason or ""] or "That didn't work. Try again."
		task.delay(3, function()
			if messageToken == token then
				message.Text = ""
			end
		end)
	end

	local function header(text: string, order: number): TextLabel
		return UIKit.label({ Text = text, Font = Theme.FontBold, TextSize = 15, TextColor3 = COLOR, LayoutOrder = order, Size = UDim2.new(1, -8, 0, 20), Parent = list })
	end
	local function row(order: number): (Frame, TextLabel, TextLabel, TextButton)
		local box = UIKit.create("Frame", {
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, ROW_HEIGHT),
			Parent = list,
		}, { UIKit.corner(8) }) :: Frame
		local title = UIKit.label({ Text = "", Font = Theme.FontBold, TextSize = 14, RichText = true, Position = UDim2.new(0, 10, 0, 4), Size = UDim2.new(1, -150, 0, 18), Parent = box })
		local sub = UIKit.label({ Text = "", TextSize = 12, TextColor3 = Theme.Muted, RichText = true, Position = UDim2.new(0, 10, 0, 23), Size = UDim2.new(1, -150, 0, 16), Parent = box })
		local button = UIKit.button({
			Text = "",
			TextSize = 13,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.new(0, 130, 0, ROW_HEIGHT - 10),
			Parent = box,
		})
		return box, title, sub, button
	end

	-- Teams away (up to 3 rows).
	local awayHeader = header("Teams away", 1)
	type Row = { box: Frame, title: TextLabel, sub: TextLabel, button: TextButton }
	local awayRows: { Row } = {}
	local maxSlots = ExpeditionConfig.SLOTS + 1
	for i = 1, maxSlots do
		local box, title, sub, button = row(1 + i)
		awayRows[i] = { box = box, title = title, sub = sub, button = button }
	end

	-- Board.
	local boardHeader = header("Mission board", 10)
	local rerollButton = UIKit.button({
		Text = "Reroll board",
		TextSize = 12,
		BackgroundColor3 = Theme.PanelLight,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 130, 1, 0),
		Parent = boardHeader,
	})
	local boardRows: { Row } = {}
	for i = 1, ExpeditionConfig.BOARD_SIZE do
		local box, title, sub, button = row(10 + i)
		boardRows[i] = { box = box, title = title, sub = sub, button = button }
	end
	Spotlight.register("Expedition:Send", boardRows[1].button)
	UIKit.label({
		Text = bonusOdds(),
		TextSize = 11,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		LayoutOrder = 30,
		Size = UDim2.new(1, -8, 0, 30),
		Parent = list,
	})

	---------------------------------------------------------------- team picker
	local picker = UIKit.create("Frame", {
		Name = "Picker",
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		ZIndex = 10,
		Parent = frame,
	}, { UIKit.corner(10) }) :: Frame
	local pickTitle = UIKit.label({ Text = "", Font = Theme.FontBold, TextSize = 16, RichText = true, ZIndex = 11, Size = UDim2.new(1, -110, 0, 20), Parent = picker })
	local pickInfo = UIKit.label({ Text = "", TextSize = 12, TextColor3 = Theme.Muted, RichText = true, ZIndex = 11, Position = UDim2.new(0, 0, 0, 22), Size = UDim2.new(1, -110, 0, 16), Parent = picker })
	local backButton = UIKit.button({ Text = "Back", TextSize = 13, BackgroundColor3 = Theme.PanelLight, ZIndex = 11, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 100, 0, 30), Parent = picker })
	local pickList = UIKit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 11,
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 1, -96),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = picker,
	}, { UIKit.create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) }) :: ScrollingFrame
	local powerLabel = UIKit.label({ Text = "", TextSize = 13, RichText = true, ZIndex = 11, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(1, -290, 0, 40), TextWrapped = true, Parent = picker })
	local scoutButton = UIKit.button({ Text = "Send Scouts", TextSize = 13, BackgroundColor3 = Theme.PanelLight, ZIndex = 11, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -146, 1, 0), Size = UDim2.new(0, 136, 0, 42), Parent = picker })
	local sendButton = UIKit.button({ Text = "Send team", TextSize = 14, BackgroundColor3 = COLOR, ZIndex = 11, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.new(0, 136, 0, 42), Parent = picker })

	local picking: Mission? = nil
	local chosen: { string } = {}
	local pickRows: { [string]: TextButton } = {}
	local busy = false

	local function renderPicker(snapshot: Snapshot)
		local mission = picking
		if mission == nil then
			picker.Visible = false
			return
		end
		picker.Visible = true
		local duration = ExpeditionConfig.DURATIONS[mission.duration]
		local house = GeneralConfig.HOUSES[mission.house]
		pickTitle.Text = `{duration.name}: {ExpeditionConfig.REWARDS[mission.reward].name}`
		pickInfo.Text = `Pick up to {ExpeditionConfig.TEAM_SIZE} spare Generals. <font color="#{house.color:ToHex()}">{house.name}</font> members count x{ExpeditionConfig.HOUSE_BONUS}.`

		-- Spare Generals: owned, not fielded, not away.
		local away: { [string]: boolean } = {}
		for _, run in snapshot.expeditions.active do
			for _, generalId in run.generals do
				away[generalId] = true
			end
		end
		local spare: { string } = {}
		for _, generalId in GeneralConfig.ORDER do
			if snapshot.generals.owned[generalId] ~= nil and table.find(snapshot.generals.fielded, generalId) == nil and not away[generalId] then
				table.insert(spare, generalId)
			end
		end
		for generalId, button in pickRows do
			if table.find(spare, generalId) == nil then
				button:Destroy()
				pickRows[generalId] = nil
			end
		end
		for i = #chosen, 1, -1 do
			if table.find(spare, chosen[i]) == nil then
				table.remove(chosen, i)
			end
		end
		for index, generalId in spare do
			local button = pickRows[generalId]
			if button == nil then
				local newButton = UIKit.button({ Text = "", TextSize = 13, RichText = true, ZIndex = 12, LayoutOrder = index, Size = UDim2.new(1, -8, 0, 34), Parent = pickList })
				newButton.TextXAlignment = Enum.TextXAlignment.Left
				UIKit.padding(10).Parent = newButton
				newButton.Activated:Connect(function()
					local at = table.find(chosen, generalId)
					if at ~= nil then
						table.remove(chosen, at)
					elseif #chosen < ExpeditionConfig.TEAM_SIZE then
						table.insert(chosen, generalId)
					end
					local current = StateController.get()
					if current ~= nil then
						renderPicker(current)
					end
				end)
				pickRows[generalId] = newButton
				button = newButton
			end
			local def = GeneralConfig.GENERALS[generalId]
			local state = snapshot.generals.owned[generalId]
			local memberHouse = Formulas.generalHouse(generalId)
			local match = memberHouse == mission.house or generalId == GeneralConfig.WILDCARD
			local picked = table.find(chosen, generalId) ~= nil
			local one = Formulas.expeditionPower(snapshot.generals, { generalId }, mission.house)
			local rarityColor = GeneralConfig.RARITIES[def.rarity].color
			button.Text = `{if picked then "[X] " else "[  ] "}<font color="#{rarityColor:ToHex()}">{def.name}</font>  {string.rep("*", state.stars)}  Lv {state.level}`
				.. `   power {math.floor(one * 10 + 0.5) / 10}{if match then "  <font color=\"#78E08C\">House match!</font>" else ""}`
			button.BackgroundColor3 = if picked then COLOR else Theme.PanelLight
		end
		if #spare == 0 then
			pickInfo.Text ..= "  You have no spare Generals: send the Scouts."
		end

		local scoutsOut = false
		for _, run in snapshot.expeditions.active do
			if #run.generals == 0 then
				scoutsOut = true
			end
		end
		local power = Formulas.expeditionPower(snapshot.generals, chosen, mission.house)
		local scale = Formulas.expeditionScale(mission.duration, power)
		local scoutScale = Formulas.expeditionScale(mission.duration, ExpeditionConfig.SCOUT_POWER)
		powerLabel.Text = if #chosen > 0
			then `Team power {math.floor(power * 10 + 0.5) / 10} / {duration.power} recommended: <b>{rewardText(mission, scale, snapshot.bestStage)}</b>`
			else `Scouts bring back {rewardText(mission, scoutScale, snapshot.bestStage)}.`
		sendButton.BackgroundColor3 = if #chosen > 0 then COLOR else Theme.Disabled
		sendButton.AutoButtonColor = #chosen > 0
		scoutButton.Text = if scoutsOut then "Scouts are out" else "Send Scouts"
		scoutButton.AutoButtonColor = not scoutsOut
		scoutButton.BackgroundColor3 = if scoutsOut then Theme.Disabled else Theme.PanelLight
	end

	local function send(team: { string })
		local mission = picking
		if mission == nil or busy then
			return
		end
		busy = true
		local result = ExpeditionController.request("Send", mission.id, team)
		busy = false
		if result.ok then
			picking = nil
			table.clear(chosen)
			picker.Visible = false
		else
			say(result.reason)
		end
	end
	sendButton.Activated:Connect(function()
		if #chosen > 0 then
			send(table.clone(chosen))
		end
	end)
	scoutButton.Activated:Connect(function()
		send({})
	end)
	backButton.Activated:Connect(function()
		picking = nil
		picker.Visible = false
	end)

	---------------------------------------------------------------- board + away

	local boardMissions: { Mission? } = {}
	for i, boardRow in boardRows do
		boardRow.button.Activated:Connect(function()
			local mission = boardMissions[i]
			local snapshot = StateController.get()
			if mission == nil or snapshot == nil then
				return
			end
			if #snapshot.expeditions.active >= snapshot.expeditionSlots then
				say("NoSlots")
				return
			end
			picking = mission
			table.clear(chosen)
			renderPicker(snapshot)
		end)
	end
	for slot, awayRow in awayRows do
		awayRow.button.Activated:Connect(function()
			if busy then
				return
			end
			busy = true
			local result = ExpeditionController.request("Collect", slot)
			busy = false
			if result.ok then
				AudioController.play("Reward")
				local loot = result.loot
				if loot ~= nil then
					local parts: { string } = {}
					if loot.gold ~= nil then
						table.insert(parts, `+{NumberFormat.big(loot.gold)} gold`)
					end
					if loot.honor ~= nil then
						table.insert(parts, `+{NumberFormat.number(loot.honor)} Honor`)
					end
					if loot.dust ~= nil then
						table.insert(parts, `+{loot.dust} Relic Dust`)
					end
					if loot.scrolls ~= nil then
						table.insert(parts, `+{loot.scrolls} Recruit Scroll{if loot.scrolls == 1 then "" else "s"}`)
					end
					if loot.heroChests ~= nil then
						table.insert(parts, `+{loot.heroChests} Hero Chest`)
					end
					if loot.relic then
						table.insert(parts, "a relic (see ARMY > Relics)")
					end
					local title = if loot.bonus == "Bountiful" then "BOUNTIFUL EXPEDITION!" elseif loot.bonus ~= "None" then "TEAM IS BACK + BONUS!" else "TEAM IS BACK!"
					NoticeUI.show(title, if #parts > 0 then table.concat(parts, ", ") else "Held for your main run.", COLOR)
				end
			else
				say(result.reason)
			end
		end)
	end
	rerollButton.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		local result = ExpeditionController.request("Reroll")
		busy = false
		if not result.ok then
			say(result.reason)
		end
	end)

	local function render(snapshot: Snapshot)
		local unlocked = snapshot.bestStage >= ExpeditionConfig.UNLOCK_STAGE
		lockedLabel.Visible = not unlocked
		list.Visible = unlocked
		if not unlocked then
			picker.Visible = false
			return
		end
		local exp = snapshot.expeditions
		local now = workspace:GetServerTimeNow()
		awayHeader.Text = `Teams away ({#exp.active}/{snapshot.expeditionSlots})`
			.. (if snapshot.expeditionSlots <= ExpeditionConfig.SLOTS then `  - 3rd team at best stage {ExpeditionConfig.THIRD_SLOT_STAGE}` else "")
		for slot, awayRow in awayRows do
			local run = exp.active[slot]
			awayRow.box.Visible = run ~= nil or slot <= snapshot.expeditionSlots
			if run == nil then
				awayRow.title.Text = "Free"
				awayRow.sub.Text = "Pick a mission below."
				awayRow.button.Visible = false
				continue
			end
			local mission = run.mission
			local names: { string } = {}
			for _, generalId in run.generals do
				table.insert(names, GeneralConfig.GENERALS[generalId].name)
			end
			local scale = Formulas.expeditionScale(mission.duration, run.power)
			awayRow.title.Text = `{if #names > 0 then table.concat(names, ", ") else "Scout Party"}: {rewardText(mission, scale, snapshot.bestStage)}`
			local left = run.endsAt - now
			awayRow.sub.Text = if left > 0 then `Back in {timeText(left)}` else `<font color="#78E08C">Back! Collect the loot.</font>`
			awayRow.button.Visible = true
			awayRow.button.Text = if left > 0 then timeText(left) else "Collect"
			awayRow.button.BackgroundColor3 = if left > 0 then Theme.Disabled else Theme.Good
			awayRow.button.AutoButtonColor = left <= 0
		end

		local rerollsLeft = if exp.rerollDay == snapshot.expeditions.day and exp.rerolls >= ExpeditionConfig.REROLLS_PER_DAY then 0 else ExpeditionConfig.REROLLS_PER_DAY
		rerollButton.Text = if rerollsLeft > 0 then "Reroll board (free)" else "Rerolled today"
		rerollButton.AutoButtonColor = rerollsLeft > 0
		local full = #exp.active >= snapshot.expeditionSlots
		for i, boardRow in boardRows do
			local mission = exp.board[i]
			boardMissions[i] = mission
			boardRow.box.Visible = mission ~= nil
			if mission == nil then
				continue
			end
			local duration = ExpeditionConfig.DURATIONS[mission.duration]
			local house = GeneralConfig.HOUSES[mission.house]
			boardRow.title.Text = `{duration.name}: {ExpeditionConfig.REWARDS[mission.reward].name}`
			boardRow.sub.Text = `At full power: {rewardText(mission, 1, snapshot.bestStage)}  |  <font color="#{house.color:ToHex()}">{house.name}</font> x{ExpeditionConfig.HOUSE_BONUS}`
			boardRow.button.Text = if full then "No free team" else "Send..."
			boardRow.button.BackgroundColor3 = if full then Theme.Disabled else COLOR
			boardRow.button.AutoButtonColor = not full
		end
		if picking ~= nil then
			renderPicker(snapshot)
		end
	end

	-- Count down every second while the tab is open (snapshots only come on changes).
	task.spawn(function()
		while true do
			task.wait(1)
			local snapshot = StateController.get()
			if snapshot ~= nil and frame.Visible and frame:IsDescendantOf(game) then
				render(snapshot)
			end
		end
	end)

	return { title = "Expeditions", frame = frame, render = render }
end

return ExpeditionsTab
