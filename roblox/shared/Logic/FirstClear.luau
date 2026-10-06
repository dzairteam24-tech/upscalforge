--!strict
-- First-clear bonuses (Config/FirstClear). `clears` holds keys like "G3" (zone 3 guardian) and "Boss".

local Config = require(script.Parent.Parent.Config.FirstClear)

local FirstClear = {}

function FirstClear.guardianKey(zoneId: number): string
	return "G" .. zoneId
end

-- Marks a clear. True only the first time.
function FirstClear.mark(clears: { [string]: boolean }, key: string): boolean
	if clears[key] then
		return false
	end
	clears[key] = true
	return true
end

function FirstClear.guardians(clears: { [string]: boolean }): number
	local n = 0
	for key in clears do
		if string.match(key, "^G%d+$") then
			n += 1
		end
	end
	return n
end

function FirstClear.coinMult(clears: { [string]: boolean }): number
	return 1 + Config.GUARDIAN_COINS * FirstClear.guardians(clears)
end

function FirstClear.luckMult(clears: { [string]: boolean }): number
	return if clears.Boss then 1 + Config.BOSS_LUCK else 1
end

return FirstClear
