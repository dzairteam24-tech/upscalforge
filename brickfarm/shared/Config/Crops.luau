--!strict
-- The crops. Each one is a little model of bricks (Logic/CropModel builds it from `shape` and the colors), grows
-- for `grow` seconds once planted, and sells for `sell` coins each. `level`: the farm level that unlocks its seeds.
-- Each crop pays a little more a minute (a tile) than the one before; quick crops give the most XP a minute (they
-- level you up while you play), slow ones grow while you're away.

local rgb = Color3.fromRGB

export type Shape = "root" | "bush" | "stalk" | "vine" | "flower"
export type Crop = {
	key: string,
	name: string,
	level: number,
	grow: number, -- seconds
	seed: number, -- coins a seed
	sell: number, -- coins each
	yield: number, -- how many a harvest gives
	xp: number,
	shape: Shape,
	leaf: Color3,
	fruit: Color3,
}

local LEAF = rgb(75, 151, 75) -- the classic brick green
local DARK_LEAF = rgb(40, 127, 71)

local CROPS: { Crop } = {
	{ key = "carrot", name = "Carrot", level = 1, grow = 30, seed = 4, sell = 4, yield = 2, xp = 2, shape = "root", leaf = LEAF, fruit = rgb(218, 133, 65) },
	{ key = "radish", name = "Radish", level = 2, grow = 75, seed = 10, sell = 11, yield = 2, xp = 4, shape = "root", leaf = LEAF, fruit = rgb(196, 40, 28) },
	{ key = "tomato", name = "Tomato", level = 3, grow = 150, seed = 22, sell = 10, yield = 5, xp = 7, shape = "bush", leaf = DARK_LEAF, fruit = rgb(255, 60, 50) },
	{ key = "corn", name = "Corn", level = 4, grow = 300, seed = 50, sell = 36, yield = 3, xp = 12, shape = "stalk", leaf = LEAF, fruit = rgb(245, 205, 48) },
	{ key = "strawberry", name = "Strawberry", level = 6, grow = 600, seed = 100, sell = 28, yield = 8, xp = 20, shape = "bush", leaf = DARK_LEAF, fruit = rgb(230, 30, 80) },
	{ key = "pumpkin", name = "Pumpkin", level = 8, grow = 1200, seed = 220, sell = 500, yield = 1, xp = 34, shape = "vine", leaf = DARK_LEAF, fruit = rgb(255, 140, 26) },
	{ key = "sunflower", name = "Sunflower", level = 10, grow = 2400, seed = 450, sell = 360, yield = 3, xp = 55, shape = "flower", leaf = LEAF, fruit = rgb(255, 210, 40) },
	{ key = "watermelon", name = "Watermelon", level = 13, grow = 5400, seed = 1000, sell = 2530, yield = 1, xp = 95, shape = "vine", leaf = DARK_LEAF, fruit = rgb(52, 142, 64) },
	{ key = "pepper", name = "Pepper", level = 16, grow = 10800, seed = 2200, sell = 940, yield = 6, xp = 150, shape = "bush", leaf = DARK_LEAF, fruit = rgb(170, 0, 170) },
	{ key = "goldcorn", name = "Golden Corn", level = 20, grow = 28800, seed = 5000, sell = 5030, yield = 3, xp = 300, shape = "stalk", leaf = rgb(160, 132, 79), fruit = rgb(255, 215, 0) },
}

local byKey: { [string]: Crop } = {}
for _, crop in CROPS do
	byKey[crop.key] = crop
end

return {
	LIST = CROPS,
	byKey = byKey,
}
