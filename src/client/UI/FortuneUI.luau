--!strict
-- The Fortune Wheel window (FortuneConfig), opened from its camp structure. The 8 prizes
-- sit in a ring; a glowing marker runs around, slows down and stops on the prize the
-- server rolled (the client never decides). Odds and the Jackpot pity are shown. Click
-- anywhere in the window while it spins to skip to the result.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local FortuneConfig = require(Shared:WaitForChild("Config"):WaitForChild("FortuneConfig"))
local UIKit = require(script.Parent.UIKit)
local Layout = require(script.Parent.Layout)
local Spotlight = require(script.Parent.Spotlight)
local NoticeUI = require(script.Parent.NoticeUI)
local ChestRevealUI = require(script.Parent.ChestRevealUI)
local StateController = require(Client.Controllers.StateController)
local AudioController = require(Client.Controllers.AudioController)
local CampController = require(Client.Controllers.CampController)

type Snapshot = Types.Snapshot

local Theme = UIKit.Theme
local WOOD = Color3.fromRGB(120, 85, 55)
local RING_RADIUS = 128
local TILE = Vector2.new(104, 52)

local FAIL_MESSAGES: { [string]: string } = {
	Locked = `The Fortune Wheel opens at stage {FortuneConfig.UNLOCK_STAGE}.`,
	NoSpins = "No spins left. You get a free one every day.",
	Rejected = "Slow down a little!",
}

local FortuneUI = {}

local function timeText(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return `{seconds // 3600}h {(seconds % 3600) // 60}m`
	end
	return `{seconds // 60}m {seconds % 60}s`
end

local function oddsText(): string
	local total = 0
	for _, prize in FortuneConfig.PRIZES do
		total += prize.weight
	end
	local parts: { string } = {}
	for _, prize in FortuneConfig.PRIZES do
		table.insert(parts, `{prize.name} {math.floor(prize.weight / total * 1000 + 0.5) / 10}%`)
	end
	return "Odds: " .. table.concat(parts, "  |  ")
end

function FortuneUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local remote = Remotes.waitForFunction(Remotes.Functions.FortuneRequest)

	local gui = UIKit.create("ScreenGui", {
		Name = "Fortune",
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
	local window = UIKit.create("TextButton", { -- a button, so clicking it skips the spin
		Name = "Window",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = Layout.windowSize(0.6, 0.9),
		Parent = overlay,
	}, { UIKit.corner(14), UIKit.padding(14), UIKit.create("UISizeConstraint", { MaxSize = Vector2.new(560, 520) }) }) :: TextButton
	UIKit.label({ Text = "Fortune Wheel", Font = Theme.FontBold, TextSize = 22, TextColor3 = Theme.Gold, Size = UDim2.new(1, -50, 0, 28), Parent = window })
	local spinsLabel = UIKit.label({ Text = "", TextSize = 13, TextColor3 = Theme.Muted, Position = UDim2.new(0, 0, 0, 28), Size = UDim2.new(1, -50, 0, 16), Parent = window })
	local closeButton = UIKit.button({
		Text = "X",
		TextSize = 16,
		BackgroundColor3 = Theme.PanelLight,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(Layout.CLOSE_SIZE, Layout.CLOSE_SIZE),
		Parent = window,
	})

	-- The ring of prizes.
	local ring = UIKit.create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 50),
		Size = UDim2.fromOffset(RING_RADIUS * 2 + TILE.X, RING_RADIUS * 2 + TILE.Y),
		Parent = window,
	}) :: Frame
	local disc = UIKit.create("Frame", {
		BackgroundColor3 = WOOD,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(RING_RADIUS * 2 - 20, RING_RADIUS * 2 - 20),
		Parent = ring,
	}, { UIKit.corner(999), UIKit.create("UIStroke", { Color = Color3.fromRGB(170, 175, 185), Thickness = 4 }) }) :: Frame
	local tiles: { Frame } = {}
	for i, prize in FortuneConfig.PRIZES do
		local angle = (i - 1) / #FortuneConfig.PRIZES * math.pi * 2
		local tile = UIKit.create("Frame", {
			BackgroundColor3 = Theme.PanelLight,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.sin(angle) * RING_RADIUS, 0.5, -math.cos(angle) * RING_RADIUS),
			Size = UDim2.fromOffset(TILE.X, TILE.Y),
			ZIndex = 2,
			Parent = ring,
		}, { UIKit.corner(10), UIKit.create("UIStroke", { Color = prize.color, Thickness = 3 }) }) :: Frame
		UIKit.label({
			Text = prize.name,
			Font = Theme.FontBold,
			TextSize = if prize.id == FortuneConfig.JACKPOT then 16 else 13,
			TextColor3 = prize.color,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -6, 1, 0),
			Position = UDim2.new(0, 3, 0, 0),
			ZIndex = 3,
			Parent = tile,
		})
		tiles[i] = tile
	end
	local marker = UIKit.create("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 240, 180),
		BackgroundTransparency = 0.55,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(TILE.X + 12, TILE.Y + 12),
		ZIndex = 4,
		Parent = ring,
	}, { UIKit.corner(12), UIKit.create("UIStroke", { Color = Color3.fromRGB(255, 225, 120), Thickness = 4 }) }) :: Frame
	local spinButton = UIKit.button({
		Text = "SPIN",
		TextSize = 26,
		BackgroundColor3 = Color3.fromRGB(200, 60, 50),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -10),
		Size = UDim2.fromOffset(130, 60),
		ZIndex = 5,
		Parent = disc,
	})
	local pityLabel = UIKit.label({
		Text = "",
		TextSize = 12,
		TextColor3 = Color3.fromRGB(255, 235, 200),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 26),
		Size = UDim2.fromOffset(170, 34),
		ZIndex = 5,
		Parent = disc,
	})
	local message = UIKit.label({ Text = "", TextSize = 13, TextColor3 = Theme.HpFill, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -40), Size = UDim2.new(1, 0, 0, 18), Parent = window })
	UIKit.label({
		Text = oddsText() .. `. Spins are free and never sold. Up to {FortuneConfig.MAX_SPINS} can be saved.`,
		TextSize = 11,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 38),
		Parent = window,
	})

	local current = 1
	local spinning = false
	local skip = false
	local function place(index: number)
		marker.Position = tiles[index].Position
	end
	place(current)

	local function render()
		local snapshot = StateController.get()
		if snapshot == nil then
			return
		end
		local unlocked = snapshot.bestStage >= FortuneConfig.UNLOCK_STAGE
		CampController.setBadge("Wheel", unlocked and snapshot.fortuneSpins > 0)
		if not overlay.Visible then
			return
		end
		if not unlocked then
			spinsLabel.Text = `Opens at stage {FortuneConfig.UNLOCK_STAGE}.`
		else
			local freeIn = snapshot.fortuneFreeAt - workspace:GetServerTimeNow()
			spinsLabel.Text = `Spins: {snapshot.fortuneSpins}/{FortuneConfig.MAX_SPINS}   |   next free spin in {timeText(freeIn)}`
		end
		pityLabel.Text = `JACKPOT guaranteed within {math.max(1, FortuneConfig.PITY_JACKPOT - snapshot.fortunePity)} spins`
		local can = unlocked and snapshot.fortuneSpins > 0 and not spinning
		spinButton.BackgroundColor3 = if can then Color3.fromRGB(200, 60, 50) else Theme.Disabled
		spinButton.AutoButtonColor = can
	end

	local function show(result: Types.FortuneResult)
		local prize = FortuneConfig.PRIZES[result.index or 1]
		local parts: { string } = {}
		if result.gold ~= nil then
			table.insert(parts, `+{NumberFormat.big(result.gold)} gold`)
		end
		if result.honor ~= nil then
			table.insert(parts, `+{NumberFormat.number(result.honor)} Honor`)
		end
		if result.dust ~= nil then
			table.insert(parts, `+{result.dust} Relic Dust`)
		end
		if prize.reward.scrolls ~= nil then
			table.insert(parts, `+{prize.reward.scrolls} Recruit Scrolls`)
		end
		if prize.reward.heroChests ~= nil then
			table.insert(parts, `+{prize.reward.heroChests} Hero Chest`)
		end
		if result.relic then
			table.insert(parts, "a relic (ARMY > Relics)")
		end
		if prize.reward.goldMinutes ~= nil and result.gold == nil then
			table.insert(parts, "gold held for your main run")
		end
		local text = table.concat(parts, ", ")
		if prize.id == FortuneConfig.JACKPOT then
			ChestRevealUI.playCard({
				header = "Fortune Wheel",
				rarityName = "JACKPOT",
				color = prize.color,
				big = true,
				rare = true,
				title = "JACKPOT!",
				line = text,
				status = "",
				statusGood = true,
			})
		else
			AudioController.play("Reward")
			NoticeUI.show(string.upper(prize.name) .. "!", text, prize.color)
		end
	end

	local function spin()
		if spinning then
			return
		end
		local snapshot = StateController.get()
		if snapshot == nil or snapshot.fortuneSpins <= 0 then
			message.Text = FAIL_MESSAGES.NoSpins
			return
		end
		spinning = true
		skip = false
		message.Text = ""
		render()
		local ok, result = pcall(function(): any
			return remote:InvokeServer("Spin")
		end)
		if not ok or typeof(result) ~= "table" or not result.ok then
			spinning = false
			message.Text = FAIL_MESSAGES[if ok and typeof(result) == "table" then result.reason or "" else ""] or "That didn't work. Try again."
			render()
			return
		end
		-- Two full laps, then on to the prize, slowing down.
		local target = result.index :: number
		local count = #tiles
		local steps = count * 2 + ((target - current) % count)
		for step = 1, steps do
			if skip then
				break
			end
			current = current % count + 1
			place(current)
			AudioController.play("UIClick")
			local progress = step / steps
			task.wait(0.04 + 0.32 * progress ^ 3)
		end
		current = target
		place(current)
		UIKit.bump(tiles[current], 0.2)
		spinning = false
		render()
		show(result :: Types.FortuneResult)
	end

	spinButton.Activated:Connect(function()
		task.spawn(spin)
	end)
	window.Activated:Connect(function()
		if spinning then
			skip = true
		end
	end)
	closeButton.Activated:Connect(function()
		if not spinning then
			overlay.Visible = false
		end
	end)
	local function open()
		UIKit.openModal(overlay, window)
		render()
	end
	Spotlight.registerOpener("Menu:Wheel", open)
	StateController.Changed:Connect(render)
	task.spawn(function()
		while true do
			task.wait(1)
			if overlay.Visible then
				render()
			end
		end
	end)

	gui.Parent = playerGui
end

return FortuneUI
