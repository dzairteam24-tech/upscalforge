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
	-- Cave (tier 5): things that live in the dark first, the dragon last (it guards the Wild's)
	{ id = "Bat", tier = 5, rarity = "Common", earn = 2500, color = rgb(105, 85, 140), top = "cat", face = "angry" },
	{ id = "Mole", tier = 5, rarity = "Common", earn = 3125, color = rgb(120, 90, 70), top = "round", face = "sleepy" },
	{ id = "Spider", tier = 5, rarity = "Uncommon", earn = 8750, color = rgb(60, 55, 70), top = "round", face = "angry" },
	{ id = "Newt", tier = 5, rarity = "Uncommon", earn = 10000, color = rgb(230, 130, 60), top = "round", face = "happy" },
	{ id = "Scorpion", tier = 5, rarity = "Rare", earn = 35000, color = rgb(180, 90, 50), top = "antenna", face = "angry" },
	{ id = "Panther", tier = 5, rarity = "Rare", earn = 40000, color = rgb(45, 45, 55), top = "cat", face = "angry" },
	{ id = "Golem", tier = 5, rarity = "Epic", earn = 143750, color = rgb(130, 125, 120), top = "round", face = "square" },
	{ id = "Dragon", tier = 5, rarity = "Epic", earn = 162500, color = rgb(90, 160, 80), top = "horns", face = "angry" },
	-- Desert (tier 6): sand dwellers first, Anubis last (it guards the Wild's)
	{ id = "Camel", tier = 6, rarity = "Common", earn = 12500, color = rgb(210, 170, 105), top = "round", face = "sleepy" },
	{ id = "Meerkat", tier = 6, rarity = "Common", earn = 15625, color = rgb(195, 160, 110), top = "cat", face = "round" },
	{ id = "Fennec", tier = 6, rarity = "Uncommon", earn = 43750, color = rgb(240, 215, 160), top = "cat", face = "happy" },
	{ id = "Vulture", tier = 6, rarity = "Uncommon", earn = 50000, color = rgb(90, 80, 85), top = "round", face = "angry" },
	{ id = "Cobra", tier = 6, rarity = "Rare", earn = 175000, color = rgb(190, 160, 80), top = "round", face = "angry" },
	{ id = "Hyena", tier = 6, rarity = "Rare", earn = 200000, color = rgb(170, 145, 110), top = "round", face = "happy" },
	{ id = "Lion", tier = 6, rarity = "Epic", earn = 718750, color = rgb(215, 160, 70), top = "round", face = "round" },
	{ id = "Anubis", tier = 6, rarity = "Epic", earn = 812500, color = rgb(50, 45, 60), top = "cat", face = "angry" },
	-- Snow (tier 7): the small and the round first, the yeti last (it guards the Wild's)
	{ id = "Lemming", tier = 7, rarity = "Common", earn = 62500, color = rgb(180, 130, 85), top = "round", face = "happy" },
	{ id = "Penguin", tier = 7, rarity = "Common", earn = 78125, color = rgb(60, 65, 80), top = "round", face = "round" },
	{ id = "Seal", tier = 7, rarity = "Uncommon", earn = 218750, color = rgb(160, 170, 180), top = "round", face = "happy" },
	{ id = "Hare", tier = 7, rarity = "Uncommon", earn = 250000, color = rgb(235, 238, 242), top = "bunny", face = "round" },
	{ id = "Yak", tier = 7, rarity = "Rare", earn = 875000, color = rgb(110, 80, 60), top = "horns", face = "sleepy" },
	{ id = "Walrus", tier = 7, rarity = "Rare", earn = 1000000, color = rgb(165, 120, 90), top = "round", face = "sleepy" },
	{ id = "Narwhal", tier = 7, rarity = "Epic", earn = 3593750, color = rgb(170, 185, 200), top = "unihorn", face = "round" },
	{ id = "Yeti", tier = 7, rarity = "Epic", earn = 4062500, color = rgb(240, 242, 245), top = "round", face = "angry" },
	-- Volcano (tier 8): lizards and crawlers first, the hydra last (it guards the Wild's)
	{ id = "Gecko", tier = 8, rarity = "Common", earn = 312500, color = rgb(120, 200, 90), top = "round", face = "happy" },
	{ id = "Iguana", tier = 8, rarity = "Common", earn = 390625, color = rgb(95, 160, 95), top = "flame", face = "round" },
	{ id = "Beetle", tier = 8, rarity = "Uncommon", earn = 1093750, color = rgb(70, 60, 90), top = "antenna", face = "angry" },
	{ id = "Salamander", tier = 8, rarity = "Uncommon", earn = 1250000, color = rgb(240, 110, 50), top = "flame", face = "round" },
	{ id = "Phoenix", tier = 8, rarity = "Rare", earn = 4375000, color = rgb(250, 140, 40), top = "flame", face = "round" },
	{ id = "Cerberus", tier = 8, rarity = "Rare", earn = 5000000, color = rgb(150, 70, 50), top = "cat", face = "angry" },
	{ id = "Basilisk", tier = 8, rarity = "Epic", earn = 17968750, color = rgb(80, 140, 70), top = "flame", face = "angry" },
	{ id = "Hydra", tier = 8, rarity = "Epic", earn = 20312500, color = rgb(70, 130, 160), top = "horns", face = "angry" },
	-- Ice (tier 9): an Egg Shop egg with no biome of its own; the frozen north's beasts, the frost dragon last
	{ id = "Puffin", tier = 9, rarity = "Common", earn = 1562500, color = rgb(55, 55, 65), top = "round", face = "round" },
	{ id = "Otter", tier = 9, rarity = "Common", earn = 1953125, color = rgb(130, 90, 60), top = "round", face = "happy" },
	{ id = "SnowLeopard", tier = 9, rarity = "Uncommon", earn = 5468750, color = rgb(225, 228, 230), top = "cat", face = "round" },
	{ id = "PolarBear", tier = 9, rarity = "Uncommon", earn = 6250000, color = rgb(245, 245, 240), top = "round", face = "round" },
	{ id = "Sabertooth", tier = 9, rarity = "Rare", earn = 21875000, color = rgb(215, 175, 110), top = "cat", face = "angry" },
	{ id = "Mammoth", tier = 9, rarity = "Rare", earn = 25000000, color = rgb(140, 105, 75), top = "round", face = "sleepy" },
	{ id = "FrostWolf", tier = 9, rarity = "Epic", earn = 89843750, color = rgb(185, 210, 230), top = "cat", face = "angry" },
	{ id = "FrostDragon", tier = 9, rarity = "Epic", earn = 101562500, color = rgb(150, 200, 240), top = "horns", face = "angry" },
	-- Pixel (tier 10): an Egg Shop egg with no biome of its own; things from inside the machine, the mainframe last
	{ id = "Mouse", tier = 10, rarity = "Common", earn = 7812500, color = rgb(150, 150, 160), top = "round", face = "happy" },
	{ id = "Bot", tier = 10, rarity = "Common", earn = 9765625, color = rgb(140, 160, 180), top = "antenna", face = "square" },
	{ id = "Drone", tier = 10, rarity = "Uncommon", earn = 27343750, color = rgb(110, 120, 135), top = "antenna", face = "square" },
	{ id = "Sprite", tier = 10, rarity = "Uncommon", earn = 31250000, color = rgb(120, 230, 190), top = "antenna", face = "happy" },
	{ id = "Glitch", tier = 10, rarity = "Rare", earn = 109375000, color = rgb(200, 90, 220), top = "antenna", face = "square" },
	{ id = "Mecha", tier = 10, rarity = "Rare", earn = 125000000, color = rgb(120, 130, 150), top = "antenna", face = "square" },
	{ id = "Quantum", tier = 10, rarity = "Epic", earn = 449218750, color = rgb(130, 110, 240), top = "halo", face = "square" },
	{ id = "Mainframe", tier = 10, rarity = "Epic", earn = 507812500, color = rgb(80, 90, 120), top = "antenna", face = "square" },
	-- Legendary (tier 11): an Egg Shop egg with no biome of its own; the myths themselves, the elder dragon last
	{ id = "Unicorn", tier = 11, rarity = "Common", earn = 39062500, color = rgb(248, 246, 250), top = "unihorn", face = "happy" },
	{ id = "Pegasus", tier = 11, rarity = "Common", earn = 48828125, color = rgb(235, 240, 250), top = "round", face = "round" },
	{ id = "Griffin", tier = 11, rarity = "Uncommon", earn = 136718750, color = rgb(190, 140, 70), top = "cat", face = "angry" },
	{ id = "Kitsune", tier = 11, rarity = "Uncommon", earn = 156250000, color = rgb(250, 245, 235), top = "cat", face = "happy" },
	{ id = "Chimera", tier = 11, rarity = "Rare", earn = 546875000, color = rgb(170, 110, 60), top = "horns", face = "angry" },
	{ id = "Kraken", tier = 11, rarity = "Rare", earn = 625000000, color = rgb(110, 80, 160), top = "round", face = "angry" },
	{ id = "Leviathan", tier = 11, rarity = "Epic", earn = 2246093750, color = rgb(60, 110, 170), top = "horns", face = "angry" },
	{ id = "ElderDragon", tier = 11, rarity = "Epic", earn = 2539062500, color = rgb(120, 80, 180), top = "crown", face = "angry" },
}

local byId: { [string]: Creature } = {}
for _, creature in list do
	byId[creature.id] = creature
end

return {
	list = list,
	byId = byId,
}
