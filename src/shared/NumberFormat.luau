--!strict
-- Turns numbers into short display strings: 950, 1.2K, 3.45M, 12.3B, 999T, 5.6e15.
-- Always rounds DOWN, so the player never sees more gold than they really have.

local BigNum = require(script.Parent.BigNum)

type BigNum = BigNum.BigNum

local NumberFormat = {}

local SUFFIXES = { "", "K", "M", "B", "T" }
local SCIENTIFIC_FROM_EXPONENT = 15
local SIGNIFICANT_DIGITS = 3

-- "1.50" -> "1.5", "2.00" -> "2"
local function trimZeros(text: string): string
	if string.find(text, ".", 1, true) == nil then
		return text
	end
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

function NumberFormat.big(value: BigNum): string
	if value.m == 0 then
		return "0"
	end

	if value.e < 0 then
		local n = BigNum.toNumber(value)
		if n < 0.01 then
			return "0"
		end
		return trimZeros(string.format("%.2f", math.floor(n * 100) / 100))
	end

	-- Truncate the mantissa to 3 significant digits. The tiny epsilon stops 1.3 showing as 1.29.
	local scale = 10 ^ (SIGNIFICANT_DIGITS - 1)
	local mantissa = math.floor(value.m * scale + 1e-6) / scale

	if value.e >= SCIENTIFIC_FROM_EXPONENT then
		return trimZeros(string.format("%.2f", mantissa)) .. "e" .. string.format("%d", value.e)
	end

	local group = value.e // 3
	local within = value.e % 3
	local shown = mantissa * 10 ^ within
	local decimals = SIGNIFICANT_DIGITS - 1 - within
	local text = string.format(`%.{decimals}f`, shown)
	return trimZeros(text) .. SUFFIXES[group + 1]
end

function NumberFormat.number(n: number): string
	if n ~= n or n <= 0 then
		return "0"
	end
	if n == math.huge then
		return "Infinity"
	end
	return NumberFormat.big(BigNum.fromNumber(n))
end

return table.freeze(NumberFormat)
