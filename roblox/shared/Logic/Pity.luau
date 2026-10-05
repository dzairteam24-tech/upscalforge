--!strict
-- Bad-luck protection: every miss raises the next chance a little, and the Nth try is guaranteed.

local Pity = {}

-- Chance of the next try after `misses` misses in a row.
function Pity.chance(base: number, misses: number, guaranteeAt: number, step: number): number
	if misses + 1 >= guaranteeAt then
		return 1
	end
	return math.min(1, base + misses * step)
end

-- Tries left until the guaranteed one (counting the next try).
function Pity.left(misses: number, guaranteeAt: number): number
	return math.max(1, guaranteeAt - misses)
end

return Pity
