--!strict
-- The eggs, from the first tier to the Legendary Egg: their price in the Egg Shop, how long they incubate
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

local COMMON_TO_EPIC = { 0.6, 0.3, 0.09, 0.01 }

local list: { Egg } = {
	{ tier = 1, name = "Meadow Egg", color = rgb(123, 201, 111), price = 100, creatures = { "Cubby", "Kitty", "Bunny", "Bear" }, chances = COMMON_TO_EPIC },
	{ tier = 2, name = "Flower Egg", color = rgb(243, 166, 200), price = 1000, creatures = { "Bee", "Ladybug", "Butterfly", "Uni" }, chances = COMMON_TO_EPIC },
	{ tier = 3, name = "Forest Egg", color = rgb(78, 154, 91), price = 2500, creatures = { "Fox", "Owl", "Deer", "Sprout" }, chances = COMMON_TO_EPIC },
	{ tier = 4, name = "Beach Egg", color = rgb(242, 213, 138), price = 5000, creatures = { "Crab", "Turtle", "Dolphin", "Octopus" }, chances = COMMON_TO_EPIC },
	{ tier = 5, name = "Cave Egg", color = rgb(107, 78, 154), price = 11000, creatures = { "Mushroom", "Bat", "Glowworm", "Shade" }, chances = COMMON_TO_EPIC },
	{ tier = 6, name = "Desert Egg", color = rgb(232, 181, 98), price = 25000, creatures = { "Camel", "Scorpion", "Cactus", "Sphinx" }, chances = COMMON_TO_EPIC },
	{ tier = 7, name = "Snow Egg", color = rgb(221, 239, 252), price = 60000, creatures = { "Penguin", "Seal", "Snowman", "Yeti" }, chances = COMMON_TO_EPIC },
	{ tier = 8, name = "Volcano Egg", color = rgb(201, 71, 46), price = 150000, creatures = { "Imp", "Salamander", "Golem", "Phoenix" }, chances = COMMON_TO_EPIC },
	{ tier = 9, name = "Ice Egg", color = rgb(159, 216, 242), price = 400000, creatures = { "Ice Fox", "Narwhal", "Frost Owl", "Ice Dragon" }, chances = COMMON_TO_EPIC },
	{ tier = 10, name = "Pixel Egg", color = rgb(142, 91, 217), price = 1000000, creatures = { "Bot", "Byte", "Cursor", "King" }, chances = COMMON_TO_EPIC },
	{ tier = 11, name = "Legendary Egg", color = rgb(255, 200, 70), price = 5000000, creatures = { "Slime King", "Blossom Queen", "Elder Treant", "Kraken", "Spore Sage", "Pharaoh Scarab", "Aurora Wolf", "Inferno Drake", "Frost Leviathan", "Glitch" }, chances = { 0.3, 0.2, 0.14, 0.1, 0.08, 0.06, 0.05, 0.03, 0.02, 0.02 } },
}

return list
