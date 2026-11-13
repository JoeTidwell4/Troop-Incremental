--!strict
-- Big center-screen banners: boss won/lost, new area, ability unlocked.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Areas = require(Shared:WaitForChild("Areas"))
local AbilityConfig = require(Shared:WaitForChild("Config"):WaitForChild("AbilityConfig"))
local UIKit = require(script.Parent.UIKit)
local AudioController = require(Client.Controllers.AudioController)
local StateController = require(Client.Controllers.StateController)

type Snapshot = Types.Snapshot
type Notice = Types.Notice

local Theme = UIKit.Theme
local SHOW_SECONDS = 3.5

local frame: Frame
local titleLabel: TextLabel
local subtitleLabel: TextLabel
local showToken = 0

local NoticeUI = {}

local FAIL_REASONS: { [string]: string } = {
	OutOfTime = "Out of time!",
	ArmyDefeated = "Your army was defeated!",
}
-- What to do about it (each reason has a different fix).
local FAIL_ADVICE: { [string]: string } = {
	OutOfTime = "Not enough damage: buy troops, upgrade Weapons, use Rally in the fight.",
	ArmyDefeated = "Not enough HP: buy Knights or upgrade Armor, then Fight Boss again.",
}

function NoticeUI.show(title: string, subtitle: string, color: Color3)
	showToken += 1
	local token = showToken

	titleLabel.Text = title
	titleLabel.TextColor3 = color
	subtitleLabel.Text = subtitle
	frame.Visible = true
	frame.BackgroundTransparency = 1
	titleLabel.TextTransparency = 1
	subtitleLabel.TextTransparency = 1

	local fadeIn = TweenInfo.new(0.25)
	TweenService:Create(frame, fadeIn, { BackgroundTransparency = 0.2 }):Play()
	TweenService:Create(titleLabel, fadeIn, { TextTransparency = 0 }):Play()
	TweenService:Create(subtitleLabel, fadeIn, { TextTransparency = 0 }):Play()

	task.delay(SHOW_SECONDS, function()
		if showToken ~= token then
			return -- a newer banner replaced this one
		end
		local fadeOut = TweenInfo.new(0.4)
		TweenService:Create(frame, fadeOut, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(titleLabel, fadeOut, { TextTransparency = 1 }):Play()
		local last = TweenService:Create(subtitleLabel, fadeOut, { TextTransparency = 1 })
		last.Completed:Connect(function()
			if showToken == token then
				frame.Visible = false
			end
		end)
		last:Play()
	end)
end

local function onNotice(notice: Notice)
	if notice.kind == "BossDefeated" then
		local nextArea = Areas.forStage(notice.stage + 1)
		local bonus = if notice.firstClear then "  (+1 free gear pack!)" else ""
		NoticeUI.show("BOSS DEFEATED!", `Entering Area {nextArea.number}: {nextArea.displayName}{bonus}`, Theme.Gold)
	elseif notice.kind == "Purchase" then
		AudioController.play("Purchase")
		NoticeUI.show("THANK YOU!", `{notice.itemName or "Your purchase"} is yours. Enjoy!`, Color3.fromRGB(0, 176, 111))
	elseif notice.kind == "RaidResult" then
		NoticeUI.show("RAID ATTACK DONE", `+{notice.units or 0} raid units for your clan!`, Color3.fromRGB(230, 120, 40))
	elseif notice.kind == "RaidRewards" then
		local packs = notice.packs or 0
		NoticeUI.show(
			`RAID REWARDS: TIER {notice.tier or 0}`,
			`+{notice.honor or 0} Honor, +{packs} free gear pack{if packs == 1 then "" else "s"}`,
			Theme.Gold
		)
	elseif notice.kind == "ClanJoined" then
		NoticeUI.show(`WELCOME TO {string.upper(notice.itemName or "YOUR CLAN")}`, "Your join request was accepted.", Theme.Gold)
	elseif notice.kind == "CommanderItem" then
		NoticeUI.show(`NEW GEAR: {notice.itemName or "?"}`, "Put it on in the WARDROBE for a bonus.", Theme.Gold)
	elseif notice.kind == "ClanWarRewards" then
		local parts: { string } = {}
		if (notice.honor or 0) > 0 then
			table.insert(parts, `+{notice.honor} Honor`)
		end
		if (notice.heroChests or 0) > 0 then
			table.insert(parts, `+{notice.heroChests} Hero Chest{if notice.heroChests == 1 then "" else "s"}`)
		end
		if (notice.packs or 0) > 0 then
			table.insert(parts, `+{notice.packs} free pack{if notice.packs == 1 then "" else "s"}`)
		end
		local title = if notice.rank ~= nil then `CLAN WAR: YOUR CLAN PLACED #{notice.rank}!` else "CLAN WAR REWARDS"
		if notice.mvp then
			table.insert(parts, 1, "You were the clan MVP!")
		end
		NoticeUI.show(title, table.concat(parts, ", "), Theme.Gold)
	elseif notice.kind == "BossFailed" then
		local reason = FAIL_REASONS[notice.reason or ""] or "Boss fight lost."
		NoticeUI.show(reason, FAIL_ADVICE[notice.reason or ""] or FAIL_ADVICE.OutOfTime, Theme.HpFill)
	end
end

-- Ability unlocks are detected locally from the all-time best stage going up.
-- (OfflineEarnings notices are shown by OfflineEarningsUI instead.)
local function onStateChanged(snapshot: Snapshot, previous: Snapshot?)
	if previous == nil then
		return
	end
	for _, abilityId in AbilityConfig.ORDER do
		local def = AbilityConfig.ABILITIES[abilityId]
		if previous.bestStage < def.unlockStage and snapshot.bestStage >= def.unlockStage then
			NoticeUI.show(`New ability: {def.displayName}!`, def.description, Theme.Accent)
		end
	end
end

function NoticeUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = UIKit.create("ScreenGui", {
		Name = "Notices",
		ResetOnSpawn = false,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	frame = UIKit.create("Frame", {
		Name = "Banner",
		Visible = false,
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.38, 0),
		Size = UDim2.new(0, 460, 0, 84),
		Parent = gui,
	}, { UIKit.corner(12) }) :: Frame

	titleLabel = UIKit.label({
		Text = "",
		Font = Theme.FontBold,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 10, 0, 8),
		Size = UDim2.new(1, -20, 0, 38),
		Parent = frame,
	})
	subtitleLabel = UIKit.label({
		Text = "",
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 10, 0, 48),
		Size = UDim2.new(1, -20, 0, 24),
		Parent = frame,
	})

	StateController.Notice:Connect(onNotice)
	StateController.Changed:Connect(onStateChanged)

	gui.Parent = playerGui
end

return NoticeUI
