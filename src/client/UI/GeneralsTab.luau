--!strict
-- ARMY > Generals (Phase 13c): Recruit Scrolls + recruiting (odds and pity shown), the
-- 3 fielded slots, and the roster: stars, level, passive, trait, Field 1/2/3 and Level Up.
-- Recruits play the chest-style reveal (ChestRevealUI.playCard). The server decides.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local BigNum = require(Shared:WaitForChild("BigNum"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local GeneralConfig = require(Shared:WaitForChild("Config"):WaitForChild("GeneralConfig"))
local UIKit = require(script.Parent.UIKit)
local ChestRevealUI = require(script.Parent.ChestRevealUI)

type Snapshot = Types.Snapshot
type GeneralDef = Types.GeneralDef
type GeneralState = Types.GeneralState

local Theme = UIKit.Theme
local fmt = NumberFormat.number
local SCROLL_COLOR = Color3.fromRGB(230, 200, 140)
local STAT_NAMES: { [string]: string } = { damage = "army damage", armyHp = "army HP", gold = "gold", tap = "click damage" }

local FAIL_MESSAGES: { [string]: string } = {
	NoScrolls = "Not enough Recruit Scrolls.",
	Locked = `Generals unlock at stage {GeneralConfig.UNLOCK_STAGE}.`,
	CantAfford = "Not enough gold.",
	MaxLevel = "Max level for these stars. Recruit duplicates for more stars!",
	NotOwned = "Recruit this General first.",
}

local GeneralsTab = {}

local requestRemote: RemoteFunction? = nil
local function request(...: any): any
	local remote = requestRemote
	if remote == nil then
		remote = Remotes.waitForFunction(Remotes.Functions.GeneralRequest)
		requestRemote = remote
	end
	local args = table.pack(...)
	local ok, result = pcall(function(): any
		return (remote :: RemoteFunction):InvokeServer(table.unpack(args, 1, args.n))
	end)
	if ok and typeof(result) == "table" then
		return result
	end
	return { ok = false, reason = "NoResponse" }
end

local function stars(count: number): string
	return string.rep("★", count) .. string.rep("☆", GeneralConfig.MAX_STARS - count)
end

local function percent(value: number): string
	return `{math.floor(value * 100 + 0.5)}`
end

local function passiveText(def: GeneralDef, state: GeneralState?): string
	local power = if state ~= nil then Formulas.generalPassivePower(state) else 1
	return `+{percent(def.passive.value * power)}% {STAT_NAMES[def.passive.stat] or def.passive.stat}`
end

local function traitText(def: GeneralDef, state: GeneralState?): string
	local value = if state ~= nil then Formulas.generalTraitValue(def, state) else def.trait.value
	local shown = if def.trait.kind == "bossTime" then fmt(value) else percent(math.abs(value))
	return (string.gsub(def.trait.text, "{v}", shown))
end

function GeneralsTab.build(parent: Instance): { title: string, frame: Frame, render: (snapshot: Snapshot) -> () }
	local frame = UIKit.create("Frame", {
		Name = "Generals",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = parent,
	}) :: Frame

	---------------------------------------------------------------- recruit bar
	local scrollsLabel = UIKit.label({ Text = "", Font = Theme.FontBold, TextSize = 15, TextColor3 = SCROLL_COLOR, Size = UDim2.new(0.4, 0, 0, 20), Parent = frame })
	local oddsLabel = UIKit.label({ Text = "", TextColor3 = Theme.Muted, TextSize = 10, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, Position = UDim2.new(0, 0, 0, 20), Size = UDim2.new(0.55, 0, 0, 28), Parent = frame })
	local recruitOne = UIKit.button({ Text = "Recruit x1", TextSize = 13, BackgroundColor3 = Theme.Good, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -116, 0, 0), Size = UDim2.new(0, 110, 0, 44), Parent = frame })
	local recruitTen = UIKit.button({ Text = `Recruit x{GeneralConfig.MAX_RECRUIT_AT_ONCE}`, TextSize = 13, BackgroundColor3 = Theme.Good, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 110, 0, 44), Parent = frame })
	local statusLabel = UIKit.label({ Text = "", TextSize = 11, TextColor3 = Theme.Good, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.new(0, 0, 0, 50), Size = UDim2.new(1, 0, 0, 14), Parent = frame })
	local lockedLabel = UIKit.label({
		Text = `Generals unlock at stage {GeneralConfig.UNLOCK_STAGE}. Beat bosses to get there!`,
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

	---------------------------------------------------------------- fielded slots
	local slotLabels: { TextLabel } = {}
	for slot = 1, GeneralConfig.FIELD_SLOTS do
		local card = UIKit.create("Frame", {
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Position = UDim2.new((slot - 1) / GeneralConfig.FIELD_SLOTS, 3, 0, 68),
			Size = UDim2.new(1 / GeneralConfig.FIELD_SLOTS, -6, 0, 34),
			Parent = frame,
		}, { UIKit.corner(8), UIKit.create("UIStroke", { Color = SCROLL_COLOR, Thickness = 2 }) }) :: Frame
		slotLabels[slot] = UIKit.label({ Text = "", Font = Theme.FontBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 1, 0), Parent = card })
	end

	-- Active set bonuses (2-3 fielded Generals of one House).
	local setsLabel = UIKit.label({
		Text = "",
		RichText = true,
		TextSize = 11,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 0, 0, 105),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = frame,
	})

	---------------------------------------------------------------- roster
	local list = UIKit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 138),
		Size = UDim2.new(1, 0, 1, -138),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = frame,
	}, {
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		UIKit.create("UIPadding", { PaddingRight = UDim.new(0, 8) }),
	}) :: ScrollingFrame

	type Row = {
		frame: Frame,
		name: TextLabel,
		info: TextLabel,
		passive: TextLabel,
		trait: TextLabel,
		fieldButtons: { TextButton },
		levelButton: TextButton,
		maxButton: TextButton,
	}
	local rows: { [string]: Row } = {}
	local busy = false

	local function run(...: any): any
		if busy then
			return nil
		end
		busy = true
		local result = request(...)
		busy = false
		return result
	end

	for order, generalId in GeneralConfig.ORDER do
		local def = GeneralConfig.GENERALS[generalId]
		local rarity = GeneralConfig.RARITIES[def.rarity]
		local row = UIKit.create("Frame", {
			LayoutOrder = order,
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 70),
			Parent = list,
		}, { UIKit.corner(8), UIKit.create("UIStroke", { Color = rarity.color, Thickness = 1.5, Transparency = 0.3 }) }) :: Frame
		local houseId = Formulas.generalHouse(generalId)
		local house = GeneralConfig.HOUSES[houseId]
		local houseText = if house ~= nil
			then `<font color="#{house.color:ToHex()}">[{house.name}]</font>`
			else `<font color="#{rarity.color:ToHex()}">[Every House]</font>`
		local name = UIKit.label({
			Text = `{def.name}, {def.title}  {houseText}`,
			RichText = true,
			Font = Theme.FontBold,
			TextSize = 13,
			TextColor3 = rarity.color,
			Position = UDim2.new(0, 8, 0, 3),
			Size = UDim2.new(1, -200, 0, 16),
			Parent = row,
		})
		local info = UIKit.label({ Text = "", TextSize = 11, Position = UDim2.new(0, 8, 0, 19), Size = UDim2.new(1, -200, 0, 14), Parent = row })
		local passive = UIKit.label({ Text = "", TextSize = 11, TextColor3 = Theme.Good, Position = UDim2.new(0, 8, 0, 34), Size = UDim2.new(1, -200, 0, 14), Parent = row })
		local trait = UIKit.label({ Text = "", TextSize = 11, TextColor3 = SCROLL_COLOR, Position = UDim2.new(0, 8, 0, 50), Size = UDim2.new(1, -200, 0, 14), Parent = row })

		local fieldButtons: { TextButton } = {}
		for slot = 1, GeneralConfig.FIELD_SLOTS do
			local button = UIKit.button({
				Text = tostring(slot),
				TextSize = 12,
				BackgroundColor3 = Theme.Panel,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -6 - (GeneralConfig.FIELD_SLOTS - slot) * 34, 0, 6),
				Size = UDim2.new(0, 30, 0, 26),
				Parent = row,
			})
			button.Activated:Connect(function()
				task.spawn(function()
					local result = run("Field", slot, generalId)
					if result ~= nil and not result.ok then
						showStatus(FAIL_MESSAGES[result.reason or ""] or "Try again.", true)
					end
				end)
			end)
			fieldButtons[slot] = button
		end
		local levelButton = UIKit.button({ Text = "", TextSize = 11, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -56, 1, -6), Size = UDim2.new(0, 130, 0, 28), Parent = row })
		local maxButton = UIKit.button({ Text = "Max", TextSize = 11, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -6, 1, -6), Size = UDim2.new(0, 46, 0, 28), Parent = row })
		local function level(max: boolean)
			task.spawn(function()
				local result = run("LevelUp", generalId, max)
				if result ~= nil then
					if result.ok then
						showStatus(`{def.name} +{result.levels or 1} level{if (result.levels or 1) == 1 then "" else "s"}!`, false)
					else
						showStatus(FAIL_MESSAGES[result.reason or ""] or "Try again.", true)
					end
				end
			end)
		end
		levelButton.Activated:Connect(function()
			level(false)
		end)
		maxButton.Activated:Connect(function()
			level(true)
		end)
		rows[generalId] = { frame = row, name = name, info = info, passive = passive, trait = trait, fieldButtons = fieldButtons, levelButton = levelButton, maxButton = maxButton }
	end

	---------------------------------------------------------------- recruiting
	local function recruit(count: number)
		if ChestRevealUI.isPlaying() then
			return
		end
		task.spawn(function()
			local result = run("Recruit", count)
			if result == nil then
				return
			end
			if not result.ok or result.results == nil then
				showStatus(FAIL_MESSAGES[result.reason or ""] or "Try again.", true)
				return
			end
			-- Reveal the best one; list the rest.
			local best = result.results[1]
			local names: { string } = {}
			for _, entry in result.results do
				local entryDef = GeneralConfig.GENERALS[entry.id]
				if GeneralConfig.RARITIES[entryDef.rarity].order > GeneralConfig.RARITIES[GeneralConfig.GENERALS[best.id].rarity].order then
					best = entry
				end
				table.insert(names, entryDef.name .. (if entry.isNew then " (NEW)" else ""))
			end
			local def = GeneralConfig.GENERALS[best.id]
			local rarity = GeneralConfig.RARITIES[def.rarity]
			local status = if best.isNew then "NEW General! It joined your field if a slot was free."
				elseif best.shards > 0 then `Already 5 stars: +{best.shards} scroll shards`
				else `Duplicate: now {stars(best.stars)}`
			if #result.results > 1 then
				status = `{status}  (+{#result.results - 1} more, listed below)`
				showStatus("Recruited: " .. table.concat(names, ", "), false)
			end
			ChestRevealUI.playCard({
				header = "Recruit",
				rarityName = rarity.name,
				color = rarity.color,
				big = rarity.order >= GeneralConfig.RARITIES.Legendary.order,
				rare = rarity.order >= GeneralConfig.RARITIES.Epic.order,
				title = `{def.name}, {def.title}`,
				line = `{passiveText(def, nil)}  |  {traitText(def, nil)}`,
				status = status,
				statusGood = best.isNew,
			})
		end)
	end
	recruitOne.Activated:Connect(function()
		recruit(1)
	end)
	recruitTen.Activated:Connect(function()
		recruit(GeneralConfig.MAX_RECRUIT_AT_ONCE)
	end)

	---------------------------------------------------------------- render
	local function render(snapshot: Snapshot)
		local generals = snapshot.generals
		local unlocked = snapshot.bestStage >= GeneralConfig.UNLOCK_STAGE
		lockedLabel.Visible = not unlocked
		list.Visible = unlocked
		recruitOne.Visible = unlocked
		recruitTen.Visible = unlocked
		scrollsLabel.Text = `Recruit Scrolls: {generals.scrolls}` .. (if generals.shards > 0 then `  (+{generals.shards}/{GeneralConfig.SHARDS_PER_SCROLL} shards)` else "")
		local odds: { string } = {}
		for _, rarityId in GeneralConfig.RARITY_ORDER do
			table.insert(odds, `{rarityId} {GeneralConfig.RARITIES[rarityId].odds}%`)
		end
		oddsLabel.Text = table.concat(odds, "  ")
			.. `\nLegendary+ within {GeneralConfig.PITY_LEGENDARY - generals.pity.sinceLegendary}, Mythic within {GeneralConfig.PITY_MYTHIC - generals.pity.sinceMythic} recruits`
		recruitOne.BackgroundColor3 = if generals.scrolls >= 1 then Theme.Good else Theme.Disabled
		recruitTen.BackgroundColor3 = if generals.scrolls >= GeneralConfig.MAX_RECRUIT_AT_ONCE then Theme.Good else Theme.Disabled

		local bonuses = Formulas.generalBonuses(generals)
		local lines: { string } = {}
		for _, set in bonuses.sets do
			local house = GeneralConfig.HOUSES[set.houseId]
			local power = if set.power > 1 then ` (x{fmt(set.power)} from stars)` else ""
			table.insert(lines, `<font color="#{house.color:ToHex()}"><b>{house.name} ({set.count}):</b></font> {house.bonuses[set.count].text}{power}`)
		end
		setsLabel.Text = if #lines > 0 then table.concat(lines, "   ")
			else `<font color="#A0A5B9">Set bonus: field 2-3 Generals of the same House. {GeneralConfig.GENERALS[GeneralConfig.WILDCARD].name} counts for every House.</font>`
		for slot, label in slotLabels do
			local def = GeneralConfig.GENERALS[generals.fielded[slot] or ""]
			label.Text = if def ~= nil then `{slot}: {def.name}` else `{slot}: (empty)`
			label.TextColor3 = if def ~= nil then GeneralConfig.RARITIES[def.rarity].color else Theme.Muted
		end

		for _, generalId in GeneralConfig.ORDER do
			local def = GeneralConfig.GENERALS[generalId]
			local row = rows[generalId]
			local state = generals.owned[generalId]
			local fieldedSlot = table.find(generals.fielded, generalId)
			row.frame.BackgroundTransparency = if state ~= nil then 0 else 0.5
			if state == nil then
				row.info.Text = `{def.rarity}  |  not recruited yet`
				row.info.TextColor3 = Theme.Muted
			else
				local needed = GeneralConfig.STAR_COPIES[state.stars]
				local starText = if needed ~= nil then `  ({state.copies}/{needed} copies to next star)` else ""
				row.info.Text = `{stars(state.stars)}  Lv {state.level}/{Formulas.generalMaxLevel(state.stars)}{starText}`
					.. (if fieldedSlot ~= nil then `  |  FIELDED (slot {fieldedSlot})` else "")
				row.info.TextColor3 = if fieldedSlot ~= nil then SCROLL_COLOR else Theme.Text
			end
			row.passive.Text = "Passive: " .. passiveText(def, state)
			row.trait.Text = "Trait: " .. traitText(def, state)
			for slot, button in row.fieldButtons do
				button.Visible = state ~= nil
				button.BackgroundColor3 = if fieldedSlot == slot then SCROLL_COLOR else Theme.Accent
				button.TextColor3 = if fieldedSlot == slot then Theme.Panel else Theme.Text
			end
			row.levelButton.Visible = state ~= nil
			row.maxButton.Visible = state ~= nil
			if state ~= nil then
				local maxed = state.level >= Formulas.generalMaxLevel(state.stars)
				local cost = Formulas.generalLevelCost(generalId, state.level, snapshot.bestStage)
				local affordable = not maxed and BigNum.gte(snapshot.gold, cost)
				row.levelButton.Text = if maxed then "Max level (need stars)" else `Level up: {NumberFormat.big(cost)} gold`
				row.levelButton.BackgroundColor3 = if affordable then Theme.Good else Theme.Disabled
				row.maxButton.BackgroundColor3 = if affordable then Theme.Good else Theme.Disabled
			end
		end
	end

	return { title = "Generals", frame = frame, render = render }
end

return GeneralsTab
