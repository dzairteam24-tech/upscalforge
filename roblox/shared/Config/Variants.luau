--!strict
-- Rarity variants. A variant multiplies a creature's power and is ×2 stronger in its element zone.

export type Variant = {
	id: string,
	order: number,
	mult: number,
	chance: number, -- base chance to roll this variant when hatching (0 = default)
	strongIn: string?, -- element where this variant gets the element bonus
	fuseInto: string?, -- variant produced by fusing FUSION_COST of this variant
	color: Color3,
	description: string,
}

local list: { Variant } = {
	{
		id = "Normal",
		order = 1,
		mult = 1,
		chance = 0,
		fuseInto = "Golden",
		color = Color3.fromRGB(138, 148, 166),
		description = "Base look.",
	},
	{
		id = "Golden",
		order = 2,
		mult = 1.5,
		chance = 1 / 50,
		strongIn = "Treasure",
		fuseInto = "Crystal",
		color = Color3.fromRGB(232, 181, 58),
		description = "Shiny gold. x2 in Treasure zones.",
	},
	{
		id = "Crystal",
		order = 3,
		mult = 2.5,
		chance = 1 / 250,
		strongIn = "Fire",
		color = Color3.fromRGB(79, 179, 232),
		description = "Ice glass. x2 in Fire zones.",
	},
	{
		id = "Lava",
		order = 4,
		mult = 4,
		chance = 1 / 1000,
		strongIn = "Ice",
		color = Color3.fromRGB(240, 100, 45),
		description = "Molten rock. x2 in Ice zones.",
	},
	{
		id = "Neon",
		order = 5,
		mult = 6,
		chance = 1 / 5000,
		strongIn = "Dark",
		color = Color3.fromRGB(43, 217, 138),
		description = "Glows in the dark. x2 in Dark zones.",
	},
	{
		id = "Pixel",
		order = 6,
		mult = 10,
		chance = 1 / 50000,
		strongIn = "Pixel",
		color = Color3.fromRGB(142, 91, 217),
		description = "8-bit. x2 in Pixel zones.",
	},
}

local byId: { [string]: Variant } = {}
for _, variant in list do
	byId[variant.id] = variant
end

return {
	list = list,
	byId = byId,
}
