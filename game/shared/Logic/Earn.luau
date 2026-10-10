--!strict
-- What creatures earn on their owner's island (Config/Creatures, Config/Mutations).

local Creatures = require(script.Parent.Parent.Config.Creatures)
local IslandConfig = require(script.Parent.Parent.Config.Island)
local Mutations = require(script.Parent.Parent.Config.Mutations)
local SnapConfig = require(script.Parent.Parent.Config.Snap)

local Earn = {}

-- g: a snapped creature's grade (Config/Snap)
export type Owned = { s: string, m: string, g: string? }

-- Coins a second one creature earns
function Earn.rate(creature: Owned): number
	local species = Creatures.byId[creature.s]
	local mutation = Mutations.byId[creature.m] or Mutations.byId.Normal
	local grade = if creature.g then SnapConfig.byId[creature.g] else nil
	return if species then species.earn * mutation.mult * (if grade then grade.mult else 1) else 0
end

-- Coins a second the creatures living on an island earn together
function Earn.islandRate(creatures: { [string]: Owned }, placed: { string }): number
	local total = 0
	for _, id in placed do
		local creature = creatures[id]
		if creature then
			total += Earn.rate(creature)
		end
	end
	return total
end

-- Coins for the time an island's owner was away (up to OFFLINE_HOURS)
function Earn.offline(rate: number, seconds: number): number
	return math.floor(rate * math.clamp(seconds, 0, IslandConfig.OFFLINE_HOURS * 3600))
end

-- Coins for selling a creature
function Earn.sellPrice(creature: Owned): number
	return math.floor(Earn.rate(creature) * IslandConfig.SELL_SECONDS)
end

-- The price of the next incubator or pen, or nil when there are no more
function Earn.nextPrice(prices: { number }, owned: number, start: number): number?
	return prices[owned - start + 1]
end

return Earn
