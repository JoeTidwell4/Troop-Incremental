--!strict
-- The Mystery Merchant's window (MerchantConfig), opened from his camp spot while he's
-- visiting. Four offer cards (what it is, price, Buy / Sold) and a countdown until he
-- leaves. Each offer is exactly what it says. Prices in gold, Relic Dust or Honor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local BigNum = require(Shared:WaitForChild("BigNum"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Config = Shared:WaitForChild("Config")
local MerchantConfig = require(Config:WaitForChild("MerchantConfig"))
local GeneralConfig = require(Config:WaitForChild("GeneralConfig"))
local RelicConfig = require(Config:WaitForChild("RelicConfig"))
local CommanderConfig = require(Config:WaitForChild("CommanderConfig"))
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)
local Spotlight = require(script.Parent.Spotlight)
local StateController = require(Client.Controllers.StateController)
local AudioController = require(Client.Controllers.AudioController)
local CampController = require(Client.Controllers.CampController)

type Snapshot = Types.Snapshot
type Offer = Types.MerchantOffer

local Theme = UIKit.Theme
local COLOR = Color3.fromRGB(150, 100, 210)

local FAIL_MESSAGES: { [string]: string } = {
	Gone = "He's already packed up and left.",
	SoldOut = "Sold out.",
	Owned = "You already own that.",
	CantAfford = "You can't afford that yet.",
	Rejected = "Slow down a little!",
}

local MerchantUI = {}

local function timeText(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return `{seconds // 3600}h {(seconds % 3600) // 60}m`
	end
	return `{seconds // 60}:{string.format("%02d", seconds % 60)}`
end

-- (title, detail, color) for an offer.
local function describe(offer: Offer): (string, string, Color3)
	if offer.kind == "General" then
		local def = GeneralConfig.GENERALS[offer.item]
		local rarity = GeneralConfig.RARITIES[offer.rarity]
		return `1 copy: {def.name}`, `{offer.rarity} General, {def.title}. New, or a step toward the next star.`, rarity.color
	elseif offer.kind == "Relic" then
		local slot, set = string.match(offer.item, "^(%w+):(%w+)$")
		local rarity = RelicConfig.RARITIES[offer.rarity]
		local setDef = RelicConfig.SETS[set or ""]
		return `{offer.rarity} {if setDef ~= nil then setDef.name else ""} {slot or "relic"}`, `{rarity.lines} stat lines, rolled when you buy it.`, rarity.color
	elseif offer.kind == "Scrolls" then
		return `{offer.amount} Recruit Scrolls`, "Recruit Generals in ARMY > Generals.", Color3.fromRGB(90, 200, 140)
	elseif offer.kind == "HeroChest" then
		return "Hero Chest", "A gear pack that's always Epic or better.", Color3.fromRGB(230, 90, 90)
	elseif offer.kind == "DustBundle" then
		return `{offer.amount} Relic Dust`, "Upgrade and reroll relics.", Color3.fromRGB(170, 120, 230)
	end
	local def = CommanderConfig.ITEMS[offer.item]
	return if def ~= nil then def.displayName else "Rare cosmetic", `{if def ~= nil then def.slot else "Wardrobe"} cosmetic, looks only. Only he sells it.`, Color3.fromRGB(255, 200, 90)
end

local function priceText(offer: Offer): string
	if offer.currency == "Gold" then
		return `{NumberFormat.big(offer.price)} gold`
	elseif offer.currency == "Honor" then
		return `{NumberFormat.big(offer.price)} Honor`
	end
	return `{NumberFormat.number(BigNum.toNumber(offer.price))} Relic Dust`
end

local function canAfford(snapshot: Snapshot, offer: Offer): boolean
	if offer.currency == "Gold" then
		return BigNum.gte(snapshot.gold, offer.price)
	elseif offer.currency == "Honor" then
		return BigNum.gte(snapshot.honor, offer.price)
	end
	return snapshot.relicDust >= BigNum.toNumber(offer.price)
end

function MerchantUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local remote = Remotes.waitForFunction(Remotes.Functions.MerchantRequest)

	local gui = UIKit.create("ScreenGui", {
		Name = "Merchant",
		ResetOnSpawn = false,
		DisplayOrder = 15,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui
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
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = Layout.windowSize(0.7, 0.8),
		Parent = overlay,
	}, { UIKit.corner(14), UIKit.padding(14), UIKit.create("UISizeConstraint", { MaxSize = Vector2.new(640, 420) }) }) :: Frame
	UIKit.label({ Text = "Mystery Merchant", Font = Theme.FontBold, TextSize = 22, TextColor3 = COLOR, Size = UDim2.new(1, -50, 0, 28), Parent = window })
	local subtitle = UIKit.label({ Text = "", TextSize = 13, TextColor3 = Theme.Muted, Position = UDim2.new(0, 0, 0, 28), Size = UDim2.new(1, -50, 0, 16), Parent = window })
	local closeButton = UIKit.button({
		Text = "X",
		TextSize = 16,
		BackgroundColor3 = Theme.PanelLight,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(Layout.CLOSE_SIZE, Layout.CLOSE_SIZE),
		Parent = window,
	})
	local message = UIKit.label({ Text = "", TextSize = 12, TextColor3 = Theme.HpFill, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -50, 0, 28), Size = UDim2.new(0.6, 0, 0, 16), Parent = window })
	local away = UIKit.label({
		Text = "",
		TextSize = 15,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0.4, 0),
		Size = UDim2.new(1, 0, 0, 60),
		Parent = window,
	})
	local grid = UIKit.create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		Parent = window,
	}, { UIKit.create("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0.5, -5), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }) }) :: Frame

	type Card = { frame: Frame, stroke: UIStroke, title: TextLabel, detail: TextLabel, price: TextLabel, button: TextButton }
	local cards: { Card } = {}
	local busy = false
	local messageToken = 0
	for index = 1, MerchantConfig.OFFER_COUNT do
		local frame = UIKit.create("Frame", { BackgroundColor3 = Theme.PanelLight, BorderSizePixel = 0, LayoutOrder = index, Parent = grid }, { UIKit.corner(10), UIKit.padding(10) }) :: Frame
		local stroke = UIKit.create("UIStroke", { Color = COLOR, Thickness = 2, Parent = frame }) :: UIStroke
		local title = UIKit.label({ Text = "", Font = Theme.FontBold, TextSize = 15, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, Size = UDim2.new(1, 0, 0, 36), TextYAlignment = Enum.TextYAlignment.Top, Parent = frame })
		local detail = UIKit.label({ Text = "", TextSize = 12, TextColor3 = Theme.Muted, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.new(0, 0, 0, 38), Size = UDim2.new(1, 0, 0, 32), Parent = frame })
		local price = UIKit.label({ Text = "", TextSize = 13, TextColor3 = Theme.Gold, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, -110, 0, 34), TextWrapped = true, Parent = frame })
		local button = UIKit.button({ Text = "Buy", TextSize = 14, BackgroundColor3 = Theme.Good, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.fromOffset(100, 34), Parent = frame })
		button.Activated:Connect(function()
			if busy then
				return
			end
			busy = true
			local ok, result = pcall(function(): any
				return remote:InvokeServer("Buy", index)
			end)
			busy = false
			if ok and typeof(result) == "table" and result.ok then
				AudioController.play("Reward")
			else
				messageToken += 1
				local token = messageToken
				message.Text = FAIL_MESSAGES[if ok and typeof(result) == "table" then result.reason or "" else ""] or "That didn't work. Try again."
				task.delay(3, function()
					if messageToken == token then
						message.Text = ""
					end
				end)
			end
		end)
		cards[index] = { frame = frame, stroke = stroke, title = title, detail = detail, price = price, button = button }
	end

	local function render()
		local snapshot = StateController.get()
		if snapshot == nil then
			return
		end
		local merchant = snapshot.merchant
		local now = workspace:GetServerTimeNow()
		local here = merchant.leaveAt > now
		local anyLeft = false
		if here then
			for index in merchant.offers do
				if not merchant.bought[tostring(index)] then
					anyLeft = true
				end
			end
		end
		CampController.setBadge("Merchant", here and anyLeft)
		if not overlay.Visible then
			return
		end
		grid.Visible = here
		away.Visible = not here
		if not here then
			subtitle.Text = ""
			away.Text = if merchant.nextAt > now
				then `The Merchant is on the road. He'll be back in about {timeText(merchant.nextAt - now)}.`
				else "The Merchant is on the road."
			return
		end
		subtitle.Text = `Leaves in {timeText(merchant.leaveAt - now)}. Each offer can be bought once.`
		for index, card in cards do
			local offer = merchant.offers[index]
			card.frame.Visible = offer ~= nil
			if offer == nil then
				continue
			end
			local title, detail, color = describe(offer)
			card.title.Text = title
			card.title.TextColor3 = color
			card.stroke.Color = color
			card.detail.Text = detail
			card.price.Text = priceText(offer)
			local sold = merchant.bought[tostring(index)] == true
			local affordable = canAfford(snapshot, offer)
			card.button.Text = if sold then "Sold" elseif affordable then "Buy" else "Can't afford"
			card.button.BackgroundColor3 = if not sold and affordable then Theme.Good else Theme.Disabled
			card.button.AutoButtonColor = not sold and affordable
		end
	end

	closeButton.Activated:Connect(function()
		overlay.Visible = false
	end)
	Spotlight.registerOpener("Menu:Merchant", function()
		UIKit.openModal(overlay, window)
		render()
	end)
	StateController.Changed:Connect(render)
	task.spawn(function()
		while true do
			task.wait(1)
			render()
			-- He left while the window was open.
			local snapshot = StateController.get()
			if snapshot ~= nil and overlay.Visible and snapshot.merchant.leaveAt <= workspace:GetServerTimeNow() and snapshot.merchant.leaveAt > 0 then
				overlay.Visible = false
			end
		end
	end)

	gui.Parent = playerGui
end

return MerchantUI
