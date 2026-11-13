--!strict
-- ARMY > Relics (Phase 13d). Left: the 6 slots (tap one to select what's in it) and the
-- active set bonuses. Right: the inventory (equipped first, then best) and the selected
-- relic's details: stat lines with Reroll, Equip / Unequip, Upgrade, Lock, Salvage. Top:
-- Relic Dust, drop odds + pity, and "salvage everything up to" buttons. Drops show as
-- floating text; Legendary and Mythic drops get the full reveal. The server decides.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local RelicConfig = require(Shared:WaitForChild("Config"):WaitForChild("RelicConfig"))
local UIKit = require(script.Parent.UIKit)
local ChestRevealUI = require(script.Parent.ChestRevealUI)
local RelicController = require(Client.Controllers.RelicController)
local DamageNumbersController = require(Client.Controllers.DamageNumbersController)

type Snapshot = Types.Snapshot
type RelicItem = Types.RelicItem
type RelicsData = Types.RelicsData

local Theme = UIKit.Theme
local fmt = NumberFormat.number
local DUST_COLOR = Color3.fromRGB(190, 160, 255)

local FAIL_MESSAGES: { [string]: string } = {
	NoDust = "Not enough Relic Dust. Salvage relics you don't need.",
	MaxLevel = "Already max level.",
	Protected = "Unequip or unlock it first.",
	NothingToSalvage = "Nothing to salvage (locked and equipped relics are kept).",
	NotFound = "That relic is gone.",
}

local RelicsTab = {}

-- "+7.8% army damage" / "+0.7s boss timer".
local function lineText(line: Types.RelicLine, level: number): string
	local stat = RelicConfig.STATS[line.stat]
	local value = Formulas.relicLineValue(line, level)
	if stat == nil then
		return "?"
	end
	if stat.percent then
		return `+{fmt(math.floor(value * 1000 + 0.5) / 10)}% {stat.name}`
	end
	return `+{fmt(math.floor(value * 10 + 0.5) / 10)}s {stat.name}`
end

local function rarityColor(rarity: string): Color3
	local def = RelicConfig.RARITIES[rarity]
	return if def ~= nil then def.color else Theme.Text
end

-- Equipped first, then rarity, then level.
local function sorted(relics: RelicsData): { RelicItem }
	local list: { RelicItem } = {}
	for _, item in relics.items do
		table.insert(list, item)
	end
	table.sort(list, function(a: RelicItem, b: RelicItem): boolean
		local ae, be = relics.equipped[a.slot] == a.id, relics.equipped[b.slot] == b.id
		if ae ~= be then
			return ae
		end
		local ar, br = RelicConfig.RARITIES[a.rarity].order, RelicConfig.RARITIES[b.rarity].order
		if ar ~= br then
			return ar > br
		end
		if a.level ~= b.level then
			return a.level > b.level
		end
		return (tonumber(a.id) or 0) > (tonumber(b.id) or 0)
	end)
	return list
end

function RelicsTab.build(parent: Instance): { title: string, frame: Frame, render: (snapshot: Snapshot) -> () }
	local frame = UIKit.create("Frame", {
		Name = "Relics",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = parent,
	}) :: Frame

	local selectedId: string? = nil
	local busy = false
	local renderAll: () -> () = function() end

	---------------------------------------------------------------- header
	local dustLabel = UIKit.label({ Text = "", Font = Theme.FontBold, TextSize = 15, TextColor3 = DUST_COLOR, Size = UDim2.new(0.35, 0, 0, 20), Parent = frame })
	local oddsLabel = UIKit.label({ Text = "", TextColor3 = Theme.Muted, TextSize = 10, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, Position = UDim2.new(0, 0, 0, 20), Size = UDim2.new(0.6, 0, 0, 26), Parent = frame })
	local statusLabel = UIKit.label({ Text = "", TextSize = 11, TextColor3 = Theme.Good, Position = UDim2.new(0, 0, 0, 46), Size = UDim2.new(1, 0, 0, 14), Parent = frame })
	local lockedLabel = UIKit.label({
		Text = `Relics drop from bosses once you reach stage {RelicConfig.UNLOCK_STAGE}.`,
		Font = Theme.FontBold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0.4, 0),
		Size = UDim2.new(1, 0, 0, 24),
		Visible = false,
		Parent = frame,
	})
	local function showStatus(text: string, bad: boolean)
		statusLabel.Text = text
		statusLabel.TextColor3 = if bad then Theme.HpFill else Theme.Good
	end
	local function run(action: string, arg: any, extra: any?, success: ((result: any) -> ())?)
		if busy then
			return
		end
		busy = true
		task.spawn(function()
			local result = RelicController.request(action, arg, extra)
			busy = false
			if result.ok then
				if success ~= nil then
					success(result)
				end
			else
				showStatus(FAIL_MESSAGES[result.reason or ""] or "Try again in a moment.", true)
			end
		end)
	end

	-- Salvage everything (unlocked, unequipped) up to Common / Rare / Epic.
	local salvageButtons: { TextButton } = {}
	for order = 1, 3 do
		local rarity = RelicConfig.RARITY_ORDER[order]
		local button = UIKit.button({
			Text = `Salvage all {rarity}{if order > 1 then " and below" else ""}`,
			TextSize = 10,
			TextWrapped = true,
			BackgroundColor3 = Theme.PanelLight,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(3 - order) * 88, 0, 0),
			Size = UDim2.new(0, 84, 0, 40),
			Parent = frame,
		})
		local armed = false
		button.Activated:Connect(function()
			if not armed then
				armed = true
				button.Text = "Click again"
				task.delay(3, function()
					armed = false
					button.Text = `Salvage all {rarity}{if order > 1 then " and below" else ""}`
				end)
				return
			end
			armed = false
			button.Text = `Salvage all {rarity}{if order > 1 then " and below" else ""}`
			run("SalvageBelow", order, nil, function(result)
				showStatus(`Salvaged {result.count or 0} relics for {result.dust or 0} Dust.`, false)
			end)
		end)
		salvageButtons[order] = button
	end

	---------------------------------------------------------------- left: slots + sets
	local left = UIKit.create("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 64), Size = UDim2.new(0.38, -4, 1, -64), Parent = frame }) :: Frame
	local slotButtons: { [string]: TextButton } = {}
	for index, slot in RelicConfig.SLOTS do
		local column = (index - 1) % 2
		local row = (index - 1) // 2
		local button = UIKit.button({
			Text = "",
			TextSize = 11,
			TextWrapped = true,
			BackgroundColor3 = Theme.PanelLight,
			Position = UDim2.new(column * 0.5, 2, 0, row * 52),
			Size = UDim2.new(0.5, -4, 0, 48),
			Parent = left,
		})
		button.Activated:Connect(function()
			local relics = RelicController.get()
			local id = if relics ~= nil then relics.equipped[slot] else nil
			if id ~= nil then
				selectedId = id
				renderAll()
			end
		end)
		slotButtons[slot] = button
	end
	local setsLabel = UIKit.label({
		Text = "",
		RichText = true,
		TextSize = 11,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 0, 0, 160),
		Size = UDim2.new(1, 0, 1, -160),
		Parent = left,
	})

	---------------------------------------------------------------- right: list + details
	local list = UIKit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0.38, 4, 0, 64),
		Size = UDim2.new(0.62, -4, 0.55, -64),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = frame,
	}, {
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
		UIKit.create("UIPadding", { PaddingRight = UDim.new(0, 8) }),
	}) :: ScrollingFrame

	local detail = UIKit.create("Frame", {
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Position = UDim2.new(0.38, 4, 0.55, 4),
		Size = UDim2.new(0.62, -4, 0.45, -4),
		Parent = frame,
	}, { UIKit.corner(8), UIKit.padding(8) }) :: Frame
	local detailName = UIKit.label({ Text = "Tap a relic to see it.", Font = Theme.FontBold, TextSize = 14, Size = UDim2.new(1, 0, 0, 18), Parent = detail })
	local lineRows: { { label: TextLabel, reroll: TextButton } } = {}
	for index = 1, 4 do
		local label = UIKit.label({ Text = "", TextSize = 12, Position = UDim2.new(0, 0, 0, 20 + (index - 1) * 20), Size = UDim2.new(1, -110, 0, 18), Parent = detail })
		local reroll = UIKit.button({ Text = "", TextSize = 10, BackgroundColor3 = Theme.Panel, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 20 + (index - 1) * 20), Size = UDim2.new(0, 104, 0, 18), Parent = detail })
		reroll.Activated:Connect(function()
			if selectedId ~= nil then
				run("Reroll", selectedId, index, function()
					showStatus("Rerolled!", false)
				end)
			end
		end)
		lineRows[index] = { label = label, reroll = reroll }
	end
	local actionNames = { "Equip", "Upgrade", "Lock", "Salvage" }
	local actionButtons: { [string]: TextButton } = {}
	for index, name in actionNames do
		local button = UIKit.button({
			Text = name,
			TextSize = 11,
			TextWrapped = true,
			BackgroundColor3 = Theme.Accent,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new((index - 1) / #actionNames, 2, 1, 0),
			Size = UDim2.new(1 / #actionNames, -4, 0, 32),
			Parent = detail,
		})
		actionButtons[name] = button
	end
	local salvageArmed = false
	actionButtons.Equip.Activated:Connect(function()
		local relics = RelicController.get()
		local item = if relics ~= nil and selectedId ~= nil then relics.items[selectedId] else nil
		if relics == nil or item == nil then
			return
		end
		if relics.equipped[item.slot] == item.id then
			run("Unequip", item.slot)
		else
			run("Equip", item.id)
		end
	end)
	actionButtons.Upgrade.Activated:Connect(function()
		if selectedId ~= nil then
			run("Upgrade", selectedId)
		end
	end)
	actionButtons.Lock.Activated:Connect(function()
		if selectedId ~= nil then
			run("Lock", selectedId)
		end
	end)
	actionButtons.Salvage.Activated:Connect(function()
		if selectedId == nil then
			return
		end
		if not salvageArmed then
			salvageArmed = true
			actionButtons.Salvage.Text = "Sure?"
			task.delay(3, function()
				salvageArmed = false
				renderAll()
			end)
			return
		end
		salvageArmed = false
		local id = selectedId
		run("Salvage", id, nil, function(result)
			showStatus(`Salvaged for {result.dust or 0} Dust.`, false)
			if selectedId == id then
				selectedId = nil
			end
		end)
	end)

	---------------------------------------------------------------- render
	local rowButtons: { TextButton } = {}
	local lastSnapshot: Snapshot? = nil

	local function renderDetail(relics: RelicsData)
		local item = if selectedId ~= nil then relics.items[selectedId] else nil
		for _, button in actionButtons do
			button.Visible = item ~= nil
		end
		if item == nil then
			detailName.Text = "Tap a relic to see it."
			detailName.TextColor3 = Theme.Muted
			for _, row in lineRows do
				row.label.Text = ""
				row.reroll.Visible = false
			end
			return
		end
		local equipped = relics.equipped[item.slot] == item.id
		detailName.Text = `{RelicController.nameOf(item)}  +{item.level}` .. (if item.locked then "  (locked)" else "")
		detailName.TextColor3 = rarityColor(item.rarity)
		local rerollCost = Formulas.relicRerollCost(item)
		for index, row in lineRows do
			local line = item.lines[index]
			row.label.Text = if line ~= nil then lineText(line, item.level) else ""
			row.reroll.Visible = line ~= nil
			row.reroll.Text = `Reroll: {rerollCost} Dust`
			row.reroll.BackgroundColor3 = if relics.dust >= rerollCost then Theme.Accent else Theme.Disabled
		end
		actionButtons.Equip.Text = if equipped then "Unequip" else "Equip"
		local maxed = item.level >= RelicConfig.MAX_LEVEL
		local upgradeCost = Formulas.relicUpgradeCost(item)
		actionButtons.Upgrade.Text = if maxed then "Max level" else `Upgrade\n{upgradeCost} Dust`
		actionButtons.Upgrade.BackgroundColor3 = if not maxed and relics.dust >= upgradeCost then Theme.Good else Theme.Disabled
		actionButtons.Lock.Text = if item.locked then "Unlock" else "Lock"
		if not salvageArmed then
			actionButtons.Salvage.Text = `Salvage\n+{Formulas.relicSalvageDust(item)} Dust`
		end
		actionButtons.Salvage.BackgroundColor3 = if item.locked or equipped then Theme.Disabled else Theme.HpFill
	end

	local function render(relics: RelicsData, snapshot: Snapshot)
		local unlocked = snapshot.bestStage >= RelicConfig.UNLOCK_STAGE
		lockedLabel.Visible = not unlocked
		left.Visible = unlocked
		list.Visible = unlocked
		detail.Visible = unlocked
		for _, button in salvageButtons do
			button.Visible = unlocked
		end
		local count = 0
		for _ in relics.items do
			count += 1
		end
		dustLabel.Text = `Relic Dust: {fmt(relics.dust)}   ({count}/{RelicConfig.MAX_ITEMS})`
		local odds: { string } = {}
		for _, rarityId in RelicConfig.RARITY_ORDER do
			table.insert(odds, `{rarityId} {RelicConfig.RARITIES[rarityId].odds}%`)
		end
		oddsLabel.Text = `{math.floor(RelicConfig.DROP_CHANCE * 100)}% per boss: ` .. table.concat(odds, " ")
			.. `\nLegendary+ within {RelicConfig.PITY_LEGENDARY - relics.pity.sinceLegendary}, Mythic within {RelicConfig.PITY_MYTHIC - relics.pity.sinceMythic} drops`

		for _, slot in RelicConfig.SLOTS do
			local button = slotButtons[slot]
			local item = relics.items[relics.equipped[slot] or ""]
			if item ~= nil then
				button.Text = `{slot}\n{item.rarity} {RelicConfig.SETS[item.set].name} +{item.level}`
				button.TextColor3 = rarityColor(item.rarity)
			else
				button.Text = `{slot}\n(empty)`
				button.TextColor3 = Theme.Muted
			end
		end

		local bonuses = Formulas.relicBonuses(relics)
		local lines: { string } = {}
		for _, set in bonuses.sets do
			local def = RelicConfig.SETS[set.setId]
			local parts: { string } = {}
			for _, pieces in { 2, 4, 6 } do
				if set.count >= pieces then
					table.insert(parts, def.bonuses[pieces].text)
				end
			end
			table.insert(lines, `<font color="#{def.color:ToHex()}"><b>{def.name} ({set.count}):</b></font> {table.concat(parts, ", ")}`)
		end
		setsLabel.Text = if #lines > 0 then table.concat(lines, "\n")
			else `<font color="#A0A5B9">Sets: equip 2, 4 or 6 relics of the same set for bonuses.</font>`

		-- Inventory rows (rebuilt; at most MAX_ITEMS).
		for _, button in rowButtons do
			button:Destroy()
		end
		rowButtons = {}
		for order, item in sorted(relics) do
			local equipped = relics.equipped[item.slot] == item.id
			local setDef = RelicConfig.SETS[item.set]
			local button = UIKit.button({
				LayoutOrder = order,
				Text = `{if equipped then "[E] " else ""}{if item.locked then "* " else ""}{RelicController.nameOf(item)} +{item.level}`,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = rarityColor(item.rarity),
				BackgroundColor3 = if selectedId == item.id then Theme.Accent else Theme.PanelLight,
				Size = UDim2.new(1, 0, 0, 24),
				Parent = list,
			})
			UIKit.create("UIPadding", { PaddingLeft = UDim.new(0, 10), Parent = button })
			UIKit.create("Frame", { BackgroundColor3 = setDef.color, BorderSizePixel = 0, Size = UDim2.new(0, 4, 1, 0), Position = UDim2.new(0, -10, 0, 0), Parent = button })
			local id = item.id
			button.Activated:Connect(function()
				selectedId = id
				renderAll()
			end)
			table.insert(rowButtons, button)
		end
		renderDetail(relics)
	end

	renderAll = function()
		local relics = RelicController.get()
		if relics ~= nil and lastSnapshot ~= nil then
			render(relics, lastSnapshot)
		end
	end

	RelicController.Changed:Connect(function()
		if frame.Visible then
			renderAll()
		end
	end)

	-- Drops: floating text, and the big reveal for Legendary and Mythic.
	RelicController.Dropped:Connect(function(item: RelicItem, dust: number?)
		local def = RelicConfig.RARITIES[item.rarity]
		if dust ~= nil then
			DamageNumbersController.show(`Relic -> +{dust} Dust (inventory full)`, DUST_COLOR, 24)
			return
		end
		DamageNumbersController.show(`RELIC: {RelicController.nameOf(item)}`, def.color, 26)
		if def.order >= RelicConfig.RARITIES.Legendary.order and not ChestRevealUI.isPlaying() then
			local summary: { string } = {}
			for _, line in item.lines do
				table.insert(summary, lineText(line, 0))
			end
			ChestRevealUI.playCard({
				header = "Relic",
				rarityName = def.name,
				color = def.color,
				big = true,
				rare = true,
				title = RelicController.nameOf(item),
				line = table.concat(summary, ", "),
				status = "Equip it in ARMY > Relics.",
				statusGood = true,
			})
		end
	end)

	-- ARMY calls this on every snapshot (several times a second). The inventory only
	-- changes on RelicSync (handled above), so only redraw here the first time.
	local function renderFromSnapshot(snapshot: Snapshot)
		local first = lastSnapshot == nil
		lastSnapshot = snapshot
		if first then
			renderAll()
		end
	end

	local wasVisible = false
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible and not wasVisible then
			renderAll()
		end
		wasVisible = frame.Visible
	end)

	return { title = "Relics", frame = frame, render = renderFromSnapshot }
end

return RelicsTab
