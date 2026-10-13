--!strict
-- A gem found in the mine: its kind, size and mutation, how many backpack slots it takes, and what it sells for.
-- `random` is anything with NextNumber() (Roblox's Random, or a seeded stand-in in tests).

local Gems = require(script.Parent.Parent.Config.Gems)

export type Item = { g: string, s: string, m: string? }

local Gem = {}

-- Sizes: how often, slots taken in the backpack, what it sells for as a multiple
Gem.SIZES = {
	{ id = "Small", chance = 0.18, slots = 1, mult = 0.6 },
	{ id = "Normal", chance = 0.66, slots = 1, mult = 1 },
	{ id = "Big", chance = 0.14, slots = 2, mult = 2.5 },
	{ id = "Huge", chance = 0.02, slots = 4, mult = 6 },
}
-- Mutations (a gem has one or none), rarest last
Gem.MUTATIONS = {
	{ id = "Golden", chance = 0.03, mult = 3 },
	{ id = "Neon", chance = 0.01, mult = 6 },
	{ id = "Void", chance = 0.003, mult = 15 },
}

local sizeById: { [string]: any } = {}
for _, size in Gem.SIZES do
	sizeById[size.id] = size
end
local mutationById: { [string]: any } = {}
for _, mutation in Gem.MUTATIONS do
	mutationById[mutation.id] = mutation
end

-- Which gem kind a cube at this layer holds (nil if none belong there). Weighted by each gem's `weight`.
function Gem.pick(layer: number, random: any): string?
	local total = 0
	for _, gem in Gems.LIST do
		if layer >= gem.from and layer <= gem.to then
			total += gem.weight
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = random:NextNumber() * total
	for _, gem in Gems.LIST do
		if layer >= gem.from and layer <= gem.to then
			roll -= gem.weight
			if roll <= 0 then
				return gem.id
			end
		end
	end
	return nil
end

-- A new gem of this kind: its size and mutation by luck
function Gem.roll(kind: string, random: any): Item
	local size = "Normal"
	local roll = random:NextNumber()
	for _, option in Gem.SIZES do
		roll -= option.chance
		if roll <= 0 then
			size = option.id
			break
		end
	end
	local mutation: string? = nil
	for i = #Gem.MUTATIONS, 1, -1 do -- (rarest first, so a rare one isn't hidden by a common one)
		local option = Gem.MUTATIONS[i]
		if random:NextNumber() < option.chance then
			mutation = option.id
			break
		end
	end
	return { g = kind, s = size, m = mutation }
end

function Gem.slots(item: Item): number
	local size = sizeById[item.s]
	return if size then size.slots else 1
end

function Gem.value(item: Item): number
	local gem = Gems.byId[item.g]
	local size = sizeById[item.s]
	if not gem or not size then
		return 0
	end
	local mutation = if item.m then mutationById[item.m] else nil
	return math.max(1, math.floor(gem.value * size.mult * (if mutation then mutation.mult else 1) + 0.5))
end

-- "Golden Big Ruby"; a Normal one has no size word
function Gem.name(item: Item): string
	return (if item.m then item.m .. " " else "") .. (if item.s ~= "Normal" then item.s .. " " else "") .. item.g
end

-- Two gems that are the same (for grouping in the backpack)
function Gem.key(item: Item): string
	return item.g .. "|" .. item.s .. "|" .. (item.m or "")
end

function Gem.parseKey(key: string): Item
	local g, s, m = string.match(key, "^([^|]*)|([^|]*)|([^|]*)$")
	return { g = g or "", s = s or "Normal", m = if m and m ~= "" then m else nil }
end

return Gem
