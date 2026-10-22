--!strict
-- Every creature (its look: art/models, Config/CreatureLooks): its egg tier, how rare it is in that egg, and
-- how many coins a second it earns when it lives on its owner's island (before its mutation).

export type Creature = {
	id: string,
	tier: number, -- the egg it hatches from (Config/Eggs)
	rarity: string, -- Common, Uncommon, Rare, Epic, Legendary, Mythic
	earn: number, -- coins a second on the island
	color: Color3, -- the block stand-in's color (without the 3D models)
	top: string, -- the block stand-in's top piece
	face: string, -- and its face
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local list: { Creature } = {
	{ id = "Dog", tier = 1, rarity = "Common", earn = 4, color = rgb(224, 165, 92), top = "round", face = "round" },
	{ id = "Cat", tier = 1, rarity = "Uncommon", earn = 14, color = rgb(245, 154, 60), top = "cat", face = "happy" },
	{ id = "Bunny", tier = 1, rarity = "Rare", earn = 56, color = rgb(240, 240, 245), top = "bunny", face = "round" },
	{ id = "Bear", tier = 1, rarity = "Epic", earn = 230, color = rgb(168, 117, 79), top = "round", face = "round" },
	-- (Meadow has eight, as Steal an Egg's maps do: two of each rarity)
	{ id = "Chicken", tier = 1, rarity = "Common", earn = 5, color = rgb(250, 250, 245), top = "flame", face = "round" },
	{ id = "Pig", tier = 1, rarity = "Uncommon", earn = 16, color = rgb(255, 168, 188), top = "round", face = "happy" },
	{ id = "Sheep", tier = 1, rarity = "Rare", earn = 64, color = rgb(244, 242, 236), top = "round", face = "sleepy" },
	{ id = "Horse", tier = 1, rarity = "Epic", earn = 260, color = rgb(160, 88, 46), top = "cat", face = "round" },
	-- Flower (tier 2): the garden's small things first, the fox and the deer last (the deer guards the Wild's)
	{ id = "Bee", tier = 2, rarity = "Common", earn = 20, color = rgb(245, 197, 66), top = "antenna", face = "happy" },
	{ id = "Ladybug", tier = 2, rarity = "Common", earn = 25, color = rgb(220, 60, 50), top = "antenna", face = "round" },
	{ id = "Butterfly", tier = 2, rarity = "Uncommon", earn = 70, color = rgb(150, 110, 220), top = "antenna", face = "happy" },
	{ id = "Snail", tier = 2, rarity = "Uncommon", earn = 80, color = rgb(130, 200, 110), top = "antenna", face = "sleepy" },
	{ id = "Frog", tier = 2, rarity = "Rare", earn = 280, color = rgb(90, 190, 90), top = "round", face = "happy" },
	{ id = "Duckling", tier = 2, rarity = "Rare", earn = 320, color = rgb(250, 210, 70), top = "round", face = "round" },
	{ id = "Fox", tier = 2, rarity = "Epic", earn = 1150, color = rgb(235, 120, 50), top = "cat", face = "angry" },
	{ id = "Deer", tier = 2, rarity = "Epic", earn = 1300, color = rgb(190, 140, 90), top = "horns", face = "round" },
	-- Forest (tier 3): climbers and prowlers of the deep woods, the stag last (it guards the Wild's)
	{ id = "Squirrel", tier = 3, rarity = "Common", earn = 100, color = rgb(200, 120, 60), top = "cat", face = "happy" },
	{ id = "Hedgehog", tier = 3, rarity = "Common", earn = 125, color = rgb(140, 100, 70), top = "round", face = "round" },
	{ id = "Owl", tier = 3, rarity = "Uncommon", earn = 350, color = rgb(120, 85, 55), top = "cat", face = "round" },
	{ id = "Raccoon", tier = 3, rarity = "Uncommon", earn = 400, color = rgb(150, 150, 155), top = "cat", face = "shades" },
	{ id = "Wolf", tier = 3, rarity = "Rare", earn = 1400, color = rgb(130, 135, 145), top = "cat", face = "angry" },
	{ id = "Moose", tier = 3, rarity = "Rare", earn = 1600, color = rgb(120, 85, 60), top = "horns", face = "round" },
	{ id = "Lynx", tier = 3, rarity = "Epic", earn = 5750, color = rgb(210, 170, 120), top = "cat", face = "angry" },
	{ id = "Stag", tier = 3, rarity = "Epic", earn = 6500, color = rgb(150, 100, 65), top = "horns", face = "round" },
	-- Beach (tier 4): shore things first, the great whale last (it guards the Wild's)
	{ id = "Crab", tier = 4, rarity = "Common", earn = 500, color = rgb(230, 80, 60), top = "antenna", face = "angry" },
	{ id = "Starfish", tier = 4, rarity = "Common", earn = 625, color = rgb(245, 150, 80), top = "round", face = "happy" },
	{ id = "Turtle", tier = 4, rarity = "Uncommon", earn = 1750, color = rgb(90, 170, 110), top = "round", face = "sleepy" },
	{ id = "Seagull", tier = 4, rarity = "Uncommon", earn = 2000, color = rgb(240, 240, 245), top = "round", face = "round" },
	{ id = "Octopus", tier = 4, rarity = "Rare", earn = 7000, color = rgb(200, 110, 180), top = "round", face = "happy" },
	{ id = "Dolphin", tier = 4, rarity = "Rare", earn = 8000, color = rgb(110, 170, 220), top = "flame", face = "happy" },
	{ id = "Shark", tier = 4, rarity = "Epic", earn = 28750, color = rgb(120, 150, 180), top = "flame", face = "angry" },
	{ id = "Whale", tier = 4, rarity = "Epic", earn = 32500, color = rgb(80, 120, 200), top = "round", face = "round" },
}

local byId: { [string]: Creature } = {}
for _, creature in list do
	byId[creature.id] = creature
end

return {
	list = list,
	byId = byId,
}
