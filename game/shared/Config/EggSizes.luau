--!strict
-- How big an egg is (rolled by luck every time a Wild nest fills up again, Logic/Hatch.rollSize). A heavier egg
-- slows its thief down while they carry it (carry: times their carrying speed) but hatches into a bigger creature
-- that earns more (creature: its size, Config/Snap's or PetModel's; mult: times its coins). An egg in a bag is
-- kept by tier and size (Logic/Hatch.key: "1" a Normal Meadow Egg, "1_Big" a Big one).

export type Size = { id: string, chance: number, weight: number, carry: number, scale: number, creature: string, mult: number }

local LIST: { Size } = {
	{ id = "Small", chance = 0.30, weight = 0.5, carry = 1, scale = 0.75, creature = "Small", mult = 0.7 },
	{ id = "Normal", chance = 0.45, weight = 1, carry = 1, scale = 1, creature = "Normal", mult = 1 },
	{ id = "Big", chance = 0.19, weight = 2, carry = 0.85, scale = 1.3, creature = "Big", mult = 2 },
	{ id = "Huge", chance = 0.06, weight = 4, carry = 0.7, scale = 1.65, creature = "Huge", mult = 4 }, -- (rare)
}

local byId: { [string]: Size } = {}
for _, size in LIST do
	byId[size.id] = size
end

return {
	LIST = LIST,
	byId = byId,
}
