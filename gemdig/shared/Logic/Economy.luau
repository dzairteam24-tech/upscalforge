--!strict
-- Expected values of digging, in one place: what a gem is worth on average at a depth, how long a cube takes, how
-- many coins a minute a player earns with a shovel and backpack. Used for balancing (the economy simulator test),
-- for what the drone earns while a player is away, and for the "X minutes of income" Robux packs.

local Config = script.Parent.Parent.Config
local Gear = require(Config.Gear)
local Gems = require(Config.Gems)
local Gem = require(script.Parent.Gem)
local MineConfig = require(Config.Mine)
local MineGen = require(script.Parent.MineGen)

local Economy = {}

Economy.OVERHEAD = 0.35 -- seconds a cube costs besides the swings (falling, turning)
Economy.TRIP = 10 -- seconds a selling trip costs (to the town, the sell stand, back down)

-- Average size and mutation multipliers, and average slots, of a freshly found gem
local sizeValue, sizeSlots = 0, 0
for _, size in Gem.SIZES do
	sizeValue += size.chance * size.mult
	sizeSlots += size.chance * size.slots
end
local mutationValue = 1
for _, mutation in Gem.MUTATIONS do
	mutationValue += mutation.chance * (mutation.mult - 1)
end
Economy.SLOTS_PER_GEM = sizeSlots

-- The average coins of one gem found at this layer
function Economy.gemValue(layer: number): number
	local total, weights = 0, 0
	for _, gem in Gems.LIST do
		if layer >= gem.from and layer <= gem.to then
			total += gem.weight * gem.value
			weights += gem.weight
		end
	end
	if weights == 0 then
		return 0
	end
	return total / weights * sizeValue * mutationValue
end

-- Seconds to break a cube at this layer with this shovel (index in Gear.SHOVELS)
function Economy.blockSeconds(shovel: number, layer: number): number
	local s = Gear.SHOVELS[shovel] or Gear.SHOVELS[1]
	return s.cooldown * math.ceil(MineGen.hp(layer) / s.power) + Economy.OVERHEAD
end

-- Coins per minute digging at one layer, with a trip to sell whenever the backpack fills
function Economy.perMinute(shovel: number, pack: number, layer: number): number
	local capacity = (Gear.PACKS[pack] or Gear.PACKS[1]).slots
	local gemsPerBlock = MineConfig.GEM_CHANCE + MineConfig.GEODE_CHANCE * MineConfig.GEODE_GEMS
	local valuePerBlock = MineConfig.GEM_CHANCE * Economy.gemValue(layer) + MineConfig.GEODE_CHANCE * MineConfig.GEODE_GEMS * Economy.gemValue(math.min(MineConfig.MAX_LAYER, layer + MineConfig.GEODE_DEEPER))
	local blocksPerTrip = capacity / (Economy.SLOTS_PER_GEM * gemsPerBlock)
	local tripSeconds = blocksPerTrip * Economy.blockSeconds(shovel, layer) + Economy.TRIP
	return blocksPerTrip * valuePerBlock / tripSeconds * 60
end

-- The layer (up to `deepest`, and no deeper than the shovel can break) where a player earns the most, and what
-- they earn there
function Economy.best(shovel: number, pack: number, deepest: number): (number, number)
	local bestLayer, bestRate = 1, 0
	for layer = 1, math.max(1, math.min(MineConfig.MAX_LAYER, deepest, MineGen.reach(shovel))) do
		local rate = Economy.perMinute(shovel, pack, layer)
		if rate > bestRate then
			bestLayer, bestRate = layer, rate
		end
	end
	return bestLayer, bestRate
end

return Economy
