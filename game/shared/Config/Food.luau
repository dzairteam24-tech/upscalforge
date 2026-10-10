--!strict
-- Food for the creatures (bought at the Food Shop in town, put in the trough in the pasture): while they're fed,
-- the creatures in the garden earn BOOST times their coins. Unfed, they earn as usual; food is a bonus, never a
-- chore. A food costs a share of what the boost earns (Logic/Food), so it always pays.

export type Food = { id: string, name: string, icon: string, minutes: number, min: number }

local LIST: { Food } = {
	{ id = "Hay", name = "Hay", icon = "🌾", minutes = 5, min = 300 },
	{ id = "Berries", name = "Berries", icon = "🫐", minutes = 15, min = 1500 },
	{ id = "GoldenApple", name = "Golden Apple", icon = "🍎", minutes = 60, min = 8000 },
}

local byId: { [string]: Food } = {}
for _, food in LIST do
	byId[food.id] = food
end

return {
	LIST = LIST,
	byId = byId,
	BOOST = 2, -- fed creatures earn this many times their coins
	SHARE = 0.3, -- a food costs this share of the extra coins it brings
	MAX_FED = 3 * 3600, -- feeding adds up, to at most this long ahead
}
