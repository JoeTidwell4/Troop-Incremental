--!strict
-- Clan chat across servers (Phase 11d H).
--
-- Safety rules (Roblox requires these for custom chat):
--   * Every message is filtered on the sender's server with Roblox's strictest filter
--     (GetNonChatStringForBroadcastAsync) BEFORE it is shown or sent anywhere; raw text
--     never leaves this server.
--   * Players who can't chat (privacy settings, parental controls, account limits:
--     TextChatService:CanUserChatAsync) can't send.
--   * A message only reaches members that Roblox lets the sender chat with
--     (TextChatService:CanUsersChatAsync), checked on the receiving server.
--   * Rate limited (CHAT_RATE_*), 150 characters max. Players can mute others on their
--     own screen, and Roblox blocks are hidden on the client.
-- Storage: the last CHAT_HISTORY messages per clan (1 day) in MemoryStore for when you
-- open the chat; new messages go to other servers through MessagingService (best effort).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ClanConfig = require(Shared:WaitForChild("Config"):WaitForChild("ClanConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)
local ClanStore = require(Services.ClanStore)

type Message = Types.ClanChatMessage

local IS_STUDIO = RunService:IsStudio()
local PERMISSION_SECONDS = 300 -- how long a chat-permission answer is reused

local seen: { [string]: number } = {} -- message id -> time, so a message isn't shown twice
local allowedCache: { [string]: { ok: boolean, at: number } } = {}
local knownClan: { [Player]: string } = {} -- the clan whose history this player was last sent

local ClanChatService = {}

-- Asks Roblox (cached). If the check itself fails, chat is refused, except in Studio
-- (where these checks may not be available).
local function cached(cacheKey: string, check: () -> boolean): boolean
	local entry = allowedCache[cacheKey]
	if entry ~= nil and os.clock() - entry.at < PERMISSION_SECONDS then
		return entry.ok
	end
	local ok, result = pcall(check)
	local allowed = if ok then result == true else IS_STUDIO
	allowedCache[cacheKey] = { ok = allowed, at = os.clock() }
	return allowed
end

local function canUserChat(userId: number): boolean
	return cached(`user:{userId}`, function(): boolean
		return TextChatService:CanUserChatAsync(userId)
	end)
end

local function canUsersChat(fromUserId: number, toUserId: number): boolean
	if fromUserId == toUserId then
		return true
	end
	return cached(`pair:{fromUserId}:{toUserId}`, function(): boolean
		return TextChatService:CanUsersChatAsync(fromUserId, toUserId)
	end)
end

-- Messages come back from MessagingService / MemoryStore: check the shape first.
local function isMessage(value: any): boolean
	return typeof(value) == "table"
		and typeof(value.id) == "string"
		and typeof(value.clanId) == "string"
		and typeof(value.userId) == "number"
		and typeof(value.name) == "string"
		and typeof(value.text) == "string"
		and typeof(value.at) == "number"
		and #value.text <= ClanConfig.CHAT_MAX_LENGTH * 4
end

-- Shows a new message to this server's members of that clan (who may see it).
local function deliver(message: Message)
	if not isMessage(message) or seen[message.id] ~= nil then
		return
	end
	seen[message.id] = os.clock()
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data ~= nil and data.clanId == message.clanId and SyncService.isReady(player) then
			task.spawn(function()
				if canUsersChat(message.userId, player.UserId) then
					RemoteService.fireClient(Remotes.Events.ClanChat, player, { message }, false)
				end
			end)
		end
	end
end

-- A note only the sender sees (e.g. chat is off for their account).
local function systemNote(player: Player, text: string)
	local data = DataService.get(player)
	RemoteService.fireClient(Remotes.Events.ClanChat, player, {
		{ id = HttpService:GenerateGUID(false), clanId = if data ~= nil then data.clanId else "", userId = 0, name = "", text = text, at = os.time() },
	}, false)
end

local function send(player: Player, text: string)
	local data = DataService.get(player)
	if data == nil or data.clanId == "" then
		return
	end
	text = (string.gsub((string.gsub(text, "^%s+", "")), "%s+$", ""))
	if #text == 0 or #text > ClanConfig.CHAT_MAX_LENGTH then
		return
	end
	if not canUserChat(player.UserId) then
		systemNote(player, "Chat isn't available on your account.")
		return
	end
	local ok, filtered = pcall(function(): string
		local result = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or typeof(filtered) ~= "string" or #filtered == 0 then
		systemNote(player, "That message couldn't be sent. Try again.")
		return
	end
	local fresh = DataService.get(player)
	if fresh == nil or fresh.clanId ~= data.clanId then
		return -- left the clan while filtering
	end
	local message: Message = {
		id = HttpService:GenerateGUID(false),
		clanId = data.clanId,
		userId = player.UserId,
		name = player.DisplayName,
		text = filtered,
		at = os.time(),
	}
	deliver(message)
	ClanStore.publishChat(message)
	task.spawn(ClanStore.appendChat, message.clanId, message, ClanConfig.CHAT_HISTORY, ClanConfig.CHAT_HISTORY_SECONDS)
end

-- Sends the recent history (only messages this player may see), replacing what they had.
local function sendHistory(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local clanId = data.clanId
	knownClan[player] = clanId
	if clanId == "" then
		RemoteService.fireClient(Remotes.Events.ClanChat, player, {}, true)
		return
	end
	local visible: { Message } = {}
	for _, message in ClanStore.getChat(clanId) do
		if isMessage(message) and canUsersChat(message.userId, player.UserId) then
			table.insert(visible, message)
		end
	end
	local fresh = DataService.get(player)
	if fresh ~= nil and fresh.clanId == clanId then
		RemoteService.fireClient(Remotes.Events.ClanChat, player, visible, true)
	end
end

function ClanChatService.start()
	RemoteService.onEvent(
		Remotes.Events.ClanChatSend,
		RateLimiter.new(ClanConfig.CHAT_RATE_BURST, ClanConfig.CHAT_RATE_PER_SECOND),
		function(text: unknown): string?
			if typeof(text) ~= "string" or #(text :: string) > ClanConfig.CHAT_MAX_LENGTH * 4 then
				return nil
			end
			return text :: string
		end,
		send
	)
	ClanStore.subscribeChat(deliver)
	SyncService.ClientReady:Connect(function(player: Player)
		task.spawn(sendHistory, player)
	end)
	-- Joined, left or switched clans: send the right history.
	task.spawn(function()
		while true do
			task.wait(5)
			for _, player in Players:GetPlayers() do
				local data = DataService.get(player)
				if data ~= nil and SyncService.isReady(player) and knownClan[player] ~= data.clanId then
					task.spawn(sendHistory, player)
				end
			end
			-- Forget old message ids and permission answers.
			local now = os.clock()
			for id, at in seen do
				if now - at > 600 then
					seen[id] = nil
				end
			end
			for cacheKey, entry in allowedCache do
				if now - entry.at > PERMISSION_SECONDS then
					allowedCache[cacheKey] = nil
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		knownClan[player] = nil
	end)
end

return ClanChatService
