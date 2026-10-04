--!strict
-- Item drops. Bigger sources and later zones drop better elixirs. `rng` returns a number in [0, 1).

local Items = require(script.Parent.Parent.Config.Items)

local Loot = {}

-- Drop chance and tier range per source kind.
local TABLE: { [string]: { chance: number, minTier: number, maxTier: number } } = {
	Pile = { chance = 0.002, minTier = 1, maxTier = 1 },
	Chest = { chance = 0.03, minTier = 1, maxTier = 1 },
	Safe = { chance = 0.12, minTier = 1, maxTier = 2 },
	Vault = { chance = 0.4, minTier = 2, maxTier = 3 },
	Big = { chance = 1, minTier = 2, maxTier = 3 },
	Guardian = { chance = 1, minTier = 3, maxTier = 4 },
}

-- Pixel elixirs are rarer than the others.
local FAMILY_WEIGHTS: { { id: string, weight: number } } = {
	{ id = "Coins", weight = 25 },
	{ id = "Power", weight = 25 },
	{ id = "Luck", weight = 20 },
	{ id = "Speed", weight = 10 },
	{ id = "Gem", weight = 10 },
	{ id = "Hunter", weight = 8 },
	{ id = "Pixel", weight = 2 },
}

function Loot.randomElixir(minTier: number, maxTier: number, rng: () -> number): string
	local total = 0
	for _, entry in FAMILY_WEIGHTS do
		total += entry.weight
	end
	local pick = rng() * total
	local family = FAMILY_WEIGHTS[1].id
	for _, entry in FAMILY_WEIGHTS do
		pick -= entry.weight
		if pick < 0 then
			family = entry.id
			break
		end
	end
	local span = maxTier - minTier + 1
	local tier = math.clamp(minTier + math.floor(rng() * span), 1, Items.MAX_TIER)
	return Items.elixirId(family, tier)
end

-- Every 4 zones adds one tier, so late zones drop stronger elixirs.
function Loot.zoneTierBonus(zoneId: number): number
	return math.floor(math.max(0, zoneId - 1) / 4)
end

-- Rolls a drop for a broken source. Returns an item id or nil.
function Loot.roll(sourceKind: string, zoneId: number, rng: () -> number, chanceMult: number?): string?
	local entry = TABLE[sourceKind]
	if not entry then
		return nil
	end
	if rng() >= math.min(1, entry.chance * (chanceMult or 1)) then
		return nil
	end
	local bonus = Loot.zoneTierBonus(zoneId)
	return Loot.randomElixir(
		math.min(Items.MAX_TIER, entry.minTier + bonus),
		math.min(Items.MAX_TIER, entry.maxTier + bonus),
		rng
	)
end

return Loot
