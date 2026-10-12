--!strict
-- Eggs (Config/Eggs) and what hatches from them: how long an egg incubates, and the creature and mutation it
-- hatches into.

local EggSizes = require(script.Parent.Parent.Config.EggSizes)
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

-- The key an egg is kept under in a bag: its tier, and its size unless Normal ("1", "1_Big")
function Hatch.key(tier: number, size: string?): string
	return if size and size ~= "Normal" and EggSizes.byId[size] then ("%d_%s"):format(tier, size) else tostring(tier)
end

-- An egg key's tier and size (nil tier when it's no egg key)
function Hatch.parse(key: string): (number?, string)
	local tier, size = string.match(key, "^(%d+)_(%a+)$")
	if tier and EggSizes.byId[size] then
		return tonumber(tier), size
	end
	return tonumber(key), "Normal"
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

-- An egg's name with its size and gold: "✨ Golden Big Meadow Egg"
function Hatch.name(tier: number, size: string?, golden: boolean?): string
	local egg = byTier[tier]
	return ("%s%s%s"):format(if golden then "✨ Golden " else "", if size and size ~= "Normal" then size .. " " else "", if egg then egg.name else "Egg")
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
