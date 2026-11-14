--!strict
-- The owner's ADMIN panel (UI/AdminUI), in the live game. OWNER ONLY: every request is
-- checked with Util/Owner on the server (the client just hides the button for others;
-- that is never trusted). Actions:
--   "List"                                    codes + free-pass players
--   "GrantPasses" {name, passes}              give exactly these passes ({} = take away)
--   "CreateCode" {code, rewards, days, maxUses}   make or edit a promo code
--   "DeleteCode" {code}
-- The player attribute "IsGameOwner" tells the client to show the panel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Services = script.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = Shared:WaitForChild("Config")
local PromoConfig = require(Config:WaitForChild("PromoConfig"))
local MonetizationConfig = require(Config:WaitForChild("MonetizationConfig"))
local RateLimiter = require(Server.Util.RateLimiter)
local Owner = require(Server.Util.Owner)
local RemoteService = require(Services.RemoteService)
local MonetizationService = require(Services.MonetizationService)
local PromoService = require(Services.PromoService)

type Result = Types.AdminResult

local AdminService = {}

local function lists(message: string, ok: boolean?): Result
	return { ok = ok ~= false, message = message, codes = PromoService.list(), grants = MonetizationService.listGrants() }
end

local function grantPasses(payload: any): Result
	local name = if typeof(payload.name) == "string" then string.gsub(payload.name, "%s", "") else ""
	if #name < 3 or #name > 20 then
		return { ok = false, message = "Type a Roblox username." }
	end
	local passes: { string } = {}
	if typeof(payload.passes) == "table" then
		for _, passKey in payload.passes do
			if typeof(passKey) == "string" and MonetizationConfig.PASSES[passKey] ~= nil and table.find(passes, passKey) == nil then
				table.insert(passes, passKey)
			end
		end
	end
	local found, userId = pcall(function(): number
		return Players:GetUserIdFromNameAsync(name)
	end)
	if not found or typeof(userId) ~= "number" then
		return { ok = false, message = `No Roblox user called "{name}".` }
	end
	local realName = name
	pcall(function()
		realName = Players:GetNameFromUserIdAsync(userId)
	end)
	local ok, err = MonetizationService.setGrant(userId, realName, passes)
	if not ok then
		return { ok = false, message = `Couldn't save (Roblox storage error): {err}` }
	end
	return lists(if #passes == 0 then `Took away {realName}'s free passes.` else `{realName} now has: {table.concat(passes, ", ")}.`)
end

local function createCode(payload: any): Result
	local code = if typeof(payload.code) == "string" then PromoService.normalize(payload.code) else nil
	if code == nil then
		return { ok = false, message = `Codes are {PromoConfig.CODE_MIN}-{PromoConfig.CODE_MAX} letters or numbers.` }
	end
	local rewards = PromoService.cleanRewards(payload.rewards)
	if rewards == nil then
		return { ok = false, message = "Give the code at least one reward." }
	end
	local days = if typeof(payload.days) == "number" and payload.days == payload.days then math.clamp(payload.days, 1, PromoConfig.MAX_DAYS) else 7
	local maxUses = if typeof(payload.maxUses) == "number" and payload.maxUses == payload.maxUses then math.max(0, math.floor(payload.maxUses)) else 0
	local ok, err = PromoService.create(code, rewards, days, maxUses)
	if not ok then
		return { ok = false, message = `Couldn't save (Roblox storage error): {err}` }
	end
	return lists(`Code {code} is live for {days} days.`)
end

local function handle(player: Player, request: { action: string, payload: any }): Result
	if not Owner.is(player) then
		return { ok = false, message = "Owner only." }
	end
	local payload = request.payload
	if request.action == "List" then
		return lists("")
	elseif request.action == "GrantPasses" then
		return grantPasses(payload)
	elseif request.action == "CreateCode" then
		return createCode(payload)
	elseif request.action == "DeleteCode" then
		local code = if typeof(payload.code) == "string" then PromoService.normalize(payload.code) else nil
		if code == nil then
			return { ok = false, message = "Unknown code." }
		end
		local ok, err = PromoService.delete(code)
		return if ok then lists(`Deleted {code}.`) else { ok = false, message = `Couldn't delete: {err}` }
	end
	return { ok = false, message = "Unknown action." }
end

function AdminService.start()
	local function mark(player: Player)
		task.spawn(function()
			if Owner.is(player) then
				player:SetAttribute("IsGameOwner", true)
			end
		end)
	end
	Players.PlayerAdded:Connect(mark)
	for _, player in Players:GetPlayers() do
		mark(player)
	end

	local ACTIONS = { List = true, GrantPasses = true, CreateCode = true, DeleteCode = true }
	RemoteService.onInvoke(
		Remotes.Functions.AdminRequest,
		RateLimiter.new(6, 1),
		function(action: unknown, payload: unknown): { action: string, payload: any }?
			if typeof(action) ~= "string" or not ACTIONS[action :: string] then
				return nil
			end
			return { action = action :: string, payload = if typeof(payload) == "table" then payload else {} }
		end,
		handle,
		{ ok = false, message = "Slow down a little." } :: Result
	)
end

return AdminService
