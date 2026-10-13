--!strict
-- The gems, from the commonest to the rarest. `from`..`to`: the layers they're found in; `weight`: how often,
-- among the gems of a layer; `value`: coins for a Normal one (Logic/Gem multiplies it by size and mutation).

export type Gem = { id: string, rarity: string, color: Color3, value: number, from: number, to: number, weight: number }

local rgb = Color3.fromRGB

local RARITY_COLORS: { [string]: Color3 } = {
	Common = rgb(205, 210, 220),
	Uncommon = rgb(120, 220, 120),
	Rare = rgb(90, 160, 255),
	Epic = rgb(190, 110, 255),
	Legendary = rgb(255, 190, 60),
}

local LIST: { Gem } = {
	{ id = "Quartz", rarity = "Common", color = rgb(235, 238, 245), value = 5, from = 1, to = 12, weight = 60 },
	{ id = "Amber", rarity = "Common", color = rgb(255, 160, 40), value = 12, from = 3, to = 16, weight = 40 },
	{ id = "Ruby", rarity = "Uncommon", color = rgb(235, 40, 70), value = 40, from = 9, to = 24, weight = 25 },
	{ id = "Sapphire", rarity = "Rare", color = rgb(50, 110, 255), value = 140, from = 17, to = 36, weight = 12 },
	{ id = "Emerald", rarity = "Epic", color = rgb(40, 220, 110), value = 600, from = 25, to = 40, weight = 5 },
	{ id = "Void", rarity = "Legendary", color = rgb(150, 60, 255), value = 4000, from = 33, to = 40, weight = 1.5 },
}

local byId: { [string]: Gem } = {}
for _, gem in LIST do
	byId[gem.id] = gem
end

return { LIST = LIST, byId = byId, RARITY_COLORS = RARITY_COLORS }
