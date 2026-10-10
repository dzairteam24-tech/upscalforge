--!strict
-- Eggs (Config/Eggs) and what hatches from them: how long an egg incubates, and the creature and mutation it
-- hatches into.

local Eggs = require(script.Parent.Parent.Config.Eggs)
local IslandConfig = require(script.Parent.Parent.Config.Island)
local Mutations = require(script.Parent.Parent.Config.Mutations)

local Hatch = {}

local byTier: { [number]: Eggs.Egg } = {}
for _, egg in Eggs do
	byTier[egg.tier] = egg
end

function Hatch.egg(tier: number): Eggs.Egg?
	return byTier[tier]
end

-- Seconds an egg incubates: 1 minute for tier 1, about 30 minutes for tier 10, an hour for the Legendary
function Hatch.seconds(tier: number): number
	return math.floor(IslandConfig.BASE_INCUBATE * tier ^ 1.45)
end

-- The creature and mutation an egg hatches into. `random` gives numbers in [0, 1); `atLeast` is the weather's
-- mutation, which the hatch can't be below.
function Hatch.roll(tier: number, random: () -> number, atLeast: string?): (string, string)
	local egg = byTier[tier]
	assert(egg, "no egg of tier " .. tostring(tier))
	local roll = random()
	local creature = egg.creatures[#egg.creatures]
	for i, chance in egg.chances do
		if roll < chance then
			creature = egg.creatures[i]
			break
		end
		roll -= chance
	end
	-- The rarest mutation that comes up wins
	local mutation = "Normal"
	for _, candidate in Mutations.list do
		if candidate.chance > 0 and random() < candidate.chance then
			mutation = candidate.id
		end
	end
	local floor = if atLeast then Mutations.byId[atLeast] else nil
	if floor and Mutations.byId[mutation].order < floor.order then
		mutation = floor.id
	end
	return creature, mutation
end

return Hatch
