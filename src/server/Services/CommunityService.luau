--!strict
-- The game's Roblox group (CommunityConfig): members get the group cosmetic.
-- Membership is checked when the profile loads and when the client says the join prompt
-- closed (remote `CommunityCheck`, rate-limited; the server checks for itself, it never
-- takes the client's word). In Studio it also prints whether GROUP_ID is a real group.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GroupService = game:GetService("GroupService")
local RunService = game:GetService("RunService")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local CommunityConfig = require(Shared:WaitForChild("Config"):WaitForChild("CommunityConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)
local CommanderService = require(Services.CommanderService)

type PlayerData = Types.PlayerData

local CommunityService = {}

local members: { [Player]: boolean } = {}

local function check(player: Player)
	local ok, isMember = pcall(function(): boolean
		return (player :: any):IsInGroupAsync(CommunityConfig.GROUP_ID)
	end)
	if not ok then
		-- Older engine builds only have the non-Async name.
		ok, isMember = pcall(function(): boolean
			return player:IsInGroup(CommunityConfig.GROUP_ID)
		end)
	end
	if not ok then
		return
	end
	members[player] = isMember == true
	if isMember then
		CommanderService.grant(player, CommunityConfig.MEMBER_ITEM)
	end
	DataService.markChanged(player)
end

function CommunityService.start()
	if RunService:IsStudio() then
		task.spawn(function()
			local ok, info = pcall(function(): any
				return GroupService:GetGroupInfoAsync(CommunityConfig.GROUP_ID)
			end)
			if ok and typeof(info) == "table" then
				print(`[Community] Group {CommunityConfig.GROUP_ID} found: "{info.Name}"`)
			else
				warn(`[Community] GROUP_ID {CommunityConfig.GROUP_ID} is not a group Roblox knows. Fix CommunityConfig.GROUP_ID (the number in the group page's address).`)
			end
		end)
	end
	DataService.ProfileLoaded:Connect(function(player: Player, _data: PlayerData)
		task.spawn(check, player)
	end)
	DataService.ProfileReleasing:Connect(function(player: Player)
		members[player] = nil
	end)
	SyncService.addSnapshotFields(function(player: Player, _data: PlayerData): { [string]: any }
		return { groupMember = members[player] == true }
	end)
	RemoteService.onEvent(
		Remotes.Events.CommunityCheck,
		RateLimiter.new(CommunityConfig.CHECK_REQUESTS_BURST, CommunityConfig.CHECK_REQUESTS_PER_SECOND),
		function(): boolean?
			return true
		end,
		function(player: Player, _payload: boolean)
			check(player)
		end
	)
end

return CommunityService
