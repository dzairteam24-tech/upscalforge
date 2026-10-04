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

---------------------------------------------------------------------------------------------------------------
-- Cartridges

local CARTRIDGE_TABLE: { [string]: { chance: number, minTier: number, maxTier: number } } = {
	Safe = { chance = 0.01, minTier = 1, maxTier = 1 },
	Vault = { chance = 0.05, minTier = 1, maxTier = 2 },
	Big = { chance = 0.2, minTier = 1, maxTier = 2 },
	Guardian = { chance = 0.6, minTier = 2, maxTier = 3 },
}
local RARE_CARTRIDGE_SHARE = 0.03

function Loot.randomCartridge(minTier: number, maxTier: number, rng: () -> number): string
	local families = Items.cartridgeFamilies
	local rare, normal = {}, {}
	for _, family in families do
		table.insert(if family.rare then rare else normal, family)
	end
	if rng() < RARE_CARTRIDGE_SHARE and #rare > 0 then
		local family = rare[1 + math.floor(rng() * #rare)]
		return Items.cartridgeId(family.id, 1)
	end
	local family = normal[1 + math.floor(rng() * #normal)]
	local span = maxTier - minTier + 1
	local tier = math.clamp(minTier + math.floor(rng() * span), 1, #family.values)
	return Items.cartridgeId(family.id, tier)
end

function Loot.rollCartridge(sourceKind: string, zoneId: number, rng: () -> number): string?
	local entry = CARTRIDGE_TABLE[sourceKind]
	if not entry or rng() >= entry.chance then
		return nil
	end
	local bonus = Loot.zoneTierBonus(zoneId)
	return Loot.randomCartridge(
		math.min(Items.MAX_TIER, entry.minTier + bonus),
		math.min(Items.MAX_TIER, entry.maxTier + bonus),
		rng
	)
end

---------------------------------------------------------------------------------------------------------------
-- Key halves

local KEY_HALVES: { [string]: { { id: string, chance: number } } } = {
	Chest = { { id = "KeyHalf_Zone", chance = 0.02 } },
	Safe = { { id = "KeyHalf_Zone", chance = 0.06 }, { id = "KeyHalf_Golden", chance = 0.03 } },
	Vault = { { id = "KeyHalf_Zone", chance = 0.15 }, { id = "KeyHalf_Golden", chance = 0.08 } },
	Big = { { id = "KeyHalf_Golden", chance = 0.1 }, { id = "KeyHalf_Titan", chance = 0.25 } },
	Guardian = { { id = "KeyHalf_Titan", chance = 0.5 } },
}

-- Every key half that drops (each one rolls on its own).
function Loot.rollKeyHalves(sourceKind: string, rng: () -> number): { string }
	local out = {}
	local entries = KEY_HALVES[sourceKind]
	if not entries then
		return out
	end
	for _, entry in entries do
		if rng() < entry.chance then
			table.insert(out, entry.id)
		end
	end
	return out
end

-- Everything a broken source drops: elixir, cartridge and key halves.
function Loot.rollAll(sourceKind: string, zoneId: number, rng: () -> number): { string }
	local drops = {}
	local elixir = Loot.roll(sourceKind, zoneId, rng)
	if elixir then
		table.insert(drops, elixir)
	end
	local cartridge = Loot.rollCartridge(sourceKind, zoneId, rng)
	if cartridge then
		table.insert(drops, cartridge)
	end
	for _, half in Loot.rollKeyHalves(sourceKind, rng) do
		table.insert(drops, half)
	end
	return drops
end

return Loot
