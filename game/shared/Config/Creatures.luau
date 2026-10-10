--!strict
-- Every creature (its look: art/models, Config/CreatureLooks): its egg tier, how rare it is in that egg, and
-- how many coins a second it earns when it lives on its owner's island (before its mutation).

export type Creature = {
	id: string,
	tier: number, -- the egg it hatches from (Config/Eggs)
	rarity: string, -- Common, Uncommon, Rare, Epic, Legendary
	earn: number, -- coins a second on the island
	color: Color3, -- the block stand-in's color (without the 3D models)
	top: string, -- the block stand-in's top piece
	face: string, -- and its face
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local list: { Creature } = {
	{ id = "Cubby", tier = 1, rarity = "Common", earn = 1, color = rgb(91, 184, 245), top = "none", face = "round" },
	{ id = "Kitty", tier = 1, rarity = "Uncommon", earn = 2, color = rgb(245, 166, 91), top = "cat", face = "happy" },
	{ id = "Bunny", tier = 1, rarity = "Rare", earn = 4, color = rgb(240, 240, 245), top = "bunny", face = "round" },
	{ id = "Bear", tier = 1, rarity = "Epic", earn = 8, color = rgb(168, 117, 79), top = "round", face = "round" },
	{ id = "Bee", tier = 2, rarity = "Common", earn = 10, color = rgb(245, 210, 70), top = "antenna", face = "round" },
	{ id = "Ladybug", tier = 2, rarity = "Uncommon", earn = 20, color = rgb(229, 83, 75), top = "antenna", face = "round" },
	{ id = "Butterfly", tier = 2, rarity = "Rare", earn = 40, color = rgb(185, 166, 245), top = "antenna", face = "sparkle" },
	{ id = "Uni", tier = 2, rarity = "Epic", earn = 80, color = rgb(247, 198, 224), top = "unihorn", face = "sparkle" },
	{ id = "Fox", tier = 3, rarity = "Common", earn = 22, color = rgb(235, 120, 60), top = "cat", face = "happy" },
	{ id = "Owl", tier = 3, rarity = "Uncommon", earn = 44, color = rgb(150, 120, 95), top = "cat", face = "round" },
	{ id = "Deer", tier = 3, rarity = "Rare", earn = 88, color = rgb(200, 150, 100), top = "horns", face = "round" },
	{ id = "Sprout", tier = 3, rarity = "Epic", earn = 176, color = rgb(123, 211, 137), top = "leaf", face = "sleepy" },
	{ id = "Crab", tier = 4, rarity = "Common", earn = 50, color = rgb(229, 90, 70), top = "round", face = "angry" },
	{ id = "Turtle", tier = 4, rarity = "Uncommon", earn = 100, color = rgb(110, 180, 110), top = "none", face = "sleepy" },
	{ id = "Dolphin", tier = 4, rarity = "Rare", earn = 200, color = rgb(120, 160, 200), top = "none", face = "happy" },
	{ id = "Octopus", tier = 4, rarity = "Epic", earn = 400, color = rgb(160, 90, 200), top = "none", face = "round" },
	{ id = "Mushroom", tier = 5, rarity = "Common", earn = 110, color = rgb(215, 70, 70), top = "cap", face = "round" },
	{ id = "Bat", tier = 5, rarity = "Uncommon", earn = 220, color = rgb(70, 60, 90), top = "cat", face = "angry" },
	{ id = "Glowworm", tier = 5, rarity = "Rare", earn = 440, color = rgb(180, 240, 90), top = "antenna", face = "sleepy" },
	{ id = "Shade", tier = 5, rarity = "Epic", earn = 880, color = rgb(90, 60, 130), top = "horns", face = "angry" },
	{ id = "Camel", tier = 6, rarity = "Common", earn = 250, color = rgb(214, 170, 110), top = "round", face = "sleepy" },
	{ id = "Scorpion", tier = 6, rarity = "Uncommon", earn = 500, color = rgb(140, 90, 50), top = "horns", face = "angry" },
	{ id = "Cactus", tier = 6, rarity = "Rare", earn = 1000, color = rgb(90, 170, 90), top = "leaf", face = "closed" },
	{ id = "Sphinx", tier = 6, rarity = "Epic", earn = 2000, color = rgb(230, 190, 90), top = "crown", face = "shades" },
	{ id = "Penguin", tier = 7, rarity = "Common", earn = 600, color = rgb(50, 55, 70), top = "none", face = "round" },
	{ id = "Seal", tier = 7, rarity = "Uncommon", earn = 1200, color = rgb(160, 170, 185), top = "none", face = "happy" },
	{ id = "Snowman", tier = 7, rarity = "Rare", earn = 2400, color = rgb(245, 248, 255), top = "hat", face = "round" },
	{ id = "Yeti", tier = 7, rarity = "Epic", earn = 4800, color = rgb(235, 240, 250), top = "horns", face = "angry" },
	{ id = "Imp", tier = 8, rarity = "Common", earn = 1500, color = rgb(229, 83, 75), top = "horns", face = "angry" },
	{ id = "Salamander", tier = 8, rarity = "Uncommon", earn = 3000, color = rgb(245, 120, 50), top = "none", face = "happy" },
	{ id = "Golem", tier = 8, rarity = "Rare", earn = 6000, color = rgb(110, 105, 100), top = "none", face = "square" },
	{ id = "Phoenix", tier = 8, rarity = "Epic", earn = 12000, color = rgb(255, 140, 40), top = "flame", face = "sparkle" },
	{ id = "Ice Fox", tier = 9, rarity = "Common", earn = 4000, color = rgb(190, 225, 245), top = "cat", face = "happy" },
	{ id = "Narwhal", tier = 9, rarity = "Uncommon", earn = 8000, color = rgb(130, 170, 220), top = "unihorn", face = "round" },
	{ id = "Frost Owl", tier = 9, rarity = "Rare", earn = 16000, color = rgb(220, 235, 250), top = "cat", face = "sparkle" },
	{ id = "Ice Dragon", tier = 9, rarity = "Epic", earn = 32000, color = rgb(120, 210, 235), top = "horns", face = "angry" },
	{ id = "Bot", tier = 10, rarity = "Common", earn = 10000, color = rgb(154, 165, 177), top = "antenna", face = "square" },
	{ id = "Byte", tier = 10, rarity = "Uncommon", earn = 20000, color = rgb(142, 91, 217), top = "none", face = "square" },
	{ id = "Cursor", tier = 10, rarity = "Rare", earn = 40000, color = rgb(240, 240, 240), top = "none", face = "square" },
	{ id = "King", tier = 10, rarity = "Epic", earn = 80000, color = rgb(108, 99, 217), top = "crown", face = "shades" },
	{ id = "Slime King", tier = 11, rarity = "Legendary", earn = 160000, color = rgb(107, 227, 107), top = "crown", face = "happy" },
	{ id = "Blossom Queen", tier = 11, rarity = "Legendary", earn = 192000, color = rgb(255, 176, 214), top = "crown", face = "sparkle" },
	{ id = "Elder Treant", tier = 11, rarity = "Legendary", earn = 224000, color = rgb(120, 84, 56), top = "leaf", face = "round" },
	{ id = "Kraken", tier = 11, rarity = "Legendary", earn = 272000, color = rgb(40, 90, 140), top = "crown", face = "angry" },
	{ id = "Spore Sage", tier = 11, rarity = "Legendary", earn = 320000, color = rgb(150, 90, 220), top = "cap", face = "sleepy" },
	{ id = "Pharaoh Scarab", tier = 11, rarity = "Legendary", earn = 384000, color = rgb(245, 196, 66), top = "horns", face = "sparkle" },
	{ id = "Aurora Wolf", tier = 11, rarity = "Legendary", earn = 480000, color = rgb(220, 240, 255), top = "cat", face = "sparkle" },
	{ id = "Inferno Drake", tier = 11, rarity = "Legendary", earn = 608000, color = rgb(40, 30, 34), top = "horns", face = "angry" },
	{ id = "Frost Leviathan", tier = 11, rarity = "Legendary", earn = 800000, color = rgb(120, 200, 240), top = "unihorn", face = "sparkle" },
	{ id = "Glitch", tier = 11, rarity = "Legendary", earn = 1280000, color = rgb(24, 24, 32), top = "halo", face = "square" },
}

local byId: { [string]: Creature } = {}
for _, creature in list do
	byId[creature.id] = creature
end

return {
	list = list,
	byId = byId,
}
