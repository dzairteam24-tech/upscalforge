--!strict
-- Speed and the Wild (Config/Wild): speed (⚡) is a big number; this turns it into how fast the player really
-- walks, says what a step on the treadmill gives, how fast a player runs with an egg, and whether they outrun a
-- biome's guardian (whose pace is set from the speed its biome needs).

local WildConfig = require(script.Parent.Parent.Config.Wild)

local Wild = {}

-- How fast (studs a second) a player with this much ⚡ walks
function Wild.walk(power: number): number
	local doublings = math.log(1 + math.max(0, power) / WildConfig.WALK_BASE, 2)
	return math.min(WildConfig.WALK_MAX, WildConfig.START_SPEED + WildConfig.WALK_PER_DOUBLING * doublings)
end

-- ⚡ a step on the treadmill gives at its level
function Wild.gain(level: number): number
	return WildConfig.TREADMILL[math.clamp(level, 1, #WildConfig.TREADMILL)].gain
end

-- What the treadmill's next level costs, or nil at the top
function Wild.upgradePrice(level: number): number?
	local next = WildConfig.TREADMILL[level + 1]
	return if next then next.price else nil
end

-- How fast a player runs while carrying an egg
function Wild.carrying(power: number): number
	return Wild.walk(power) * WildConfig.CARRY
end

-- How fast a biome's guardian runs: a little slower than a player with just the ⚡ it needs, carrying an egg
function Wild.guardian(biome: WildConfig.Biome): number
	return Wild.carrying(biome.need) - 0.5
end

-- Whether a player with this much ⚡ outruns the biome's guardian with an egg
function Wild.outruns(power: number, biome: WildConfig.Biome): boolean
	return power >= biome.need
end

-- The ⚡ a player needs to outrun a biome's guardian with an egg
function Wild.needs(biome: WildConfig.Biome): number
	return biome.need
end

return Wild
