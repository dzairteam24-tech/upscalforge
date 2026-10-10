--!strict
-- Cube Snap: Cubelings are cubes, so they snap together. Four of the same creature with the same mutation make a
-- Mega (bigger, earns more, guards better); four Megas of the same creature, whatever their mutations, make a
-- Rainbow, with the best mutation of the four. Logic/Snap finds what can snap.

export type Grade = { id: string, from: string, mult: number, guard: number, size: string }

local LIST: { Grade } = {
	-- from: the grade it's made of ("" = a plain hatched creature)
	{ id = "Mega", from = "", mult = 5, guard = 2, size = "Big" },
	{ id = "Rainbow", from = "Mega", mult = 25, guard = 4, size = "Huge" },
}

local byId: { [string]: Grade } = {}
for _, grade in LIST do
	byId[grade.id] = grade
end

return {
	LIST = LIST,
	byId = byId,
	NEED = 4, -- creatures that snap into one
}
