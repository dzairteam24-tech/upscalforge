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
}

local byId: { [string]: Creature } = {}
for _, creature in list do
	byId[creature.id] = creature
end

return {
	list = list,
	byId = byId,
}
