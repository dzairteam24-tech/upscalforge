--!strict
-- Items the player can hold. Earned in game only, never sold.
-- Elixirs give a timed boost. 3 of the same tier merge into the next tier, and the Mixer combines
-- two different elixirs of the same tier into a double elixir.

export type BoostStat = string -- "Coins" | "Power" | "Luck" | "Speed" | "Pixel" | "Gem" | "Hunter"

export type Item = {
	id: string,
	name: string,
	kind: string, -- "Elixir"
	tier: number,
	family: string, -- elixir family, e.g. "Coins" or "Fortune"
	boosts: { { stat: BoostStat, mult: number } },
	duration: number, -- seconds
	color: Color3,
	description: string,
}

local ROMAN = { "I", "II", "III", "IV", "V" }
local MAX_TIER = #ROMAN

type Family = {
	id: string,
	label: string,
	stats: { BoostStat },
	mults: { { number } }, -- per stat, per tier
	duration: number,
	color: Color3,
	verb: string,
}

-- Base families: one stat each.
local BASE: { Family } = {
	{
		id = "Coins",
		label = "Coin Elixir",
		stats = { "Coins" },
		mults = { { 1.5, 1.75, 2, 2.5, 3 } },
		duration = 600,
		color = Color3.fromRGB(245, 197, 66),
		verb = "coins",
	},
	{
		id = "Power",
		label = "Power Elixir",
		stats = { "Power" },
		mults = { { 1.5, 1.75, 2, 2.5, 3 } },
		duration = 600,
		color = Color3.fromRGB(229, 83, 75),
		verb = "team power",
	},
	{
		id = "Luck",
		label = "Luck Elixir",
		stats = { "Luck" },
		mults = { { 1.5, 1.75, 2, 2.5, 3 } },
		duration = 600,
		color = Color3.fromRGB(80, 200, 120),
		verb = "hatch luck",
	},
	{
		id = "Speed",
		label = "Speed Elixir",
		stats = { "Speed" },
		mults = { { 1.25, 1.4, 1.55, 1.75, 2 } },
		duration = 600,
		color = Color3.fromRGB(91, 184, 245),
		verb = "walk speed",
	},
	{
		id = "Pixel",
		label = "Pixel Elixir",
		stats = { "Pixel" },
		mults = { { 2, 2.75, 3.5, 4.25, 5 } },
		duration = 300,
		color = Color3.fromRGB(142, 91, 217),
		verb = "Pixel chance",
	},
	{
		id = "Gem",
		label = "Gem Elixir",
		stats = { "Gem" },
		mults = { { 2, 2.5, 3, 3.5, 4 } },
		duration = 600,
		color = Color3.fromRGB(120, 220, 255),
		verb = "gem drops",
	},
	{
		id = "Hunter",
		label = "Hunter Elixir",
		stats = { "Hunter" },
		mults = { { 2, 2.5, 3, 3.5, 4 } },
		duration = 600,
		color = Color3.fromRGB(240, 138, 45),
		verb = "Big appearances",
	},
}

-- Mixer recipes: two base families -> a double family.
local MIXES = {
	{ id = "Fortune", label = "Fortune Elixir", a = "Coins", b = "Luck", color = Color3.fromRGB(200, 220, 90) },
	{ id = "Rush", label = "Rush Elixir", a = "Power", b = "Speed", color = Color3.fromRGB(240, 120, 200) },
	{ id = "Rainbow", label = "Rainbow Elixir", a = "Luck", b = "Pixel", color = Color3.fromRGB(255, 140, 220) },
}

local byId: { [string]: Item } = {}
local list: { Item } = {}
local familyById: { [string]: Family } = {}

local function itemId(family: string, tier: number): string
	return ("Elixir_%s_%d"):format(family, tier)
end

local function register(family: Family)
	familyById[family.id] = family
	for tier = 1, MAX_TIER do
		local boosts = {}
		local parts = {}
		for i, stat in family.stats do
			local mult = family.mults[i][tier]
			table.insert(boosts, { stat = stat, mult = mult })
			table.insert(parts, ("x%g %s"):format(mult, stat))
		end
		local item: Item = {
			id = itemId(family.id, tier),
			name = ("%s %s"):format(family.label, ROMAN[tier]),
			kind = "Elixir",
			tier = tier,
			family = family.id,
			boosts = boosts,
			duration = family.duration,
			color = family.color,
			description = ("%s for %d min"):format(table.concat(parts, " + "), family.duration // 60),
		}
		byId[item.id] = item
		table.insert(list, item)
	end
end

for _, family in BASE do
	register(family)
end
for _, mix in MIXES do
	local a, b = familyById[mix.a], familyById[mix.b]
	register({
		id = mix.id,
		label = mix.label,
		stats = { a.stats[1], b.stats[1] },
		mults = { a.mults[1], b.mults[1] },
		duration = math.min(a.duration, b.duration),
		color = mix.color,
		verb = a.verb .. " and " .. b.verb,
	})
end

local Items = {
	list = list,
	byId = byId,
	MAX_TIER = MAX_TIER,
	MERGE_COST = 3,
	BOOST_CAP_SECONDS = 4 * 3600,
	baseFamilies = BASE,
}

function Items.elixirId(family: string, tier: number): string
	return itemId(family, tier)
end

-- Id of the next tier, or nil at max tier.
function Items.nextTier(id: string): string?
	local item = byId[id]
	if not item or item.tier >= MAX_TIER then
		return nil
	end
	return itemId(item.family, item.tier + 1)
end

-- Mixer result for two elixir ids (order doesn't matter), or nil.
function Items.mixResult(a: string, b: string): string?
	local ia, ib = byId[a], byId[b]
	if not ia or not ib or ia.tier ~= ib.tier then
		return nil
	end
	for _, mix in MIXES do
		if (ia.family == mix.a and ib.family == mix.b) or (ia.family == mix.b and ib.family == mix.a) then
			return itemId(mix.id, ia.tier)
		end
	end
	return nil
end

return Items
