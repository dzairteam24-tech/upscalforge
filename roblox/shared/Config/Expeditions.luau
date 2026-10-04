--!strict
-- Expeditions: send creatures you aren't using on a timed trip. They come back with coins and items.
-- This keeps old and weak creatures useful (the "power creep" complaint from the research).

export type ExpeditionKind = {
	id: string,
	name: string,
	duration: number, -- seconds
	pets: number, -- creatures needed
	coinFactor: number, -- coins = total power x duration x factor
	elixirs: number,
	elixirTiers: { number }, -- min, max
	cartridgeChance: number,
	cartridgeTiers: { number },
	keyHalves: { { id: string, chance: number } },
	gemsPerZone: number,
	color: Color3,
}

local list: { ExpeditionKind } = {
	{
		id = "Short",
		name = "Forest Walk",
		duration = 30 * 60,
		pets = 3,
		coinFactor = 0.3,
		elixirs = 1,
		elixirTiers = { 1, 2 },
		cartridgeChance = 0,
		cartridgeTiers = { 1, 1 },
		keyHalves = {},
		gemsPerZone = 0,
		color = Color3.fromRGB(123, 201, 111),
	},
	{
		id = "Medium",
		name = "Mountain Trip",
		duration = 4 * 3600,
		pets = 5,
		coinFactor = 0.3,
		elixirs = 2,
		elixirTiers = { 2, 3 },
		cartridgeChance = 0.25,
		cartridgeTiers = { 1, 2 },
		keyHalves = { { id = "KeyHalf_Zone", chance = 0.5 }, { id = "KeyHalf_Golden", chance = 0.25 } },
		gemsPerZone = 10,
		color = Color3.fromRGB(91, 184, 245),
	},
	{
		id = "Long",
		name = "Volcano Expedition",
		duration = 12 * 3600,
		pets = 8,
		coinFactor = 0.3,
		elixirs = 2,
		elixirTiers = { 3, 4 },
		cartridgeChance = 0.6,
		cartridgeTiers = { 2, 3 },
		keyHalves = { { id = "KeyHalf_Titan", chance = 0.3 }, { id = "KeyHalf_Golden", chance = 0.4 } },
		gemsPerZone = 50,
		color = Color3.fromRGB(240, 100, 45),
	},
}

local byId: { [string]: ExpeditionKind } = {}
for _, kind in list do
	byId[kind.id] = kind
end

return {
	list = list,
	byId = byId,
	BASE_SLOTS = 2,
	MAX_SLOTS = 4,
	ELEMENT_BONUS = 1.5, -- all creatures share one strong element
}
