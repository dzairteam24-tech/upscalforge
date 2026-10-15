--!strict
-- The farm level, from XP (every harvest gives some). Each level unlocks crops (Config/Crops) and more land.

local Level = {}

Level.MAX = 50

-- XP from one level to the next
function Level.toNext(level: number): number
	return math.floor(30 * level ^ 1.85)
end

-- The level of a total of XP, and how far into it (0..1)
function Level.of(xp: number): (number, number)
	local level = 1
	local need = Level.toNext(1)
	while xp >= need and level < Level.MAX do
		xp -= need
		level += 1
		need = Level.toNext(level)
	end
	return level, if level >= Level.MAX then 1 else xp / need
end

-- The total XP that reaches a level
function Level.total(level: number): number
	local sum = 0
	for l = 1, level - 1 do
		sum += Level.toNext(l)
	end
	return sum
end

return Level
