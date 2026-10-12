--!strict
-- The eggs, from the first tier to the Legendary Egg: their price in the Sell Shop, how long they incubate
-- (Logic/Hatch) and what hatches from them, with each creature's chance.

export type Egg = {
	tier: number,
	name: string,
	color: Color3,
	price: number,
	creatures: { string },
	chances: { number }, -- adding up to 1
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Only Meadow has its creatures so far (the new blocky animals); the other eggs are Coming Soon (empty until
-- their animals are designed: Config/Island OPEN_TIER).
-- (eight creatures, two of each rarity: Common, Common, Uncommon, Uncommon, Rare, Rare, Epic, Epic)
local EIGHT = { 0.32, 0.28, 0.16, 0.14, 0.05, 0.04, 0.006, 0.004 }

local list: { Egg } = {
	{ tier = 1, name = "Meadow Egg", color = rgb(123, 201, 111), price = 500, creatures = { "Dog", "Chicken", "Cat", "Pig", "Bunny", "Sheep", "Bear", "Horse" }, chances = EIGHT },
	{ tier = 2, name = "Flower Egg", color = rgb(243, 166, 200), price = 5000, creatures = {}, chances = {} },
	{ tier = 3, name = "Forest Egg", color = rgb(78, 154, 91), price = 50000, creatures = {}, chances = {} },
	{ tier = 4, name = "Beach Egg", color = rgb(242, 213, 138), price = 500000, creatures = {}, chances = {} },
	{ tier = 5, name = "Cave Egg", color = rgb(107, 78, 154), price = 5000000, creatures = {}, chances = {} },
	{ tier = 6, name = "Desert Egg", color = rgb(232, 181, 98), price = 50000000, creatures = {}, chances = {} },
	{ tier = 7, name = "Snow Egg", color = rgb(221, 239, 252), price = 500000000, creatures = {}, chances = {} },
	{ tier = 8, name = "Volcano Egg", color = rgb(201, 71, 46), price = 5000000000, creatures = {}, chances = {} },
	{ tier = 9, name = "Ice Egg", color = rgb(159, 216, 242), price = 50000000000, creatures = {}, chances = {} },
	{ tier = 10, name = "Pixel Egg", color = rgb(142, 91, 217), price = 500000000000, creatures = {}, chances = {} },
	{ tier = 11, name = "Legendary Egg", color = rgb(255, 200, 70), price = 2000000000000, creatures = {}, chances = {} },
}

return list
