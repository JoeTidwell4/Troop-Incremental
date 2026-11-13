--!strict
-- Clan membership and roles: create, browse/search, join, leave, kick, promote, demote,
-- open/closed. Bank + perks live in ClanBankService and the raid in RaidService; both add
-- their own actions here with ClanService.registerAction.
--
-- Truth vs cache:
--   * The clan record in the "Clans" DataStore is the source of truth for who's in a clan.
--   * Each player's save keeps a copy of their clan id. It's checked against the record
--     when they join the game and every POLL_INTERVAL, and cleared if they're not listed
--     (e.g. they were kicked from another server, or a server crashed mid-join).
--   * Joining writes the player's save FIRST, then the clan record, so a crash in between
--     is always fixed by that check rather than leaving a ghost member.
--
-- This server keeps a cached copy of every clan that has a member online here, re-read on
-- a timer and immediately whenever another server publishes a change (MessagingService).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local ClanConfig = require(Shared:WaitForChild("Config"):WaitForChild("ClanConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local RemoteService = require(Services.RemoteService)
local DataService = require(Services.DataService)
local SyncService = require(Services.SyncService)
local ClanStore = require(Services.ClanStore)

type ClanRecord = Types.ClanRecord
type ClanResult = Types.ClanResult
type ClanSummary = Types.ClanSummary
type ClanRole = Types.ClanRole
type PlayerData = Types.PlayerData

export type Handler = (player: Player, data: PlayerData, arg: any) -> ClanResult
-- Checks the raw argument from the client. Returns (valid, cleanedArg).
export type ArgValidator = (arg: unknown) -> (boolean, any)

type Request = { action: string, arg: any }

local ROLE_RANK: { [string]: number } = { Leader = 3, Officer = 2, Member = 1 }

local clans: { [string]: ClanRecord } = {} -- cached records for clans with members online here
local busy: { [Player]: boolean } = {} -- one clan request at a time per player
local actions: { [string]: { validate: ArgValidator, handle: Handler } } = {}
local browseCache: { at: number, list: { ClanSummary } }? = nil

local ClanService = {
	-- Fires after a clan's cached record changes on this server: (clanId).
	ClanChanged = Signal.new() :: Signal.Signal<string>,
	-- Fires when another server says a clan changed (MessagingService), even if no one
	-- here is in it (ClanExtrasService uses it to notice accepted join requests).
	Nudged = Signal.new() :: Signal.Signal<string>,
	-- Extra Supplies to show in a clan's bank (donations buffered on this server).
	-- ClanBankService replaces this.
	bankBonus = function(_clanId: string): number
		return 0
	end,
	-- Adds extra fields to a member's view before it's sent (ClanWarService replaces this
	-- to add clan XP still buffered here and the player's own contribution).
	decorateView = function(_player: Player, _view: Types.ClanView) end,
}

local function fail(reason: string): ClanResult
	return { ok = false, reason = reason }
end

local function key(player: Player): string
	return tostring(player.UserId)
end

---------------------------------------------------------------- reading

-- The player's clan record (cached), or nil if they're not in one.
function ClanService.getClan(player: Player): ClanRecord?
	local data = DataService.get(player)
	if data == nil or data.clanId == "" then
		return nil
	end
	local record = clans[data.clanId]
	if record == nil or record.members[key(player)] == nil then
		return nil
	end
	return record
end

function ClanService.getRole(player: Player): ClanRole?
	local record = ClanService.getClan(player)
	if record == nil then
		return nil
	end
	return record.members[key(player)].role
end

function ClanService.roleRank(role: string?): number
	return if role ~= nil then ROLE_RANK[role] or 0 else 0
end

-- Online players on this server whose save says they're in this clan.
local function onlineMembers(clanId: string): { Player }
	local list: { Player } = {}
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data ~= nil and data.clanId == clanId then
			table.insert(list, player)
		end
	end
	return list
end

---------------------------------------------------------------- client view

function ClanService.pushView(player: Player)
	if not SyncService.isReady(player) then
		return
	end
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local record = ClanService.getClan(player)
	local view: Types.ClanView
	if record == nil then
		view = {
			inClan = false,
			clan = nil,
			myRole = nil,
			donatedToday = 0,
			requestClanId = if data.clanRequest.clanId ~= "" then data.clanRequest.clanId else nil,
		}
	else
		-- Copy so the display bank can include donations still waiting to be sent.
		local shown = table.clone(record)
		shown.bank = record.bank + ClanService.bankBonus(record.id)
		local today = Formulas.clanDay(os.time())
		view = {
			inClan = true,
			clan = shown,
			myRole = record.members[key(player)].role,
			donatedToday = if data.clanDonation.dayId == today then data.clanDonation.amount else 0,
		}
		ClanService.decorateView(player, view)
	end
	RemoteService.fireClient(Remotes.Events.ClanSync, player, view)
end

function ClanService.pushClan(clanId: string)
	for _, player in onlineMembers(clanId) do
		ClanService.pushView(player)
	end
end

---------------------------------------------------------------- cache

-- Stores a fresh record, clears anyone on this server who's no longer listed, and
-- updates their screens.
function ClanService.applyRecord(record: ClanRecord)
	local cached = clans[record.id]
	if cached ~= nil and cached.version > record.version then
		return -- older than what we have
	end
	clans[record.id] = record
	for _, player in onlineMembers(record.id) do
		if record.members[key(player)] == nil then
			local data = DataService.get(player)
			if data ~= nil then
				data.clanId = ""
				DataService.markChanged(player)
			end
		end
		ClanService.pushView(player)
	end
	ClanService.ClanChanged:Fire(record.id)
end

-- Re-reads a clan from the store (yields). A clan that no longer exists is removed from
-- every online member's save; a store error changes nothing.
function ClanService.refresh(clanId: string)
	local record, ok = ClanStore.get(clanId)
	if not ok then
		return
	end
	if record == nil or record.memberCount <= 0 then
		clans[clanId] = nil
		for _, player in onlineMembers(clanId) do
			local data = DataService.get(player)
			if data ~= nil then
				data.clanId = ""
				DataService.markChanged(player)
			end
			ClanService.pushView(player)
		end
		return
	end
	ClanService.applyRecord(record)
end

-- Saves a change made by an action, then tells the browse list and other servers.
local function afterChange(record: ClanRecord)
	ClanService.applyRecord(record)
	ClanStore.updateListing(record, ClanConfig.MAX_MEMBERS)
	ClanStore.publish(record.id)
end

function ClanService.afterChange(record: ClanRecord)
	afterChange(record)
end

---------------------------------------------------------------- text rules

local function cleanName(text: string): string
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	text = string.gsub(text, "%s+", " ")
	return text
end

-- Roblox requires player-written text shown to others to go through the text filter.
-- Returns true only if the filter leaves the text unchanged.
local function passesFilter(text: string, userId: number): boolean
	local ok, filtered = pcall(function(): string
		local result = TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	return ok and filtered == text
end
ClanService.passesFilter = passesFilter

local function summary(record: ClanRecord): ClanSummary
	return {
		id = record.id,
		name = record.name,
		tag = record.tag,
		memberCount = record.memberCount,
		faction = record.faction,
		open = record.open,
	}
end

---------------------------------------------------------------- actions

local function create(player: Player, data: PlayerData, arg: any): ClanResult
	if data.clanId ~= "" then
		return fail("InClan")
	end
	if data.bestStage < ClanConfig.CREATE_MIN_BEST_STAGE then
		return fail("StageTooLow")
	end
	if ClanConfig.CLAN_REQUIRES_SAME_FACTION and data.faction == "" then
		return fail("NeedFaction")
	end
	local name = cleanName(arg.name)
	local tag = string.upper(arg.tag)
	if #name < ClanConfig.NAME_MIN_LENGTH or #name > ClanConfig.NAME_MAX_LENGTH or not string.match(name, "^[%w ]+$") then
		return fail("BadName")
	end
	if #tag < ClanConfig.TAG_MIN_LENGTH or #tag > ClanConfig.TAG_MAX_LENGTH or not string.match(tag, "^%w+$") then
		return fail("BadTag")
	end
	if not passesFilter(name, player.UserId) or not passesFilter(tag, player.UserId) then
		return fail("NameNotAllowed")
	end

	local now = os.time()
	local clanId = string.sub(string.gsub(HttpService:GenerateGUID(false), "-", ""), 1, 16)
	local record: ClanRecord = {
		id = clanId,
		name = name,
		tag = tag,
		faction = if ClanConfig.CLAN_REQUIRES_SAME_FACTION then data.faction else "",
		open = true,
		createdAt = now,
		members = {
			[key(player)] = { role = "Leader", name = player.Name, joinedAt = now, donated = 0 },
		},
		memberCount = 1,
		bank = 0,
		perks = {},
		version = 1,
	}
	local ok, reason = ClanStore.create(record)
	if not ok then
		return fail(reason or "StoreError")
	end
	local fresh = DataService.get(player)
	if fresh == nil then
		return fail("NotLoaded")
	end
	fresh.clanId = clanId
	fresh.clanRequest = { clanId = "", at = 0 } -- in a clan now: drop any pending request
	afterChange(record)
	browseCache = nil
	return { ok = true }
end

local function join(player: Player, data: PlayerData, clanId: string): ClanResult
	if data.clanId ~= "" then
		return fail("InClan")
	end
	local faction = data.faction
	local name = player.Name
	-- Save first: if anything below fails or the server dies, the next check clears it.
	data.clanId = clanId
	local record, reason = ClanStore.update(clanId, function(r: ClanRecord): (ClanRecord?, string?)
		if r.members[key(player)] ~= nil then
			return r, nil -- already a member (e.g. a retried request)
		end
		if r.memberCount <= 0 then
			return nil, "ClanNotFound"
		end
		if not r.open then
			return nil, "ClanClosed"
		end
		if r.memberCount >= ClanConfig.MAX_MEMBERS then
			return nil, "ClanFull"
		end
		if ClanConfig.CLAN_REQUIRES_SAME_FACTION and r.faction ~= "" and r.faction ~= faction then
			return nil, "WrongFaction"
		end
		r.members[key(player)] = { role = "Member", name = name, joinedAt = os.time(), donated = 0 }
		r.memberCount += 1
		return r, nil
	end)
	local fresh = DataService.get(player)
	if record == nil then
		if fresh ~= nil and fresh.clanId == clanId then
			fresh.clanId = ""
		end
		return fail(reason or "StoreError")
	end
	if fresh ~= nil then
		fresh.clanRequest = { clanId = "", at = 0 } -- in a clan now: drop any pending request
	end
	afterChange(record)
	browseCache = nil
	return { ok = true }
end

-- Picks the next leader: highest role first, then whoever joined earliest.
local function successor(r: ClanRecord): string?
	local best: string? = nil
	for userKey, member in r.members do
		if best == nil then
			best = userKey
		else
			local current = r.members[best]
			local rank, bestRank = ROLE_RANK[member.role] or 0, ROLE_RANK[current.role] or 0
			if rank > bestRank or (rank == bestRank and member.joinedAt < current.joinedAt) then
				best = userKey
			end
		end
	end
	return best
end

local function leave(player: Player, data: PlayerData, _arg: any): ClanResult
	local clanId = data.clanId
	if clanId == "" then
		return fail("NotInClan")
	end
	local record, reason = ClanStore.update(clanId, function(r: ClanRecord): (ClanRecord?, string?)
		local me = r.members[key(player)]
		if me == nil then
			return r, nil
		end
		r.members[key(player)] = nil
		r.memberCount = math.max(0, r.memberCount - 1)
		if me.role == "Leader" then
			local nextLeader = successor(r)
			if nextLeader ~= nil then
				r.members[nextLeader].role = "Leader"
			end
		end
		return r, nil
	end)
	if record == nil and reason ~= "ClanNotFound" then
		return fail(reason or "StoreError")
	end
	local fresh = DataService.get(player)
	if fresh ~= nil then
		fresh.clanId = ""
		DataService.markChanged(player)
	end
	if record ~= nil and record.memberCount <= 0 then
		ClanStore.delete(record)
		clans[clanId] = nil
	elseif record ~= nil then
		afterChange(record)
	end
	browseCache = nil
	ClanService.pushView(player)
	return { ok = true }
end

-- Shared shape for actions on another member (kick / promote / demote).
local function manage(player: Player, data: PlayerData, targetId: number, kind: "Kick" | "Promote" | "Demote"): ClanResult
	local clanId = data.clanId
	if clanId == "" then
		return fail("NotInClan")
	end
	local target = tostring(targetId)
	if target == key(player) then
		return fail("NotYourself")
	end
	local record, reason = ClanStore.update(clanId, function(r: ClanRecord): (ClanRecord?, string?)
		local me = r.members[key(player)]
		local them = r.members[target]
		if me == nil then
			return nil, "NotInClan"
		end
		if them == nil then
			return nil, "NotAMember"
		end
		local myRank, theirRank = ROLE_RANK[me.role] or 0, ROLE_RANK[them.role] or 0
		if kind == "Kick" then
			if myRank < ROLE_RANK.Officer or theirRank >= myRank then
				return nil, "NotAllowed"
			end
			r.members[target] = nil
			r.memberCount = math.max(0, r.memberCount - 1)
		elseif kind == "Promote" then
			if me.role ~= "Leader" then
				return nil, "NotAllowed"
			end
			if them.role == "Member" then
				them.role = "Officer"
			elseif them.role == "Officer" then
				-- Promoting an Officer hands over leadership.
				them.role = "Leader"
				me.role = "Officer"
			end
		else
			if me.role ~= "Leader" or them.role ~= "Officer" then
				return nil, "NotAllowed"
			end
			them.role = "Member"
		end
		return r, nil
	end)
	if record == nil then
		return fail(reason or "StoreError")
	end
	afterChange(record)
	return { ok = true }
end

local function setOpen(player: Player, data: PlayerData, open: boolean): ClanResult
	if data.clanId == "" then
		return fail("NotInClan")
	end
	local record, reason = ClanStore.update(data.clanId, function(r: ClanRecord): (ClanRecord?, string?)
		local me = r.members[key(player)]
		if me == nil or me.role ~= "Leader" then
			return nil, "NotAllowed"
		end
		r.open = open
		return r, nil
	end)
	if record == nil then
		return fail(reason or "StoreError")
	end
	afterChange(record)
	browseCache = nil
	return { ok = true }
end

local function browse(_player: Player, _data: PlayerData, _arg: any): ClanResult
	local cached = browseCache
	if cached ~= nil and os.clock() - cached.at < ClanConfig.BROWSE_CACHE_SECONDS then
		return { ok = true, clans = cached.list }
	end
	local entries = ClanStore.listOpen(ClanConfig.BROWSE_COUNT)
	if entries == nil then
		return fail("StoreError")
	end
	local list: { ClanSummary } = {}
	for _, entry in entries do
		local record = clans[entry.id] or ClanStore.get(entry.id)
		if record ~= nil and record.memberCount > 0 then
			table.insert(list, summary(record))
		end
	end
	browseCache = { at = os.clock(), list = list }
	return { ok = true, clans = list }
end

local function search(_player: Player, _data: PlayerData, name: string): ClanResult
	local clanId = ClanStore.findByName(cleanName(name))
	if clanId == nil then
		return { ok = true, clans = {} }
	end
	local record = ClanStore.get(clanId)
	if record == nil or record.memberCount <= 0 then
		return { ok = true, clans = {} }
	end
	return { ok = true, clans = { summary(record) } }
end

---------------------------------------------------------------- validators

local function isString(maxLength: number): ArgValidator
	return function(arg: unknown): (boolean, any)
		return typeof(arg) == "string" and #(arg :: string) <= maxLength, arg
	end
end

local function isUserId(arg: unknown): (boolean, any)
	return typeof(arg) == "number" and arg == arg and (arg :: number) % 1 == 0 and (arg :: number) > 0, arg
end

local function noArg(_arg: unknown): (boolean, any)
	return true, nil
end

local function createArgs(arg: unknown): (boolean, any)
	if typeof(arg) ~= "table" then
		return false, nil
	end
	local t = arg :: any
	local name, tag = t.name, t.tag
	if typeof(name) ~= "string" or typeof(tag) ~= "string" or #name > 40 or #tag > 10 then
		return false, nil
	end
	return true, { name = name, tag = tag }
end

-- Lets other services add actions to the ClanRequest remote.
function ClanService.registerAction(name: string, validate: ArgValidator, handle: Handler)
	actions[name] = { validate = validate, handle = handle }
end

ClanService.registerAction("Create", createArgs, create)
ClanService.registerAction("Join", isString(40), join)
ClanService.registerAction("Leave", noArg, leave)
ClanService.registerAction("Kick", isUserId, function(p, d, id)
	return manage(p, d, id, "Kick")
end)
ClanService.registerAction("Promote", isUserId, function(p, d, id)
	return manage(p, d, id, "Promote")
end)
ClanService.registerAction("Demote", isUserId, function(p, d, id)
	return manage(p, d, id, "Demote")
end)
ClanService.registerAction("SetOpen", function(arg: unknown): (boolean, any)
	return typeof(arg) == "boolean", arg
end, setOpen)
ClanService.registerAction("Browse", noArg, browse)
ClanService.registerAction("Search", isString(ClanConfig.NAME_MAX_LENGTH + 10), search)

---------------------------------------------------------------- lifecycle

local function handleRequest(player: Player, request: Request): ClanResult
	local entry = actions[request.action]
	local data = DataService.get(player)
	if entry == nil or data == nil then
		return fail("Rejected")
	end
	if busy[player] then
		return fail("Busy")
	end
	busy[player] = true
	local ok, result = pcall(entry.handle, player, data, request.arg)
	busy[player] = nil
	if not ok then
		warn(`[ClanService] {request.action} failed for {player.Name}: {result}`)
		return fail("StoreError")
	end
	-- Their own screen updates even if nothing else changed (e.g. a failed join).
	ClanService.pushView(player)
	return result
end

local function onLoaded(player: Player, data: PlayerData)
	if data.clanId == "" then
		return
	end
	ClanService.refresh(data.clanId)
	local record = clans[data.clanId]
	-- Keep their display name up to date in the clan record.
	if record ~= nil and record.members[key(player)] ~= nil and record.members[key(player)].name ~= player.Name then
		local updated = ClanStore.update(data.clanId, function(r: ClanRecord): (ClanRecord?, string?)
			local me = r.members[key(player)]
			if me == nil then
				return nil, "NotInClan"
			end
			me.name = player.Name
			return r, nil
		end)
		if updated ~= nil then
			ClanService.applyRecord(updated)
		end
	end
end

local function poll()
	local ids: { [string]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data ~= nil and data.clanId ~= "" then
			ids[data.clanId] = true
		end
	end
	for clanId in clans do
		if not ids[clanId] then
			clans[clanId] = nil -- nobody here needs it anymore
		end
	end
	for clanId in ids do
		ClanService.refresh(clanId)
	end
end

function ClanService.start()
	local limiter = RateLimiter.new(ClanConfig.REQUESTS_BURST, ClanConfig.REQUESTS_PER_SECOND)
	RemoteService.onInvoke(Remotes.Functions.ClanRequest, limiter, function(action: unknown, arg: unknown): Request?
		if typeof(action) ~= "string" then
			return nil
		end
		local entry = actions[action :: string]
		if entry == nil then
			return nil
		end
		local valid, cleaned = entry.validate(arg)
		if not valid then
			return nil
		end
		return { action = action :: string, arg = cleaned }
	end, handleRequest, { ok = false, reason = "Rejected" } :: ClanResult)

	DataService.ProfileLoaded:Connect(function(player: Player, data: PlayerData)
		onLoaded(player, data)
	end)
	SyncService.ClientReady:Connect(function(player: Player)
		ClanService.pushView(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		busy[player] = nil
	end)

	ClanStore.subscribe(function(clanId: string)
		if clans[clanId] ~= nil then
			ClanService.refresh(clanId)
		end
		ClanService.Nudged:Fire(clanId)
	end)

	task.spawn(function()
		while true do
			task.wait(ClanConfig.POLL_INTERVAL)
			local ok, err = pcall(poll)
			if not ok then
				warn(`[ClanService] poll error: {err}`)
			end
		end
	end)
end

return ClanService
