--!strict
-- Eggs (Config/Eggs) and what hatches from them: how long an egg incubates, and the creature and mutation it
-- hatches into.

local Creatures = require(script.Parent.Parent.Config.Creatures)
local EggSizes = require(script.Parent.Parent.Config.EggSizes)
local Mystery = require(script.Parent.Parent.Config.Mystery)
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

-- An egg's size (Config/EggSizes), Normal when unknown
function Hatch.size(id: string?): EggSizes.Size
	return EggSizes.byId[id or "Normal"] or EggSizes.byId.Normal
end

-- The key an egg is kept under in a bag: its tier, its size unless Normal, and the creature in it when it's
-- known (a Wild egg shows it: "1", "1_Big", "1@Cat", "1_Huge@Bear")
function Hatch.key(tier: number, size: string?, species: string?): string
	local key = if size and size ~= "Normal" and EggSizes.byId[size] then ("%d_%s"):format(tier, size) else tostring(tier)
	return if species and Hatch.known(species) then key .. "@" .. species else key
end

-- Whether this can be what an egg shows: a creature, or the Mystery Egg's mystery (Config/Mystery)
function Hatch.known(species: string): boolean
	return Creatures.byId[species] ~= nil or species == Mystery.ID
end

-- An egg key's tier, size and creature (nil tier when it's no egg key; nil creature when it's not known: it's
-- rolled when it hatches)
function Hatch.parse(key: string): (number?, string, string?)
	local base, species = string.match(key, "^([^@]+)@(%a+)$")
	if base and not Hatch.known(species) then
		return nil, "Normal", nil
	end
	base = base or key
	local tier, size = string.match(base, "^(%d+)_(%a+)$")
	if tier and EggSizes.byId[size] then
		return tonumber(tier), size, species
	end
	return tonumber(base), "Normal", species
end

-- The creature in an egg of this tier, by luck (its chances, Config/Eggs): a Wild egg's is known from the
-- start, and shows on it (Shared/EggModel)
function Hatch.species(tier: number, random: () -> number): string
	local egg = byTier[tier]
	assert(egg, "no egg of tier " .. tostring(tier))
	local roll = random()
	for i, chance in egg.chances do
		if roll < chance then
			return egg.creatures[i]
		end
		roll -= chance
	end
	return egg.creatures[#egg.creatures]
end

-- The keys of the eggs held in a bag (key -> count), the best first: by tier, then by size
function Hatch.sortedKeys(bag: { [string]: number }?): { string }
	local keys: { string } = {}
	for key, count in bag or {} do
		if count > 0 and Hatch.parse(key) then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(a, b)
		local ta, sa = Hatch.parse(a)
		local tb, sb = Hatch.parse(b)
		if ta ~= tb then
			return (ta or 0) > (tb or 0)
		end
		return Hatch.size(sa).weight > Hatch.size(sb).weight
	end)
	return keys
end

-- A Mystery Egg's reward, by luck (Config/Mystery)
function Hatch.mysteryReward(random: () -> number): Mystery.Reward
	local total = 0
	for _, reward in Mystery.REWARDS do
		total += reward.weight
	end
	local roll = random() * total
	for _, reward in Mystery.REWARDS do
		if roll < reward.weight then
			return reward
		end
		roll -= reward.weight
	end
	return Mystery.REWARDS[#Mystery.REWARDS]
end

-- One of a tier's creatures of a rarity, by luck (nil when it has none)
function Hatch.ofRarity(tier: number, rarity: string, random: () -> number): string?
	local egg = byTier[tier]
	local found: { string } = {}
	for _, id in (if egg then egg.creatures else {}) do
		local creature = Creatures.byId[id]
		if creature and creature.rarity == rarity then
			table.insert(found, id)
		end
	end
	return if #found > 0 then found[math.clamp(math.floor(random() * #found) + 1, 1, #found)] else nil
end

-- A size, by luck (random gives numbers in [0, 1))
function Hatch.rollSize(random: () -> number): string
	local roll = random()
	for _, size in EggSizes.LIST do
		if roll < size.chance then
			return size.id
		end
		roll -= size.chance
	end
	return "Normal"
end

-- An egg's name with its size, gold and creature: "✨ Golden Big Meadow Egg", "Big Cat Egg"
function Hatch.name(tier: number, size: string?, golden: boolean?, species: string?): string
	local egg = byTier[tier]
	local what = if species then species .. " Egg" elseif egg then egg.name else "Egg" -- ("Mystery Egg" too)
	return ("%s%s%s"):format(if golden then "✨ Golden " else "", if size and size ~= "Normal" then size .. " " else "", what)
end

-- Whether an egg's map is open yet (Config/Island OPEN_TIER); the others are Coming Soon
function Hatch.open(tier: number): boolean
	return tier <= IslandConfig.OPEN_TIER
end

-- Seconds an egg incubates in a nest on the ground: 1 minute for tier 1, about 30 minutes for tier 10, an hour
-- for the Legendary
function Hatch.seconds(tier: number): number
	local times = IslandConfig.HATCH_SECONDS
	return times[math.clamp(tier, 1, #times)]
end

-- Whether a slot is an incubator (a machine at the back of the garden) rather than a nest on the ground
function Hatch.isMachine(slot: number): boolean
	return slot > IslandConfig.MACHINE_SLOT
end

-- Seconds an egg takes in a given slot: half as long in an incubator
function Hatch.secondsIn(tier: number, slot: number): number
	local seconds = Hatch.seconds(tier)
	return if Hatch.isMachine(slot) then math.floor(seconds / IslandConfig.MACHINE_SPEED) else seconds
end

-- The creature and mutation an egg hatches into. `random` gives numbers in [0, 1); `atLeast` is the weather's
-- mutation, which the hatch can't be below.
function Hatch.roll(tier: number, random: () -> number, atLeast: string?, species: string?): (string, string)
	-- (the creature: the one the egg showed, else by luck)
	local creature = if species and Creatures.byId[species] then species else Hatch.species(tier, random)
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

-- The better of two least mutations (the weather's, a Golden Egg's), either of which may be nil
function Hatch.atLeast(a: string?, b: string?): string?
	if not a or not Mutations.byId[a] then
		return b
	end
	if not b or not Mutations.byId[b] then
		return a
	end
	return if Mutations.byId[a].order >= Mutations.byId[b].order then a else b
end

return Hatch
