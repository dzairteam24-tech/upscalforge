--!strict
-- A creature's mutation: how much more it earns, how often it hatches by itself, and its color. The weather
-- (Config/Weather) can make an egg hatch at least a given mutation.

export type Mutation = { id: string, order: number, mult: number, chance: number, color: Color3 }

local list: { Mutation } = {
	{ id = "Normal", order = 1, mult = 1, chance = 0, color = Color3.fromRGB(150, 156, 170) },
	{ id = "Golden", order = 2, mult = 1.5, chance = 1 / 50, color = Color3.fromRGB(245, 197, 66) },
	{ id = "Crystal", order = 3, mult = 2.5, chance = 1 / 250, color = Color3.fromRGB(120, 200, 245) },
	{ id = "Lava", order = 4, mult = 4, chance = 1 / 1000, color = Color3.fromRGB(240, 100, 45) },
	{ id = "Neon", order = 5, mult = 6, chance = 1 / 5000, color = Color3.fromRGB(43, 230, 150) },
}

local byId: { [string]: Mutation } = {}
for _, mutation in list do
	byId[mutation.id] = mutation
end

return { list = list, byId = byId }
