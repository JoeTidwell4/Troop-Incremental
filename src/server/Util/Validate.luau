--!strict
-- Runtime checks for data that arrives from clients. Anything from a client can be
-- any type or value (exploiters can send whatever they like), so every check
-- returns nil when the value is wrong.

local Validate = {}

-- A whole number between min and max (inclusive). Rejects NaN and infinity.
function Validate.integer(value: unknown, min: number, max: number): number?
	if typeof(value) ~= "number" then
		return nil
	end
	local n = value :: number
	if n ~= n or n % 1 ~= 0 or n < min or n > max then
		return nil
	end
	return n
end

-- One of a fixed list of allowed strings.
function Validate.oneOf(value: unknown, allowed: { string }): string?
	if typeof(value) ~= "string" then
		return nil
	end
	local s = value :: string
	if table.find(allowed, s) == nil then
		return nil
	end
	return s
end

-- A string that's a key in the given table (e.g. a troop id in TroopConfig.TROOPS).
function Validate.keyOf(value: unknown, dictionary: { [string]: any }): string?
	if typeof(value) ~= "string" then
		return nil
	end
	local s = value :: string
	if #s > 64 or dictionary[s] == nil then
		return nil
	end
	return s
end

return table.freeze(Validate)
