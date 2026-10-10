--!strict
-- Speed and the Wild (Config/Wild): what the treadmill trains, how fast a player runs with an egg, and whether
-- they can outrun a biome's guardians.

local WildConfig = require(script.Parent.Parent.Config.Wild)

local Wild = {}

-- Speed a second the treadmill trains at `level`: a little less the faster the player already is
function Wild.trainRate(level: number, speed: number): number
	local gain = WildConfig.TREADMILL_GAINS[math.clamp(level, 1, #WildConfig.TREADMILL_GAINS)]
	return gain / (1 + math.max(0, speed - WildConfig.START_SPEED) / 12)
end

-- Speed after training `seconds` (capped)
function Wild.train(speed: number, level: number, seconds: number): number
	return math.min(WildConfig.MAX_SPEED, speed + Wild.trainRate(level, speed) * seconds)
end

-- How fast a player runs while carrying an egg
function Wild.carrying(speed: number): number
	return speed * WildConfig.CARRY
end

-- Whether a player this fast outruns the biome's guardians with an egg
function Wild.outruns(speed: number, biome: WildConfig.Biome): boolean
	return Wild.carrying(speed) > biome.guardian
end

-- The speed a player needs to outrun a biome's guardians with an egg
function Wild.needs(biome: WildConfig.Biome): number
	return math.ceil(biome.guardian / WildConfig.CARRY + 0.01)
end

return Wild
