--!strict
-- The Nest: each player's island next to the town, with incubators that hatch eggs in real time (even while
-- the player is away), and the weather that colors what hatches. Logic/Nest has the math; NestService runs it.

export type Weather = {
	id: string,
	name: string,
	icon: string,
	weight: number, -- how often it comes, out of the weights' total
	minVariant: string?, -- eggs that finish incubating in this weather hatch at least this variant
	color: Color3,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

return {
	PLOTS = 8, -- islands in the Nest field, one per player (a server holds 8)
	SLOTS_START = 3, -- incubators a new player has
	-- Coins for the 4th, 5th... incubator
	SLOT_PRICES = { 25000, 250000, 2500000, 25000000, 250000000 },
	PRICE_MULT = 4, -- a nest egg costs this many times the zone's egg...
	LUCK = 3, -- ...and hatches with this much more luck
	BASE_SECONDS = 90, -- a zone 1 egg incubates this long; later zones longer (Logic/Nest)
	WEATHER_SECONDS = 600, -- the weather changes this often (the same for every server: it follows the clock)
	WEATHERS = {
		{ id = "Clear", name = "Clear Sky", icon = "☀️", weight = 55, color = rgb(255, 230, 150) },
		{ id = "Gold", name = "Golden Hour", icon = "🌅", weight = 20, minVariant = "Golden", color = rgb(255, 200, 70) },
		{ id = "Frost", name = "Crystal Frost", icon = "❄️", weight = 13, minVariant = "Crystal", color = rgb(120, 200, 255) },
		{ id = "Lava", name = "Lava Storm", icon = "🌋", weight = 8, minVariant = "Lava", color = rgb(255, 110, 50) },
		{ id = "Neon", name = "Neon Night", icon = "🌌", weight = 4, minVariant = "Neon", color = rgb(60, 230, 150) },
	} :: { Weather },
}
