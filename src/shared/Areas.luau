--!strict
-- Works out which area a stage belongs to, and its display names.

local Shared = script.Parent
local Types = require(Shared.Types)
local AreaConfig = require(Shared.Config.AreaConfig)
local BossConfig = require(Shared.Config.BossConfig)

export type AreaInfo = {
	number: number, -- 1, 2, 3, ... (never wraps)
	theme: Types.AreaTheme,
	displayName: string, -- e.g. "Frozen Pass" or "Frozen Pass II"
	bossName: string,
}

local Areas = {}

local ROMAN: { { value: number, symbol: string } } = {
	{ value = 1000, symbol = "M" },
	{ value = 900, symbol = "CM" },
	{ value = 500, symbol = "D" },
	{ value = 400, symbol = "CD" },
	{ value = 100, symbol = "C" },
	{ value = 90, symbol = "XC" },
	{ value = 50, symbol = "L" },
	{ value = 40, symbol = "XL" },
	{ value = 10, symbol = "X" },
	{ value = 9, symbol = "IX" },
	{ value = 5, symbol = "V" },
	{ value = 4, symbol = "IV" },
	{ value = 1, symbol = "I" },
}

local function toRoman(n: number): string
	if n >= 4000 then
		return tostring(n)
	end
	local out = ""
	for _, entry in ROMAN do
		while n >= entry.value do
			out ..= entry.symbol
			n -= entry.value
		end
	end
	return out
end

function Areas.numberForStage(stage: number): number
	return (math.max(stage, 1) - 1) // BossConfig.BOSS_EVERY + 1
end

function Areas.forStage(stage: number): AreaInfo
	local number = Areas.numberForStage(stage)
	local themeCount = #AreaConfig.THEMES
	local theme = AreaConfig.THEMES[(number - 1) % themeCount + 1]
	local cycle = (number - 1) // themeCount + 1
	local suffix = if cycle > 1 then " " .. toRoman(cycle) else ""
	return {
		number = number,
		theme = theme,
		displayName = theme.name .. suffix,
		bossName = theme.bossName .. suffix,
	}
end

return table.freeze(Areas)
