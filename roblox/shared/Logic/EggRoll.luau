--!strict
-- Rolls a hatch result for an egg (zone eggs use the zone's id, see World1.eggs). `rng` returns a number in [0, 1).

local Config = script.Parent.Parent.Config
local Sizes = require(Config.Sizes)
local Variants = require(Config.Variants)
local World1 = require(Config.World1)
local Types = require(script.Parent.Types)

type Roll = Types.Roll

export type RollContext = {
	luck: number, -- total luck multiplier (1 = none)
	variantChance: { [string]: number }?, -- extra multiplier per variant
	forceGolden: boolean?, -- guarantees at least Golden (first-golden rule)
	minVariant: string?, -- guarantees at least this variant
}

local EggRoll = {}

-- Rare species (below 10%) get sqrt(luck): luck helps, but common species stay common.
-- Eggs with fixed odds (the Legendary Egg) ignore luck for the species.
function EggRoll.speciesWeights(eggId: number, luck: number): { { id: string, weight: number } }
	local egg = World1.eggs[eggId]
	local weights = {}
	local total = 0
	for index, speciesId in egg.species do
		local chance = egg.chances[index]
		local weight = chance
		if chance < 0.1 and not egg.fixedOdds then
			weight *= math.sqrt(math.max(1, luck))
		end
		total += weight
		table.insert(weights, { id = speciesId, weight = weight })
	end
	for _, entry in weights do
		entry.weight /= total
	end
	return weights
end

-- Effective chance of each variant after luck. Rarest is checked first.
function EggRoll.variantChance(variantId: string, context: RollContext): number
	local variant = Variants.byId[variantId]
	local extra = if context.variantChance then context.variantChance[variantId] or 1 else 1
	return math.min(1, variant.chance * math.max(1, context.luck) * extra)
end

function EggRoll.sizeChance(sizeId: string, context: RollContext): number
	local size = Sizes.byId[sizeId]
	return math.min(1, size.chance * math.max(1, context.luck))
end

function EggRoll.roll(eggId: number, context: RollContext, rng: () -> number): Roll
	-- Species
	local weights = EggRoll.speciesWeights(eggId, context.luck)
	local pick = rng()
	local speciesId = weights[#weights].id
	local acc = 0
	for _, entry in weights do
		acc += entry.weight
		if pick < acc then
			speciesId = entry.id
			break
		end
	end

	-- Variant: check from rarest to most common
	local variantId = "Normal"
	for index = #Variants.list, 2, -1 do
		local variant = Variants.list[index]
		if rng() < EggRoll.variantChance(variant.id, context) then
			variantId = variant.id
			break
		end
	end
	local minimum = context.minVariant or (if context.forceGolden then "Golden" else nil)
	if minimum and Variants.byId[variantId].order < Variants.byId[minimum].order then
		variantId = minimum
	end

	-- Size
	local sizeId = "Normal"
	if rng() < EggRoll.sizeChance("Titan", context) then
		sizeId = "Titan"
	elseif rng() < EggRoll.sizeChance("Big", context) then
		sizeId = "Big"
	end

	return { s = speciesId, v = variantId, z = sizeId }
end

return EggRoll
