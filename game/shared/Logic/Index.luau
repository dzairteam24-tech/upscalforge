--!strict
-- The Index's pages (Config/Index): which of an egg's creatures a player has hatched, and whether its reward
-- can be claimed.

local Creatures = require(script.Parent.Parent.Config.Creatures)
local Eggs = require(script.Parent.Parent.Config.Eggs)
local IndexConfig = require(script.Parent.Parent.Config.Index)

local Index = {}

local byTier: { [number]: Eggs.Egg } = {}
for _, egg in Eggs do
	byTier[egg.tier] = egg
end

-- How many of an egg's creatures are in the index, out of how many
function Index.progress(found: { [string]: boolean }, tier: number): (number, number)
	local egg = byTier[tier]
	if not egg then
		return 0, 0
	end
	local got = 0
	for _, species in egg.creatures do
		if found[species] then
			got += 1
		end
	end
	return got, #egg.creatures
end

-- Every creature found, out of all of them
function Index.total(found: { [string]: boolean }): (number, number)
	local got, all = 0, 0
	for _, egg in Eggs do
		local g, n = Index.progress(found, egg.tier)
		got += g
		all += n
	end
	return got, all
end

-- A page's reward, if it's complete and not claimed yet
function Index.claimable(found: { [string]: boolean }, claimed: { [string]: boolean }, tier: number): IndexConfig.Reward?
	local got, all = Index.progress(found, tier)
	if all == 0 or got < all or claimed[tostring(tier)] then
		return nil
	end
	return IndexConfig.REWARDS[tier]
end

-- What finding a creature for the first time gives (Config/Index)
function Index.creatureReward(species: string): IndexConfig.Reward
	local creature = Creatures.byId[species]
	if not creature then
		return { coins = 0, power = 0 }
	end
	return { coins = creature.earn * IndexConfig.CREATURE_SECONDS, power = IndexConfig.CREATURE_POWER[creature.rarity] or 0 }
end

return Index
