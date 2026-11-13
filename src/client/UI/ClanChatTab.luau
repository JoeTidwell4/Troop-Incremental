--!strict
-- Clan window tab: clan chat. Messages are filtered by Roblox on the server before they
-- get here. Tap "mute" on a message to hide that player for this session; players you've
-- blocked on Roblox are hidden automatically.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local ClanConfig = require(Shared:WaitForChild("Config"):WaitForChild("ClanConfig"))
local UIKit = require(script.Parent.UIKit)
local ClanTypes = require(script.Parent.ClanTypes)
local ClanController = require(Client.Controllers.ClanController)

type ClanView = Types.ClanView

local Theme = UIKit.Theme

local ClanChatTab = {}

function ClanChatTab.build(parent: Instance, _context: ClanTypes.Context): ClanTypes.Tab
	local muted: { [number]: boolean } = {}
	-- Roblox blocks (best effort: the core GUI may not be ready yet).
	task.spawn(function()
		for _ = 1, 10 do
			local ok, ids = pcall(function(): any
				return StarterGui:GetCore("GetBlockedUserIds")
			end)
			if ok and typeof(ids) == "table" then
				for _, id in ids do
					muted[id] = true
				end
				return
			end
			task.wait(1)
		end
	end)

	local frame = UIKit.create("Frame", {
		Name = "Chat",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = parent,
	}) :: Frame
	local list = UIKit.create("ScrollingFrame", {
		BackgroundColor3 = Theme.PanelLight,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -44),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = frame,
	}, {
		UIKit.corner(8),
		UIKit.padding(6),
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	}) :: ScrollingFrame
	local input = UIKit.create("TextBox", {
		Text = "",
		PlaceholderText = "Say something to your clan...",
		ClearTextOnFocus = false,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.Muted,
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Font = Theme.Font,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, -86, 0, 38),
		Parent = frame,
	}, { UIKit.corner(6), UIKit.padding(6) }) :: TextBox
	local sendButton = UIKit.button({
		Text = "Send",
		TextSize = 14,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(0, 80, 0, 38),
		Parent = frame,
	})

	local rows: { Instance } = {}
	local me = Players.LocalPlayer.UserId
	local dirty = true -- rebuild on the next render (new messages arrived while hidden)

	local function redraw()
		dirty = false
		for _, row in rows do
			row:Destroy()
		end
		rows = {}
		for order, message in ClanController.getChat() do
			if muted[message.userId] then
				continue
			end
			local row = UIKit.create("Frame", {
				LayoutOrder = order,
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, -8, 0, 18),
				Parent = list,
			}) :: Frame
			table.insert(rows, row)
			local system = message.userId == 0
			local nameColor = if message.userId == me then Theme.Gold else Color3.fromRGB(140, 190, 255)
			UIKit.label({
				Text = if system then message.text else `<font color="#{nameColor:ToHex()}"><b>{message.name}:</b></font> {message.text}`,
				RichText = not system,
				TextColor3 = if system then Theme.Muted else Theme.Text,
				TextSize = 13,
				TextWrapped = true,
				TextTruncate = Enum.TextTruncate.None,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, -48, 0, 16),
				Parent = row,
			})
			if not system and message.userId ~= me then
				local mute = UIKit.button({
					Text = "mute",
					TextSize = 10,
					BackgroundColor3 = Theme.Panel,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 0, 0, 0),
					Size = UDim2.new(0, 44, 0, 16),
					Parent = row,
				})
				mute.Activated:Connect(function()
					muted[message.userId] = true
					redraw()
				end)
			end
		end
		task.defer(function()
			list.CanvasPosition = Vector2.new(0, math.max(0, list.AbsoluteCanvasSize.Y - list.AbsoluteWindowSize.Y))
		end)
	end

	local function send()
		local text = string.sub(input.Text, 1, ClanConfig.CHAT_MAX_LENGTH)
		if #text > 0 then
			ClanController.sendChat(text)
			input.Text = ""
		end
	end
	sendButton.Activated:Connect(send)
	input.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			send()
		end
	end)
	ClanController.ChatChanged:Connect(function()
		if frame.Visible then
			redraw()
		else
			dirty = true
		end
	end)

	-- ClanUI calls this several times a second while the tab is open, so only rebuild
	-- the list when something changed.
	local function render(_view: ClanView, _snapshot: Types.Snapshot?)
		if dirty then
			redraw()
		end
	end

	return { title = "Chat", frame = frame, render = render }
end

return ClanChatTab
