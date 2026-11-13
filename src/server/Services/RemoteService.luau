--!strict
-- Creates every remote and is the ONLY place that listens to them.
--
-- Every handler must be registered with a rate limiter and a validator:
--   1. Rate limit: requests over the limit are dropped before anything else runs.
--   2. Validate: turns the raw client arguments into a typed value, or nil to reject.
--   3. Handler: only ever sees validated data.
-- Errors inside handlers are caught and logged so a bad request can't break the service.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Remotes = require(Shared:WaitForChild("Remotes"))
local RateLimiter = require(Server.Util.RateLimiter)

type RateLimiter = RateLimiter.RateLimiter

local events: { [string]: RemoteEvent } = {}
local functions: { [string]: RemoteFunction } = {}

local RemoteService = {}

local function getEvent(name: string): RemoteEvent
	local remote = events[name]
	if remote == nil then
		error(`RemoteService: unknown RemoteEvent "{name}". Add it to Shared/Remotes.`, 3)
	end
	return remote
end

local function getFunction(name: string): RemoteFunction
	local remote = functions[name]
	if remote == nil then
		error(`RemoteService: unknown RemoteFunction "{name}". Add it to Shared/Remotes.`, 3)
	end
	return remote
end

-- Must run before any other service registers handlers.
function RemoteService.start()
	local folder = Instance.new("Folder")
	folder.Name = Remotes.FOLDER_NAME

	for _, name in Remotes.Events do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		events[name] = remote
	end
	for _, name in Remotes.Functions do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
		functions[name] = remote
	end

	folder.Parent = ReplicatedStorage
end

-- Listen for a client -> server RemoteEvent.
function RemoteService.onEvent<T>(
	name: string,
	limiter: RateLimiter,
	validate: (...unknown) -> T?,
	handler: (player: Player, payload: T) -> ()
)
	getEvent(name).OnServerEvent:Connect(function(player: Player, ...: unknown)
		if not limiter:allow(player) then
			return
		end
		local payload = validate(...)
		if payload == nil then
			return
		end
		local ok, err = pcall(handler, player, payload)
		if not ok then
			warn(`[RemoteService] {name} handler error for {player.Name}: {err}`)
		end
	end)
end

-- Handle a client -> server RemoteFunction. `rejected` is returned when the request
-- is rate limited, invalid, or the handler errors.
function RemoteService.onInvoke<T, R>(
	name: string,
	limiter: RateLimiter,
	validate: (...unknown) -> T?,
	handler: (player: Player, payload: T) -> R,
	rejected: R
)
	getFunction(name).OnServerInvoke = function(player: Player, ...: unknown): R
		if not limiter:allow(player) then
			return rejected
		end
		local payload = validate(...)
		if payload == nil then
			return rejected
		end
		local ok, result = pcall(handler, player, payload)
		if not ok then
			warn(`[RemoteService] {name} handler error for {player.Name}: {result}`)
			return rejected
		end
		return result
	end
end

-- Send a server -> client RemoteEvent to one player.
function RemoteService.fireClient(name: string, player: Player, ...: any)
	getEvent(name):FireClient(player, ...)
end

return RemoteService
