--!strict
-- Non-negative big numbers stored as mantissa * 10^exponent.
--
-- Values are plain tables { m = mantissa, e = exponent } so they can be saved in
-- ProfileStore and sent through RemoteEvents with no conversion step.
-- Treat every BigNum as immutable: functions here always return a new value.
--
-- Invariant: either m == 0 and e == 0 (zero), or 1 <= m < 10 and e is an integer.

export type BigNum = { m: number, e: number }

local BigNum = {}

-- Past this exponent gap the smaller value can't change a double's mantissa.
local MAX_EXPONENT_GAP = 17

local ZERO: BigNum = table.freeze({ m = 0, e = 0 })
local ONE: BigNum = table.freeze({ m = 1, e = 0 })

BigNum.ZERO = ZERO
BigNum.ONE = ONE

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- Builds a normalized BigNum. m can be any finite positive number.
local function make(m: number, e: number): BigNum
	if m ~= m or m <= 0 then
		return ZERO
	end
	if not isFinite(m) or not isFinite(e) then
		error(`BigNum: non-finite value (m={m}, e={e})`, 3)
	end
	local shift = math.floor(math.log10(m))
	m /= 10 ^ shift
	e += shift
	-- Guard against floating point landing just outside [1, 10).
	if m >= 10 then
		m /= 10
		e += 1
	elseif m < 1 then
		m *= 10
		e -= 1
	end
	return { m = m, e = e }
end

function BigNum.new(mantissa: number, exponent: number): BigNum
	return make(mantissa, math.floor(exponent))
end

function BigNum.fromNumber(n: number): BigNum
	if not isFinite(n) then
		error(`BigNum.fromNumber: non-finite input {n}`, 2)
	end
	if n <= 0 then
		return ZERO
	end
	return make(n, 0)
end

-- Converts to a regular Luau number. Returns math.huge if it doesn't fit.
function BigNum.toNumber(value: BigNum): number
	if value.m == 0 then
		return 0
	end
	if value.e > 308 then
		return math.huge
	end
	return value.m * 10 ^ value.e
end

function BigNum.fromLog10(log: number): BigNum
	if log == -math.huge then
		return ZERO
	end
	local e = math.floor(log)
	return make(10 ^ (log - e), e)
end

-- log10 of the value. Zero returns -math.huge.
function BigNum.log10(value: BigNum): number
	if value.m == 0 then
		return -math.huge
	end
	return math.log10(value.m) + value.e
end

function BigNum.isZero(value: BigNum): boolean
	return value.m == 0
end

function BigNum.add(a: BigNum, b: BigNum): BigNum
	if a.m == 0 then
		return b
	end
	if b.m == 0 then
		return a
	end
	if a.e >= b.e then
		local gap = a.e - b.e
		if gap > MAX_EXPONENT_GAP then
			return a
		end
		return make(a.m + b.m / 10 ^ gap, a.e)
	else
		local gap = b.e - a.e
		if gap > MAX_EXPONENT_GAP then
			return b
		end
		return make(b.m + a.m / 10 ^ gap, b.e)
	end
end

-- a - b, floored at zero. For currency, check BigNum.gte(gold, cost) before subtracting.
function BigNum.sub(a: BigNum, b: BigNum): BigNum
	if b.m == 0 then
		return a
	end
	if BigNum.compare(a, b) <= 0 then
		return ZERO
	end
	local gap = a.e - b.e
	if gap > MAX_EXPONENT_GAP then
		return a
	end
	return make(a.m - b.m / 10 ^ gap, a.e)
end

function BigNum.mul(a: BigNum, b: BigNum): BigNum
	if a.m == 0 or b.m == 0 then
		return ZERO
	end
	return make(a.m * b.m, a.e + b.e)
end

function BigNum.mulNumber(a: BigNum, n: number): BigNum
	return BigNum.mul(a, BigNum.fromNumber(n))
end

function BigNum.div(a: BigNum, b: BigNum): BigNum
	if b.m == 0 then
		error("BigNum.div: division by zero", 2)
	end
	if a.m == 0 then
		return ZERO
	end
	return make(a.m / b.m, a.e - b.e)
end

-- base ^ exponent for a plain positive base, e.g. cost growth 1.07 ^ owned.
function BigNum.powNumber(base: number, exponent: number): BigNum
	if base <= 0 then
		error("BigNum.powNumber: base must be positive", 2)
	end
	return BigNum.fromLog10(exponent * math.log10(base))
end

-- Rounds to the nearest whole number. Values of 1e15 and up are already beyond
-- double precision for fractions, so they're returned as-is.
function BigNum.round(value: BigNum): BigNum
	if value.m == 0 or value.e >= 15 then
		return value
	end
	return BigNum.fromNumber(math.floor(BigNum.toNumber(value) + 0.5))
end

-- Returns -1 if a < b, 0 if equal, 1 if a > b.
function BigNum.compare(a: BigNum, b: BigNum): number
	if a.m == 0 or b.m == 0 then
		if a.m == b.m then
			return 0
		end
		return if a.m == 0 then -1 else 1
	end
	if a.e ~= b.e then
		return if a.e < b.e then -1 else 1
	end
	if a.m ~= b.m then
		return if a.m < b.m then -1 else 1
	end
	return 0
end

function BigNum.lt(a: BigNum, b: BigNum): boolean
	return BigNum.compare(a, b) < 0
end

function BigNum.lte(a: BigNum, b: BigNum): boolean
	return BigNum.compare(a, b) <= 0
end

function BigNum.gt(a: BigNum, b: BigNum): boolean
	return BigNum.compare(a, b) > 0
end

function BigNum.gte(a: BigNum, b: BigNum): boolean
	return BigNum.compare(a, b) >= 0
end

function BigNum.max(a: BigNum, b: BigNum): BigNum
	return if BigNum.compare(a, b) >= 0 then a else b
end

function BigNum.min(a: BigNum, b: BigNum): BigNum
	return if BigNum.compare(a, b) <= 0 then a else b
end

-- True if the value is a correctly shaped BigNum (use on loaded or received data).
function BigNum.isValid(value: unknown): boolean
	if typeof(value) ~= "table" then
		return false
	end
	local t = value :: { [any]: any }
	local m, e = t.m, t.e
	if typeof(m) ~= "number" or typeof(e) ~= "number" then
		return false
	end
	if not isFinite(m) or not isFinite(e) or e % 1 ~= 0 then
		return false
	end
	if m == 0 then
		return e == 0
	end
	return m >= 1 and m < 10
end

-- Returns a clean copy of a valid BigNum, or `fallback` (default zero) if it's malformed.
function BigNum.sanitize(value: unknown, fallback: BigNum?): BigNum
	if BigNum.isValid(value) then
		local t = value :: BigNum
		return { m = t.m, e = t.e }
	end
	return fallback or ZERO
end

return table.freeze(BigNum)
