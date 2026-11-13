--!strict
-- Clan customization and join requests (Phase 11d B + E). Registers ClanRequest actions:
--   Customize { color, emblem, motto }  Leader/Officer: the clan's color, emoji emblem and
--                                       motto (motto must pass Roblox's text filter)
--   RequestJoin clanId                   ask to join a CLOSED clan (open clans: just Join)
--   CancelRequest                        withdraw your request
--   AnswerRequest { userId, accept }     Leader/Officer: accept or decline a request
--
-- Cross-server: the request lives in the clan record (changed only through
-- ClanStore.update, so capacity checks can't race), and the requester's save remembers
-- which clan they asked (data.clanRequest). The requester's server finds out about an
-- answer on a MessagingService nudge (ClanService.Nudged) or its next poll: accepted ->
-- their save gets the clanId; declined or expired -> the request is cleared. If they joined
-- some other clan in the meantime, the accepting clan's record is fixed up.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ClanConfig = require(Shared:WaitForChild("Config"):WaitForChild("ClanConfig"))
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local ClanService = require(Services.ClanService)
local ClanStore = require(Services.ClanStore)

type ClanRecord = Types.ClanRecord
type ClanResult = Types.ClanResult
type PlayerData = Types.PlayerData

local checking: { [Player]: boolean } = {}

local ClanExtrasService = {}

local function fail(reason: string): ClanResult
	return { ok = false, reason = reason }
end

local function key(player: Player): string
	return tostring(player.UserId)
end

local function isOfficer(record: ClanRecord, userKey: string): boolean
	local me = record.members[userKey]
	return me ~= nil and ClanService.roleRank(me.role) >= ClanService.roleRank("Officer")
end

-- Drops requests older than REQUEST_EXPIRE_SECONDS (called inside UpdateAsync changes).
local function pruneRequests(r: ClanRecord)
	local requests = r.requests or {}
	local cutoff = os.time() - ClanConfig.REQUEST_EXPIRE_SECONDS
	for userKey, request in requests do
		if request.at < cutoff or r.members[userKey] ~= nil then
			requests[userKey] = nil
		end
	end
	r.requests = requests
end

local function countRequests(r: ClanRecord): number
	local count = 0
	for _ in r.requests or {} do
		count += 1
	end
	return count
end

---------------------------------------------------------------- customize

local function trim(text: string): string
	return (string.gsub((string.gsub(text, "^%s+", "")), "%s+$", ""))
end

local function customize(player: Player, data: PlayerData, arg: any): ClanResult
	if data.clanId == "" then
		return fail("NotInClan")
	end
	local motto = trim(arg.motto)
	if #motto > 0 and not ClanService.passesFilter(motto, player.UserId) then
		return fail("NameNotAllowed")
	end
	local userKey = key(player)
	local record, reason = ClanStore.update(data.clanId, function(r: ClanRecord): (ClanRecord?, string?)
		if not isOfficer(r, userKey) then
			return nil, "NotAllowed"
		end
		r.color = arg.color
		r.emblem = arg.emblem
		r.motto = motto
		return r, nil
	end)
	if record == nil then
		return fail(reason or "StoreError")
	end
	ClanService.afterChange(record)
	return { ok = true }
end

local function customizeArgs(arg: unknown): (boolean, any)
	if typeof(arg) ~= "table" then
		return false, nil
	end
	local t = arg :: any
	local color, emblem, motto = t.color, t.emblem, t.motto
	local function index(value: any, count: number): boolean
		return typeof(value) == "number" and value == value and value % 1 == 0 and value >= 1 and value <= count
	end
	if not index(color, #ClanConfig.COLORS) or not index(emblem, #ClanConfig.EMBLEMS) then
		return false, nil
	end
	if typeof(motto) ~= "string" or #motto > ClanConfig.MOTTO_MAX_LENGTH then
		return false, nil
	end
	return true, { color = color, emblem = emblem, motto = motto }
end

---------------------------------------------------------------- join requests

-- Removes this player's request from a clan record (best effort).
local function withdraw(player: Player, clanId: string)
	local userKey = key(player)
	local record = ClanStore.update(clanId, function(r: ClanRecord): (ClanRecord?, string?)
		if r.requests == nil or r.requests[userKey] == nil then
			return nil, "NoRequest"
		end
		r.requests[userKey] = nil
		return r, nil
	end)
	if record ~= nil then
		ClanService.afterChange(record)
	end
end

local function requestJoin(player: Player, data: PlayerData, clanId: string): ClanResult
	if data.clanId ~= "" then
		return fail("InClan")
	end
	local previous = data.clanRequest.clanId
	if previous ~= "" and previous ~= clanId then
		withdraw(player, previous) -- one request at a time
	end
	local userKey = key(player)
	local name, bestStage, faction = player.Name, data.bestStage, data.faction
	local record, reason = ClanStore.update(clanId, function(r: ClanRecord): (ClanRecord?, string?)
		if r.memberCount <= 0 then
			return nil, "ClanNotFound"
		end
		if r.members[userKey] ~= nil then
			return r, nil
		end
		if r.open then
			return nil, "ClanOpen" -- open clans: just join
		end
		if r.memberCount >= ClanConfig.MAX_MEMBERS then
			return nil, "ClanFull"
		end
		if ClanConfig.CLAN_REQUIRES_SAME_FACTION and r.faction ~= "" and r.faction ~= faction then
			return nil, "WrongFaction"
		end
		pruneRequests(r)
		local requests = r.requests :: { [string]: { name: string, at: number, bestStage: number } }
		if requests[userKey] == nil and countRequests(r) >= ClanConfig.MAX_REQUESTS then
			return nil, "TooManyRequests"
		end
		requests[userKey] = { name = name, at = os.time(), bestStage = bestStage }
		return r, nil
	end)
	if record == nil then
		return fail(reason or "StoreError")
	end
	local fresh = DataService.get(player)
	if fresh ~= nil then
		fresh.clanRequest = { clanId = clanId, at = os.time() }
		DataService.markChanged(player)
	end
	ClanService.afterChange(record)
	return { ok = true }
end

local function cancelRequest(player: Player, data: PlayerData, _arg: any): ClanResult
	local clanId = data.clanRequest.clanId
	if clanId == "" then
		return { ok = true }
	end
	data.clanRequest = { clanId = "", at = 0 }
	DataService.markChanged(player)
	withdraw(player, clanId)
	return { ok = true }
end

local function answerRequest(player: Player, data: PlayerData, arg: any): ClanResult
	if data.clanId == "" then
		return fail("NotInClan")
	end
	local me = key(player)
	local target = tostring(arg.userId)
	local record, reason = ClanStore.update(data.clanId, function(r: ClanRecord): (ClanRecord?, string?)
		if not isOfficer(r, me) then
			return nil, "NotAllowed"
		end
		pruneRequests(r)
		local requests = r.requests :: { [string]: { name: string, at: number, bestStage: number } }
		local request = requests[target]
		if request == nil then
			return nil, "NoRequest"
		end
		requests[target] = nil
		if arg.accept then
			if r.memberCount >= ClanConfig.MAX_MEMBERS then
				return nil, "ClanFull"
			end
			r.members[target] = { role = "Member", name = request.name, joinedAt = os.time(), donated = 0 }
			r.memberCount += 1
		end
		return r, nil
	end)
	if record == nil then
		return fail(reason or "StoreError")
	end
	ClanService.afterChange(record) -- also nudges the requester's server
	return { ok = true }
end

-- Checks the clan this player asked to join: accepted, declined, or still waiting.
local function checkRequest(player: Player)
	if checking[player] then
		return
	end
	local data = DataService.get(player)
	if data == nil or data.clanRequest.clanId == "" then
		return
	end
	checking[player] = true
	local clanId = data.clanRequest.clanId
	local record, ok = ClanStore.get(clanId)
	checking[player] = nil
	local fresh = DataService.get(player)
	if not ok or fresh == nil or fresh.clanRequest.clanId ~= clanId then
		return
	end
	local userKey = key(player)
	if record ~= nil and record.memberCount > 0 and record.members[userKey] ~= nil then
		fresh.clanRequest = { clanId = "", at = 0 }
		if fresh.clanId == "" then
			-- Accepted!
			fresh.clanId = clanId
			DataService.markChanged(player)
			ClanService.refresh(clanId)
			RemoteService.fireClient(Remotes.Events.Notice, player, { kind = "ClanJoined", stage = 0, itemName = record.name })
		elseif fresh.clanId ~= clanId then
			-- Already joined another clan: take them back out of this one.
			local fixed = ClanStore.update(clanId, function(r: ClanRecord): (ClanRecord?, string?)
				if r.members[userKey] == nil then
					return nil, "NotAMember"
				end
				r.members[userKey] = nil
				r.memberCount = math.max(0, r.memberCount - 1)
				return r, nil
			end)
			if fixed ~= nil then
				ClanService.afterChange(fixed)
			end
		end
	elseif record == nil or record.memberCount <= 0 or record.requests == nil or record.requests[userKey] == nil then
		fresh.clanRequest = { clanId = "", at = 0 } -- declined, expired, or the clan is gone
		DataService.markChanged(player)
	end
	ClanService.pushView(player)
end

---------------------------------------------------------------- start

function ClanExtrasService.start()
	ClanService.registerAction("Customize", customizeArgs, customize)
	ClanService.registerAction("RequestJoin", function(arg: unknown): (boolean, any)
		return typeof(arg) == "string" and #(arg :: string) <= 40, arg
	end, requestJoin)
	ClanService.registerAction("CancelRequest", function(_arg: unknown): (boolean, any)
		return true, nil
	end, cancelRequest)
	ClanService.registerAction("AnswerRequest", function(arg: unknown): (boolean, any)
		if typeof(arg) ~= "table" then
			return false, nil
		end
		local t = arg :: any
		local valid = typeof(t.userId) == "number" and t.userId == t.userId and t.userId % 1 == 0 and t.userId > 0
			and typeof(t.accept) == "boolean"
		return valid, if valid then { userId = t.userId, accept = t.accept } else nil
	end, answerRequest)

	DataService.ProfileLoaded:Connect(function(player: Player, _data: PlayerData)
		task.spawn(checkRequest, player)
	end)
	ClanService.Nudged:Connect(function(clanId: string)
		for _, player in Players:GetPlayers() do
			local data = DataService.get(player)
			if data ~= nil and data.clanRequest.clanId == clanId then
				task.spawn(checkRequest, player)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(ClanConfig.POLL_INTERVAL)
			for _, player in Players:GetPlayers() do
				local data = DataService.get(player)
				if data ~= nil and data.clanRequest.clanId ~= "" then
					task.spawn(checkRequest, player)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		checking[player] = nil
	end)
end

return ClanExtrasService
