--!strict
-- Clan window tab: member list with roles, donations, and management buttons.
-- Buttons only appear if your role allows them; the server checks again anyway.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local UIKit = require(script.Parent.UIKit)
local ClanTypes = require(script.Parent.ClanTypes)

type ClanView = Types.ClanView
type ClanMember = Types.ClanMember

local Theme = UIKit.Theme
local ROW_HEIGHT = 34
local RANK: { [string]: number } = { Leader = 3, Officer = 2, Member = 1 }
local ROLE_COLORS: { [string]: Color3 } = {
	Leader = Color3.fromRGB(255, 205, 70),
	Officer = Color3.fromRGB(120, 170, 255),
	Member = Color3.fromRGB(190, 190, 200),
}

local ClanMembersTab = {}

function ClanMembersTab.build(parent: Instance, context: ClanTypes.Context): ClanTypes.Tab
	local frame = UIKit.create("Frame", {
		Name = "Members",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = parent,
	}) :: Frame
	local list = UIKit.create("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = frame,
	}, {
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	}) :: ScrollingFrame

	local rows: { Frame } = {}
	local confirmKick: string? = nil -- user id waiting for a second click
	local lastBuilt = "" -- rebuild only when the clan or the confirm state changes

	local function act(action: string, userId: number)
		task.spawn(function()
			context.request(action, userId)
		end)
	end

	local function render(view: ClanView, _snapshot: Types.Snapshot?)
		local clan = view.clan
		if clan == nil then
			return
		end
		local buildKey = `{clan.id}:{clan.version}:{view.myRole}:{confirmKick or ""}`
		if buildKey == lastBuilt then
			return
		end
		lastBuilt = buildKey
		for _, row in rows do
			row:Destroy()
		end
		rows = {}
		local myRank = RANK[view.myRole or "Member"] or 1
		local me = tostring(Players.LocalPlayer.UserId)

		-- Sort: role, then most donated.
		local entries: { { key: string, member: ClanMember } } = {}
		for userKey, member in clan.members do
			table.insert(entries, { key = userKey, member = member })
		end
		table.sort(entries, function(a, b)
			local ra, rb = RANK[a.member.role] or 0, RANK[b.member.role] or 0
			if ra ~= rb then
				return ra > rb
			end
			return a.member.donated > b.member.donated
		end)

		for order, entry in entries do
			local member = entry.member
			local theirRank = RANK[member.role] or 0
			local isMe = entry.key == me
			local row = UIKit.create("Frame", {
				Name = entry.key,
				LayoutOrder = order,
				BackgroundColor3 = Theme.PanelLight,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -8, 0, ROW_HEIGHT),
				Parent = list,
			}, { UIKit.corner(6) }) :: Frame
			table.insert(rows, row)

			UIKit.label({
				Text = member.name .. (if isMe then "  (you)" else ""),
				Font = Theme.FontBold,
				TextSize = 13,
				Position = UDim2.new(0, 8, 0, 0),
				Size = UDim2.new(0.35, -8, 1, 0),
				Parent = row,
			})
			UIKit.label({
				Text = member.role,
				TextColor3 = ROLE_COLORS[member.role] or Theme.Text,
				TextSize = 12,
				Position = UDim2.new(0.35, 0, 0, 0),
				Size = UDim2.new(0.15, 0, 1, 0),
				Parent = row,
			})
			UIKit.label({
				Text = `Donated {NumberFormat.number(member.donated)}`,
				TextColor3 = Theme.Muted,
				TextSize = 12,
				Position = UDim2.new(0.5, 0, 0, 0),
				Size = UDim2.new(0.2, 0, 1, 0),
				Parent = row,
			})

			-- Buttons, right to left.
			local buttons: { { text: string, color: Color3, action: () -> () } } = {}
			if not isMe then
				local userId = tonumber(entry.key) or 0
				if myRank >= 2 and theirRank < myRank then
					local waiting = confirmKick == entry.key
					table.insert(buttons, {
						text = if waiting then "Sure?" else "Kick",
						color = Theme.HpFill,
						action = function()
							if confirmKick == entry.key then
								confirmKick = nil
								act("Kick", userId)
							else
								confirmKick = entry.key
								render(view, nil)
								task.delay(3, function()
									if confirmKick == entry.key then
										confirmKick = nil
										render(view, nil)
									end
								end)
							end
						end,
					})
				end
				if view.myRole == "Leader" and member.role == "Officer" then
					table.insert(buttons, {
						text = "Demote",
						color = Theme.PanelLight,
						action = function()
							act("Demote", userId)
						end,
					})
				end
				if view.myRole == "Leader" then
					table.insert(buttons, {
						text = if member.role == "Officer" then "Make leader" else "Promote",
						color = Theme.Accent,
						action = function()
							act("Promote", userId)
						end,
					})
				end
			end
			for index, info in buttons do
				local button = UIKit.button({
					Text = info.text,
					TextSize = 11,
					BackgroundColor3 = info.color,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -4 - (index - 1) * 76, 0.5, 0),
					Size = UDim2.new(0, 72, 1, -8),
					Parent = row,
				})
				button.Activated:Connect(info.action)
			end
		end
	end

	return { title = "Members", frame = frame, render = render }
end

return ClanMembersTab
