--!strict
-- The camp (CampConfig): menus as structures standing around the battlefield.
--
--   * Each sign is a part-built model (Visuals/CampProps) at the player's plot, turned to
--     face the camera, with a floating name label and a "!" when its window has something
--     waiting (the old menu button's red "Dot").
--   * Clicking: every sign has an invisible on-screen button that follows the model's
--     outline every frame. Because it's a real GUI button, a click on a sign never
--     counts as an attack (InputController ignores clicks that hit UI) and taps on
--     phones just work. Those boxes are rectangles and can overlap, so they only catch
--     the click: `pickAt` then decides which sign it was (its name label, else the
--     exact model under the pointer by raycast, else the nearest box). Hover (PC)
--     highlights the sign `pickAt` finds.
--   * A click bounces the sign, glides the camera to it (BattlefieldController.focusCamera),
--     then opens the window (Spotlight.open). When the window closes, the camera glides
--     back.
--   * The old menu button is hidden, and the sign's button takes over its Spotlight key,
--     so tutorials and tips point at the sign.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Plots = require(Shared:WaitForChild("Plots"))
local CampConfig = require(Shared:WaitForChild("Config"):WaitForChild("CampConfig"))
local VisualConfig = require(Shared:WaitForChild("Config"):WaitForChild("VisualConfig"))
local CampProps = require(Client:WaitForChild("Visuals"):WaitForChild("CampProps"))
local Spotlight = require(Client.UI.Spotlight)
local BattlefieldController = require(script.Parent.BattlefieldController)
local AudioController = require(script.Parent.AudioController)
local ClanController = require(script.Parent.ClanController)
local StateController = require(script.Parent.StateController)

type SignDef = typeof(CampConfig.SIGNS[1])
type Sign = {
	def: SignDef,
	model: Model,
	home: CFrame, -- the model's pivot when standing still
	height: number,
	focus: CFrame, -- where the camera goes
	hitbox: TextButton,
	label: TextLabel,
	badge: TextLabel,
	highlight: Highlight,
	oldButton: GuiObject?,
	bounceAt: number,
	hidden: boolean, -- model parts made invisible (hiddenInClan / onlyWhenMerchant)
	absent: boolean, -- onlyWhenMerchant and he's not here: no label, no click
}

local BOUNCE_SECONDS = 0.35

local CampController = {}

local signs: { Sign } = {}
local badges: { [string]: boolean } = {} -- "!" for signs without an old menu button
local busy = false -- a glide / window is in progress
local hovered: { [TextButton]: boolean } = {} -- hitboxes under the mouse (they respect UI on top)
local highlighted: Sign? = nil
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include

local function windowOpen(def: SignDef): boolean
	local gui = Players.LocalPlayer.PlayerGui:FindFirstChild(def.gui)
	local overlay = if gui ~= nil then gui:FindFirstChild("Overlay") else nil
	return overlay ~= nil and (overlay :: GuiObject).Visible
end

-- Fly to the sign, open its window, fly back when it closes.
local function visit(sign: Sign)
	if busy then
		return
	end
	busy = true
	sign.bounceAt = os.clock()
	AudioController.play("UIClick")
	BattlefieldController.focusCamera(sign.focus, CampConfig.FOCUS_SECONDS)
	task.delay(CampConfig.FOCUS_SECONDS, function()
		Spotlight.open(sign.def.menu)
		-- Wait until the window has opened and closed again (or never opened).
		local opened = false
		local started = os.clock()
		while true do
			task.wait(0.05)
			local open = windowOpen(sign.def)
			if open then
				opened = true
			elseif opened or os.clock() - started > 0.6 then
				break
			end
		end
		BattlefieldController.focusCamera(nil, CampConfig.FOCUS_SECONDS)
		task.wait(CampConfig.FOCUS_SECONDS)
		busy = false
	end)
end

-- Screen rectangle (GUI coordinates, below the top bar) of a sign's name label.
local function labelRect(sign: Sign, camera: Camera, inset: Vector2): (Vector2?, Vector2?)
	local billboard = sign.label.Parent :: BillboardGui
	local anchor = billboard.Parent :: BasePart
	if not billboard.Enabled then
		return nil, nil
	end
	local point, inFront = camera:WorldToViewportPoint(anchor.Position)
	if not inFront then
		return nil, nil
	end
	-- The billboard is centred on the anchor; the label sits at its bottom (28 px of 52).
	local x, y = point.X - inset.X, point.Y - inset.Y
	local half = sign.label.AbsoluteSize.X / 2
	return Vector2.new(x - half, y - 2), Vector2.new(x + half, y + 26)
end

local function clickable(sign: Sign): boolean
	return not sign.absent and sign.hitbox.Visible
end

-- Which sign is at `position` (GUI coordinates)? Name labels first (they're drawn on
-- top), then the model actually under the pointer, then the nearest hitbox around it.
local function pickAt(position: Vector2): Sign?
	local camera = workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local inset = GuiService:GetGuiInset()
	local best: Sign? = nil
	local bestDepth = math.huge
	for _, sign in signs do
		if clickable(sign) then
			local low, high = labelRect(sign, camera, inset)
			if low ~= nil and high ~= nil and position.X >= low.X and position.X <= high.X and position.Y >= low.Y and position.Y <= high.Y then
				local depth = (camera.CFrame.Position - sign.home.Position).Magnitude
				if depth < bestDepth then
					best, bestDepth = sign, depth
				end
			end
		end
	end
	if best ~= nil then
		return best
	end
	local ray = camera:ScreenPointToRay(position.X, position.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * 600, raycastParams)
	if result ~= nil then
		for _, sign in signs do
			if clickable(sign) and result.Instance:IsDescendantOf(sign.model) then
				return sign
			end
		end
	end
	local bestDistance = math.huge
	for _, sign in signs do
		if clickable(sign) then
			local low = sign.hitbox.AbsolutePosition
			local size = sign.hitbox.AbsoluteSize
			if position.X >= low.X and position.X <= low.X + size.X and position.Y >= low.Y and position.Y <= low.Y + size.Y then
				local distance = (low + size / 2 - position).Magnitude
				if distance < bestDistance then
					best, bestDistance = sign, distance
				end
			end
		end
	end
	return best
end

local function setHighlighted(sign: Sign?)
	if highlighted == sign then
		return
	end
	local old = highlighted
	if old ~= nil then
		old.highlight.FillTransparency = 1
		old.highlight.OutlineTransparency = 1
		old.label.TextColor3 = CampConfig.LABEL_COLOR
	end
	highlighted = sign
	if sign ~= nil then
		sign.highlight.FillTransparency = 0.8
		sign.highlight.OutlineTransparency = 0
		sign.label.TextColor3 = Color3.new(1, 1, 1)
	end
end

local function build(origin: Vector3, folder: Folder, hitboxGui: ScreenGui)
	local cameraPosition = origin + VisualConfig.CAMERA_OFFSET
	for _, def in CampConfig.SIGNS do
		local feet = origin + def.offset
		-- Face the camera (turning only around the vertical axis).
		local facing = Vector3.new(cameraPosition.X, feet.Y, cameraPosition.Z)
		local at = CFrame.lookAt(feet, facing)
		local model, height = CampProps.build(def.kind, def.color, at, folder)
		model.WorldPivot = at

		-- Camera stop: in front of the sign, a little above, looking at its middle.
		local middle = feet + Vector3.new(0, height * 0.5, 0)
		local toward = (facing - feet).Unit
		local focus = CFrame.lookAt(middle + toward * CampConfig.FOCUS_DISTANCE + Vector3.new(0, CampConfig.FOCUS_HEIGHT, 0), middle)

		-- Floating name + "!" badge.
		local anchor = Instance.new("Part")
		anchor.Name = "LabelAnchor"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.CFrame = CFrame.new(feet + Vector3.new(0, height + 1.4, 0))
		anchor.Parent = model
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(170, 52)
		billboard.LightInfluence = 0
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 400
		billboard.Parent = anchor
		local label = Instance.new("TextLabel")
		label.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
		label.BackgroundTransparency = 0.25
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, 0)
		label.Size = UDim2.fromOffset(0, 28)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Font = Enum.Font.FredokaOne
		label.TextSize = 18
		label.TextColor3 = CampConfig.LABEL_COLOR
		label.TextStrokeTransparency = 0.5
		label.Text = def.label
		label.Parent = billboard
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 10)
		padding.PaddingRight = UDim.new(0, 10)
		padding.Parent = label
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = label
		local stroke = Instance.new("UIStroke")
		stroke.Color = def.color
		stroke.Thickness = 2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = label
		local badge = Instance.new("TextLabel")
		badge.BackgroundColor3 = Color3.fromRGB(230, 60, 60)
		badge.AnchorPoint = Vector2.new(0.5, 1)
		badge.Position = UDim2.new(0.5, 0, 0, 22)
		badge.Size = UDim2.fromOffset(22, 22)
		badge.Font = Enum.Font.FredokaOne
		badge.TextSize = 18
		badge.TextColor3 = Color3.new(1, 1, 1)
		badge.Text = "!"
		badge.Visible = false
		badge.Parent = billboard
		local badgeCorner = Instance.new("UICorner")
		badgeCorner.CornerRadius = UDim.new(1, 0)
		badgeCorner.Parent = badge

		local highlight = Instance.new("Highlight")
		highlight.FillColor = CampConfig.LABEL_COLOR
		highlight.FillTransparency = 1
		highlight.OutlineColor = CampConfig.LABEL_COLOR
		highlight.OutlineTransparency = 1
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Adornee = model
		highlight.Parent = model

		-- Invisible click target that follows the sign on screen.
		local hitbox = Instance.new("TextButton")
		hitbox.Name = def.key
		hitbox.BackgroundTransparency = 1
		hitbox.Text = ""
		hitbox.AutoButtonColor = false
		hitbox.Visible = false
		hitbox.Parent = hitboxGui

		local sign: Sign = {
			def = def,
			model = model,
			home = at,
			height = height,
			focus = focus,
			hitbox = hitbox,
			label = label,
			badge = badge,
			highlight = highlight,
			oldButton = Spotlight.get(def.menu),
			bounceAt = -math.huge,
			hidden = false,
			absent = false,
		}
		hitbox.MouseEnter:Connect(function()
			hovered[hitbox] = true
		end)
		hitbox.MouseLeave:Connect(function()
			hovered[hitbox] = nil
		end)
		hitbox.Activated:Connect(function(input: InputObject)
			local picked = pickAt(Vector2.new(input.Position.X, input.Position.Y)) or sign
			visit(picked)
		end)
		-- The models can be clicked exactly (raycast in pickAt).
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Name ~= "LabelAnchor" then
				part.CanQuery = true
			end
		end
		-- The sign takes over the old button's spot in tutorials and tips.
		if sign.oldButton ~= nil then
			(sign.oldButton :: GuiObject).Visible = false
		end
		Spotlight.register(def.menu, hitbox)
		table.insert(signs, sign)
	end
end

local function setHidden(sign: Sign, hidden: boolean)
	if sign.hidden == hidden then
		return
	end
	sign.hidden = hidden
	for _, part in sign.model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "LabelAnchor" then
			part.LocalTransparencyModifier = if hidden then 1 else 0
			-- A stand hidden for your real clan banner still takes clicks; an absent
			-- merchant doesn't.
			part.CanQuery = not (hidden and sign.def.onlyWhenMerchant == true)
		end
		if part:IsA("Light") then
			part.Enabled = not hidden
		end
	end
	sign.highlight.Enabled = not hidden
end

-- Keeps every hitbox over its sign's outline on screen, the "!" badges, and the bounce.
local function update()
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local inset = GuiService:GetGuiInset()
	local away = BattlefieldController.cameraFocus() > 0.01 or busy
	local now = os.clock()
	local clan = ClanController.get()
	local inClan = clan ~= nil and clan.inClan
	local snapshot = StateController.get()
	local merchantHere = snapshot ~= nil and snapshot.merchant.leaveAt > workspace:GetServerTimeNow()
	for _, sign in signs do
		if sign.def.hiddenInClan then
			setHidden(sign, inClan)
		end
		if sign.def.onlyWhenMerchant then
			sign.absent = not merchantHere
			setHidden(sign, sign.absent)
			local billboard = sign.label.Parent :: BillboardGui
			billboard.Enabled = not sign.absent
			if sign.absent then
				sign.hitbox.Visible = false
				continue
			end
		end
		-- Bounce: a quick hop and squash when clicked.
		local t = (now - sign.bounceAt) / BOUNCE_SECONDS
		if t >= 0 and t <= 1 then
			sign.model:PivotTo(sign.home * CFrame.new(0, math.sin(t * math.pi) * 0.8, 0))
		elseif t > 1 and t < 1.2 then
			sign.model:PivotTo(sign.home)
		end

		local dot = if sign.oldButton ~= nil then (sign.oldButton :: GuiObject):FindFirstChild("Dot") else nil
		sign.badge.Visible = (dot ~= nil and (dot :: GuiObject).Visible) or badges[sign.def.key] == true
		if sign.badge.Visible then
			sign.badge.Position = UDim2.new(0.5, 0, 0, 22 - math.abs(math.sin(now * 3)) * 4)
		end

		if away then
			sign.hitbox.Visible = false
			continue
		end
		local boxCFrame, size = sign.model:GetBoundingBox()
		local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
		local visible = true
		for _, x in { -0.5, 0.5 } do
			for _, y in { -0.5, 0.5 } do
				for _, z in { -0.5, 0.5 } do
					local corner = boxCFrame * Vector3.new(size.X * x, size.Y * y, size.Z * z)
					local point, inFront = camera:WorldToViewportPoint(corner)
					if not inFront then
						visible = false
					end
					minX, maxX = math.min(minX, point.X), math.max(maxX, point.X)
					minY, maxY = math.min(minY, point.Y), math.max(maxY, point.Y)
				end
			end
		end
		sign.hitbox.Visible = visible
		if visible then
			-- (viewport points include the top bar; this ScreenGui starts below it)
			sign.hitbox.Position = UDim2.fromOffset(minX - inset.X, minY - inset.Y - 30) -- + the label above
			sign.hitbox.Size = UDim2.fromOffset(maxX - minX, maxY - minY + 30)
			-- Nearer signs on top (the click is re-picked anyway, see pickAt).
			sign.hitbox.ZIndex = math.clamp(1000 - math.floor((camera.CFrame.Position - sign.home.Position).Magnitude), 1, 1000)
		end
	end

	-- Hover: highlight the sign actually under the mouse.
	local over = false
	for hitbox in hovered do
		if hitbox.Visible then
			over = true
		else
			hovered[hitbox] = nil
		end
	end
	if over and not away then
		local mouse = UserInputService:GetMouseLocation() - inset
		setHighlighted(pickAt(mouse))
	else
		setHighlighted(nil)
	end
end

-- For the MENU fallback (UI/MenuUI): every sign's key, label and whether it has a "!".
function CampController.list(): { { key: string, label: string, badge: boolean } }
	local result = {}
	for _, sign in signs do
		if not sign.absent then
			table.insert(result, { key = sign.def.key, label = sign.def.label, badge = sign.badge.Visible })
		end
	end
	return result
end

-- Shows a "!" over a sign that has no old menu button (Fortune Wheel, Merchant).
function CampController.setBadge(key: string, on: boolean)
	badges[key] = on
end

-- Visit a sign by key (camera glide + window), as if it was clicked.
function CampController.visitKey(key: string)
	for _, sign in signs do
		if sign.def.key == key then
			visit(sign)
		end
	end
end

function CampController.start()
	local player = Players.LocalPlayer
	local hitboxGui = Instance.new("ScreenGui")
	hitboxGui.Name = "CampSigns"
	hitboxGui.ResetOnSpawn = false
	hitboxGui.DisplayOrder = 1 -- under the HUD, shop and windows: they win where they overlap
	hitboxGui.Parent = player:WaitForChild("PlayerGui")

	task.spawn(function()
		local index = player:GetAttribute(Plots.ATTRIBUTE)
		while typeof(index) ~= "number" do
			player:GetAttributeChangedSignal(Plots.ATTRIBUTE):Wait()
			index = player:GetAttribute(Plots.ATTRIBUTE)
		end
		local folder = Instance.new("Folder")
		folder.Name = "Camp"
		folder.Parent = workspace
		build(Plots.origin(index :: number), folder, hitboxGui)
		raycastParams.FilterDescendantsInstances = { folder }
		RunService.RenderStepped:Connect(update)
	end)
end

return CampController
