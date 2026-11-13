--!strict
-- Per-player token bucket. Each player gets `capacity` tokens that refill at
-- `refillPerSecond`. Spending more than you have is refused.
--   local limiter = RateLimiter.new(10, 5)  -- burst of 10, then 5 per second
--   if limiter:allow(player) then ... end
--   local granted = limiter:take(player, 12) -- may grant fewer than asked

local Players = game:GetService("Players")

export type RateLimiter = {
	-- Takes up to `amount` whole tokens; returns how many were actually granted.
	take: (self: RateLimiter, player: Player, amount: number) -> number,
	-- Takes exactly one token. Returns false if the player is over the limit.
	allow: (self: RateLimiter, player: Player) -> boolean,
}

type Bucket = { tokens: number, lastRefill: number }

local RateLimiter = {}

function RateLimiter.new(capacity: number, refillPerSecond: number): RateLimiter
	local buckets: { [Player]: Bucket } = {}

	Players.PlayerRemoving:Connect(function(player: Player)
		buckets[player] = nil
	end)

	local function refill(player: Player): Bucket
		local now = os.clock()
		local bucket = buckets[player]
		if bucket == nil then
			bucket = { tokens = capacity, lastRefill = now }
			buckets[player] = bucket
			return bucket
		end
		local elapsed = now - bucket.lastRefill
		bucket.tokens = math.min(capacity, bucket.tokens + elapsed * refillPerSecond)
		bucket.lastRefill = now
		return bucket
	end

	local limiter: RateLimiter = {
		take = function(_self: RateLimiter, player: Player, amount: number): number
			if amount <= 0 then
				return 0
			end
			local bucket = refill(player)
			local granted = math.min(math.floor(amount), math.floor(bucket.tokens))
			if granted <= 0 then
				return 0
			end
			bucket.tokens -= granted
			return granted
		end,

		allow = function(self: RateLimiter, player: Player): boolean
			return self:take(player, 1) == 1
		end,
	}

	return limiter
end

return table.freeze(RateLimiter)
