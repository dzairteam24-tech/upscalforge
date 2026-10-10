--!strict
-- The weather: it changes every few minutes, the same in every server (it follows the clock, Logic/Weather).
-- An egg that finishes incubating in a special weather hatches at least that weather's mutation.

export type Weather = { id: string, name: string, icon: string, weight: number, mutation: string?, color: Color3 }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

return {
	SECONDS = 600,
	LIST = {
		{ id = "Clear", name = "Clear Sky", icon = "☀️", weight = 55, color = rgb(255, 230, 150) },
		{ id = "Gold", name = "Golden Hour", icon = "🌅", weight = 20, mutation = "Golden", color = rgb(255, 200, 70) },
		{ id = "Frost", name = "Crystal Frost", icon = "❄️", weight = 13, mutation = "Crystal", color = rgb(120, 200, 255) },
		{ id = "Lava", name = "Lava Storm", icon = "🌋", weight = 8, mutation = "Lava", color = rgb(255, 110, 50) },
		{ id = "Neon", name = "Neon Night", icon = "🌌", weight = 4, mutation = "Neon", color = rgb(60, 230, 150) },
	} :: { Weather },
}
