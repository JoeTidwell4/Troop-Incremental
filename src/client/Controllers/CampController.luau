--!strict
-- The camp (CampConfig): menus as structures standing around the battlefield.
--
--   * Each sign is a part-built model (Visuals/CampProps) at the player's plot, turned to
--     face the camera, with a floating name label and a "!" when its window has something
--     waiting (window modules call CampController.setBadge).
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
--   * The sign's button holds its Spotlight key ("Menu:<Name>"), so tutorials and tips
--     point at the sign.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Plots = require(Shared:WaitForChild("Plots"))
local CampConfig = require(Shared:WaitForChild("Config"):WaitForChild("CampConfig"))
local VisualConfig = require(Shared:WaitForChild("Config"):WaitForChild("VisualConfig"))
local CampProps = require(Client:WaitForChild("Visuals"):WaitForChild("CampProps"))
local Quality = require(Client:WaitForChild("Visuals"):WaitForChild("Quality"))
local Cinematic = require(script.Parent.Cinematic)
local Spotlight = require(Client.UI.Spotlight)
local Layout = require(Client.UI.Layout)
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
	bounceAt: number,
	hidden: boolean, -- model parts made invisible (hiddenInClan / onlyWhenMerchant)
	absent: boolean, -- onlyWhenMerchant and he's not here: no label, no click
	culled: boolean, -- name label hidden because it would cover the HUD or another label
	labelWidth: number, -- name label width in pixels
}

local BOUNCE_SECONDS = 0.35
-- Name labels: smaller on phones (billboards don't follow the screen UIScale).
local LABEL_TEXT = if Layout.compact then 13 else 18
local LABEL_HEIGHT = if Layout.compact then 21 else 28
local CULL_INTERVAL = 0.2
-- ScreenGuis that never hide a label (the sign hitboxes themselves, flashes, coins).
local CULL_IGNORE: { [string]: boolean } = { CampSigns = true, Juice = true }

local CampController = {}

local signs: { Sign } = {}
local badges: { [string]: boolean } = {} -- "!" per sign key (setBadge)
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

-- Where a sign's name label is on screen (GUI coordinates, below the top bar), shown or not.
local function rectOf(sign: Sign, camera: Camera, inset: Vector2): (Vector2?, Vector2?)
	local anchor = (sign.label.Parent :: BillboardGui).Parent :: BasePart
	local point, inFront = camera:WorldToViewportPoint(anchor.Position)
	if not inFront then
		return nil, nil
	end
	-- The billboard is centred on the anchor; the label sits at its bottom.
	local x, y = point.X - inset.X, point.Y - inset.Y
	local half = sign.labelWidth / 2
	return Vector2.new(x - half, y + 26 - LABEL_HEIGHT), Vector2.new(x + half, y + 26)
end

-- Screen rectangle of a sign's name label while it's shown.
local function labelRect(sign: Sign, camera: Camera, inset: Vector2): (Vector2?, Vector2?)
	local billboard = sign.label.Parent :: BillboardGui
	if not billboard.Enabled then
		return nil, nil
	end
	return rectOf(sign, camera, inset)
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
		-- A soft warm lamp over each structure (High graphics), so the camp reads at night.
		if Quality.get().shadows then
			local lamp = Instance.new("PointLight")
			lamp.Color = Color3.fromRGB(255, 200, 140)
			lamp.Brightness = 0.7
			lamp.Range = 11
			lamp.Parent = anchor
		end
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
		label.Size = UDim2.fromOffset(0, LABEL_HEIGHT)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Font = Enum.Font.FredokaOne
		label.TextSize = LABEL_TEXT
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
			bounceAt = -math.huge,
			hidden = false,
			culled = false,
			labelWidth = TextService:GetTextSize(def.label, LABEL_TEXT, Enum.Font.FredokaOne, Vector2.new(1000, 100)).X + 20,
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
		Spotlight.register(def.menu, hitbox)
		table.insert(signs, sign)
	end
end

-- Is any solid piece of HUD / window at this GUI point?
local function hudAt(playerGui: PlayerGui, point: Vector2, screenArea: number): boolean
	for _, object in playerGui:GetGuiObjectsAtPosition(point.X, point.Y) do
		local gui = object:FindFirstAncestorWhichIsA("ScreenGui")
		if gui == nil or CULL_IGNORE[gui.Name] then
			continue
		end
		local size = object.AbsoluteSize
		if size.X * size.Y > screenArea * 0.4 then
			continue -- full-screen layers (they're see-through)
		end
		if object.BackgroundTransparency < 0.8 then
			return true
		end
		if object:IsA("TextLabel") and object.Text ~= "" and object.TextTransparency < 0.5 then
			return true
		end
	end
	return false
end

-- Hides name labels that would sit on the HUD or on another label (phones especially:
-- the camp shrinks with the screen, the labels don't). "!" signs go first, then nearer.
local lastCull = 0
local function cullLabels(camera: Camera, inset: Vector2)
	local now = os.clock()
	if now - lastCull < CULL_INTERVAL then
		return
	end
	lastCull = now
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	local order: { Sign } = {}
	for _, sign in signs do
		if not sign.absent then
			table.insert(order, sign)
		end
	end
	local from = camera.CFrame.Position
	table.sort(order, function(a: Sign, b: Sign): boolean
		local badgeA, badgeB = badges[a.def.key] == true, badges[b.def.key] == true
		if badgeA ~= badgeB then
			return badgeA
		end
		return (a.home.Position - from).Magnitude < (b.home.Position - from).Magnitude
	end)
	local viewport = camera.ViewportSize
	local screenArea = viewport.X * viewport.Y
	local placed: { { Vector2 } } = {}
	for _, sign in order do
		local low, high = rectOf(sign, camera, inset)
		local culled = low == nil
		if low ~= nil and high ~= nil then
			for _, other in placed do
				if low.X < other[2].X + 4 and high.X > other[1].X - 4 and low.Y < other[2].Y + 2 and high.Y > other[1].Y - 2 then
					culled = true
					break
				end
			end
			if not culled then
				local middle = (low + high) / 2
				for _, point in { middle, Vector2.new(low.X + 4, middle.Y), Vector2.new(high.X - 4, middle.Y), Vector2.new(middle.X, low.Y + 3), Vector2.new(middle.X, high.Y - 3) } do
					if hudAt(playerGui, point, screenArea) then
						culled = true
						break
					end
				end
			end
			if not culled then
				table.insert(placed, { low, high })
			end
		end
		sign.culled = culled
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
	local away = BattlefieldController.cameraFocus() > 0.01 or busy or Cinematic.active
	if not away then
		cullLabels(camera, inset)
	end
	local now = os.clock()
	local clan = ClanController.get()
	local inClan = clan ~= nil and clan.inClan
	local snapshot = StateController.get()
	local merchantHere = snapshot ~= nil and snapshot.merchant.leaveAt > workspace:GetServerTimeNow()
	-- "!" over the Story stand while the final battle is waiting.
	badges.Story = snapshot ~= nil and snapshot.storyCleared ~= nil and snapshot.storyCleared["10"] == true and not snapshot.storyFinalWon
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
		-- No floating name labels in the middle of a story cutscene.
		(sign.label.Parent :: BillboardGui).Enabled = not Cinematic.active and not sign.culled
		-- Bounce: a quick hop and squash when clicked.
		local t = (now - sign.bounceAt) / BOUNCE_SECONDS
		if t >= 0 and t <= 1 then
			sign.model:PivotTo(sign.home * CFrame.new(0, math.sin(t * math.pi) * 0.8, 0))
		elseif t > 1 and t < 1.2 then
			sign.model:PivotTo(sign.home)
		end

		sign.badge.Visible = badges[sign.def.key] == true
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
