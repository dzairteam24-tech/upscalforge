--!strict
-- The course: a long glowing lane, in stages. Each stage ends in a wall of cubes that only a fast enough runner
-- can smash. Distances are studs; the course runs along -Z, a stage's own measure `d` is how far along it you are.

local rgb = Color3.fromRGB

export type Theme = { name: string, accent: Color3, accent2: Color3, floor: Color3, sky: Color3 }

return {
	STAGES = 10,
	WIDTH = 34, -- the lane's width
	GAP = 16, -- between one stage's wall and the next stage's start
	START_PAD = 36, -- an empty run-up at the start of each stage
	END_PAD = 46, -- and an empty stretch before the wall
	WALL_THICK = 6, -- the wall of cubes
	WALL_HEIGHT = 24,
	-- a stage's themes, one after another (they go round)
	THEMES = {
		{ name = "Neon Grid", accent = rgb(0, 229, 255), accent2 = rgb(255, 64, 200), floor = rgb(10, 16, 30), sky = rgb(6, 10, 24) },
		{ name = "Candy", accent = rgb(255, 105, 180), accent2 = rgb(120, 255, 220), floor = rgb(30, 12, 28), sky = rgb(24, 8, 22) },
		{ name = "Solar", accent = rgb(255, 160, 40), accent2 = rgb(255, 230, 120), floor = rgb(30, 18, 8), sky = rgb(24, 12, 6) },
		{ name = "Toxic", accent = rgb(130, 255, 70), accent2 = rgb(0, 220, 190), floor = rgb(10, 26, 14), sky = rgb(6, 20, 10) },
		{ name = "Violet Void", accent = rgb(170, 90, 255), accent2 = rgb(80, 160, 255), floor = rgb(16, 10, 34), sky = rgb(10, 6, 26) },
		{ name = "Ice", accent = rgb(150, 225, 255), accent2 = rgb(255, 255, 255), floor = rgb(10, 22, 34), sky = rgb(8, 16, 28) },
		{ name = "Crimson", accent = rgb(255, 60, 90), accent2 = rgb(255, 150, 80), floor = rgb(32, 8, 14), sky = rgb(26, 6, 10) },
		{ name = "Emerald", accent = rgb(40, 235, 150), accent2 = rgb(200, 255, 120), floor = rgb(8, 28, 20), sky = rgb(6, 22, 16) },
		{ name = "Gold", accent = rgb(255, 210, 70), accent2 = rgb(255, 120, 60), floor = rgb(30, 24, 8), sky = rgb(24, 18, 6) },
		{ name = "Prism", accent = rgb(255, 255, 255), accent2 = rgb(200, 120, 255), floor = rgb(18, 18, 28), sky = rgb(12, 12, 22) },
	} :: { Theme },
}
