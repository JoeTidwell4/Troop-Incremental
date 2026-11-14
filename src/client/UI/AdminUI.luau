--!strict
-- The owner's ADMIN panel (server AdminService, which checks ownership on every request;
-- this button only appears for the owner). Two parts:
--   Free passes: type a username, tick passes, GIVE (exactly those) / TAKE ALL AWAY.
--   Promo codes: code + rewards + days + max uses, CREATE (or edit an existing code);
--                the list shows each code's uses and a Delete button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = Shared:WaitForChild("Config")
local PromoConfig = require(Config:WaitForChild("PromoConfig"))
local MonetizationConfig = require(Config:WaitForChild("MonetizationConfig"))
local UIKit = require(script.Parent.UIKit)

local Theme = UIKit.Theme
local ADMIN_COLOR = Color3.fromRGB(150, 70, 200)
local ROW = 32

local AdminUI = {}

local function textBox(placeholder: string, parent: Instance, order: number, width: UDim?): TextBox
	return UIKit.create("TextBox", {
		Text = "",
		PlaceholderText = placeholder,
		ClearTextOnFocus = false,
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.Muted,
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Size = UDim2.new(width or UDim.new(1, -8), UDim.new(0, ROW)),
		Parent = parent,
	}, { UIKit.corner(6) }) :: TextBox
end

local function heading(text: string, parent: Instance, order: number)
	UIKit.label({ Text = text, Font = Theme.FontBold, TextSize = 16, TextColor3 = ADMIN_COLOR, LayoutOrder = order, Size = UDim2.new(1, -8, 0, 22), Parent = parent })
end

local function note(text: string, parent: Instance, order: number): TextLabel
	return UIKit.label({
		Text = text,
		TextSize = 12,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, 14),
		Parent = parent,
	})
end

function AdminUI.start()
	local player = Players.LocalPlayer
	if player:GetAttribute("IsGameOwner") ~= true then
		player:GetAttributeChangedSignal("IsGameOwner"):Wait()
	end
	local remote = Remotes.waitForFunction(Remotes.Functions.AdminRequest)

	local gui = UIKit.create("ScreenGui", {
		Name = "Admin",
		ResetOnSpawn = false,
		DisplayOrder = 29,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui
	local toggle = UIKit.button({
		Text = "ADMIN",
		TextSize = 14,
		BackgroundColor3 = ADMIN_COLOR,
		Position = UDim2.new(0, 78, 0, 6),
		Size = UDim2.fromOffset(70, 28),
		Parent = gui,
	})
	local window = UIKit.panel({
		Visible = false,
		Position = UDim2.new(0, 8, 0, 40),
		Size = UDim2.new(0, 380, 1, -60),
		BackgroundTransparency = 0.05,
		Parent = gui,
	})
	UIKit.create("UISizeConstraint", { MaxSize = Vector2.new(380, 640), Parent = window })
	local status = UIKit.label({
		Text = "Owner tools. Only you can see this.",
		TextSize = 12,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.new(1, 0, 0, 30),
		Parent = window,
	})
	local list = UIKit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 32),
		Size = UDim2.new(1, 0, 1, -32),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = window,
	}, { UIKit.create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }) }) :: ScrollingFrame

	local busy = false
	local renderLists: (Types.AdminResult) -> () = function() end
	local function send(action: string, payload: any)
		if busy then
			return
		end
		busy = true
		status.Text = "Working..."
		status.TextColor3 = Theme.Muted
		task.spawn(function()
			local ok, result = pcall(function(): any
				return remote:InvokeServer(action, payload)
			end)
			busy = false
			if ok and typeof(result) == "table" then
				if result.message ~= "" then
					status.Text = result.message
				else
					status.Text = "Owner tools. Only you can see this."
				end
				status.TextColor3 = if result.ok then Theme.Good else Theme.HpFill
				if result.codes ~= nil then
					renderLists(result)
				end
			else
				status.Text = "No answer from the server. Try again."
				status.TextColor3 = Theme.HpFill
			end
		end)
	end

	---------------------------------------------------------------- free passes
	heading("Free passes", list, 1)
	note("Gives a player the pass's effect in this game (not on their Roblox profile). Works even if they're offline.", list, 2)
	local nameBox = textBox("Roblox username", list, 3)
	local passRow = UIKit.create("Frame", { BackgroundTransparency = 1, LayoutOrder = 4, Size = UDim2.new(1, -8, 0, ROW), Parent = list }, {
		UIKit.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
	}) :: Frame
	local picked: { [string]: boolean } = {}
	for _, passKey in MonetizationConfig.PASS_ORDER do
		local def = MonetizationConfig.PASSES[passKey]
		if def.id > 0 then
			local button = UIKit.button({ Text = def.displayName, TextSize = 12, BackgroundColor3 = Theme.PanelLight, Size = UDim2.new(0, 116, 1, 0), Parent = passRow })
			button.Activated:Connect(function()
				picked[passKey] = not picked[passKey]
				button.BackgroundColor3 = if picked[passKey] then Theme.Good else Theme.PanelLight
			end)
		end
	end
	local passButtons = UIKit.create("Frame", { BackgroundTransparency = 1, LayoutOrder = 5, Size = UDim2.new(1, -8, 0, ROW), Parent = list }, {
		UIKit.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
	}) :: Frame
	local giveButton = UIKit.button({ Text = "GIVE", TextSize = 13, BackgroundColor3 = Theme.Good, Size = UDim2.new(0.5, -3, 1, 0), Parent = passButtons })
	local takeButton = UIKit.button({ Text = "TAKE ALL AWAY", TextSize = 13, BackgroundColor3 = Theme.HpFill, Size = UDim2.new(0.5, -3, 1, 0), Parent = passButtons })
	giveButton.Activated:Connect(function()
		local passes: { string } = {}
		for passKey, on in picked do
			if on then
				table.insert(passes, passKey)
			end
		end
		if #passes == 0 then
			status.Text = "Tick at least one pass first."
			status.TextColor3 = Theme.HpFill
			return
		end
		send("GrantPasses", { name = nameBox.Text, passes = passes })
	end)
	takeButton.Activated:Connect(function()
		send("GrantPasses", { name = nameBox.Text, passes = {} })
	end)
	local grantsLabel = note("", list, 6)

	---------------------------------------------------------------- promo codes
	heading("Promo codes", list, 10)
	note("Players type the code in SETTINGS, once each. Rewards are in-game items only. Leave a box empty for 0.", list, 11)
	local codeBox = textBox("Code, e.g. LAUNCH", list, 12)
	local rewardBoxes: { [string]: TextBox } = {}
	for i, field in PromoConfig.REWARD_ORDER do
		local def = PromoConfig.REWARDS[field]
		rewardBoxes[field] = textBox(`{def.name} (max {def.max})`, list, 12 + i)
	end
	local daysBox = textBox("Lasts how many days? (default 7)", list, 30)
	local usesBox = textBox("Max uses in total (empty = no limit)", list, 31)
	local createButton = UIKit.button({ Text = "CREATE / UPDATE CODE", TextSize = 13, BackgroundColor3 = ADMIN_COLOR, LayoutOrder = 32, Size = UDim2.new(1, -8, 0, ROW), Parent = list })
	createButton.Activated:Connect(function()
		local rewards: { [string]: number } = {}
		for field, box in rewardBoxes do
			local value = tonumber(box.Text)
			if value ~= nil then
				rewards[field] = value
			end
		end
		send("CreateCode", {
			code = codeBox.Text,
			rewards = rewards,
			days = tonumber(daysBox.Text) or 7,
			maxUses = tonumber(usesBox.Text) or 0,
		})
	end)
	heading("Live codes", list, 40)
	local codesFrame = UIKit.create("Frame", { BackgroundTransparency = 1, LayoutOrder = 41, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, -8, 0, 0), Parent = list }, {
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	}) :: Frame

	renderLists = function(result: Types.AdminResult)
		local lines: { string } = {}
		for _, grant in result.grants or {} do
			table.insert(lines, `{grant.name}: {table.concat(grant.passes, ", ")}`)
		end
		grantsLabel.Text = if #lines > 0 then "Players with free passes:\n" .. table.concat(lines, "\n") else "Nobody has free passes from this panel yet."
		for _, child in codesFrame:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local now = os.time()
		for index, code in result.codes or {} do
			local row = UIKit.create("Frame", { BackgroundColor3 = Theme.PanelLight, BorderSizePixel = 0, LayoutOrder = index, Size = UDim2.new(1, 0, 0, 50), Parent = codesFrame }, { UIKit.corner(6) }) :: Frame
			local parts: { string } = {}
			for _, field in PromoConfig.REWARD_ORDER do
				if code.rewards[field] ~= nil then
					table.insert(parts, `{code.rewards[field]} {PromoConfig.REWARDS[field].name}`)
				end
			end
			local daysLeft = math.floor((code.expiresAt - now) / 86400 * 10) / 10
			local uses = if code.maxUses > 0 then `{code.uses}/{code.maxUses} used` else `{code.uses} used`
			UIKit.label({ Text = code.code, Font = Theme.FontBold, TextSize = 14, Position = UDim2.new(0, 8, 0, 3), Size = UDim2.new(1, -90, 0, 18), Parent = row })
			UIKit.label({
				Text = `{table.concat(parts, ", ")} | {uses} | {if daysLeft > 0 then `{daysLeft} days left` else "EXPIRED"}`,
				TextSize = 11,
				TextColor3 = Theme.Muted,
				TextWrapped = true,
				Position = UDim2.new(0, 8, 0, 21),
				Size = UDim2.new(1, -90, 0, 26),
				Parent = row,
			})
			local delete = UIKit.button({ Text = "Delete", TextSize = 12, BackgroundColor3 = Theme.HpFill, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(70, 30), Parent = row })
			delete.Activated:Connect(function()
				send("DeleteCode", { code = code.code })
			end)
		end
	end

	toggle.Activated:Connect(function()
		window.Visible = not window.Visible
		if window.Visible then
			send("List", {})
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

return AdminUI
