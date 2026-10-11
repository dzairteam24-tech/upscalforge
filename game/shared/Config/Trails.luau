--!strict
-- The Trail Shop (TrailService), as in Steal an Egg: a colored trail behind the player that multiplies the speed
-- (⚡) every treadmill step gives. Bought with coins only (speed is never sold for Robux); the player wears one.

export type Trail = { id: string, name: string, rarity: string, colors: { Color3 }, mult: number, price: number }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local LIST: { Trail } = {
	{ id = "Green", name = "Green Trail", rarity = "Uncommon", colors = { rgb(92, 214, 110) }, mult = 2, price = 5000 },
	{ id = "Blue", name = "Blue Trail", rarity = "Rare", colors = { rgb(80, 170, 255) }, mult = 2.5, price = 75000 },
	{ id = "Purple", name = "Purple Trail", rarity = "Epic", colors = { rgb(176, 110, 255) }, mult = 3, price = 1500000 },
	{ id = "Gold", name = "Gold Trail", rarity = "Legendary", colors = { rgb(255, 200, 50), rgb(255, 240, 150) }, mult = 4, price = 50000000 },
	{ id = "Fire", name = "Fire Trail", rarity = "Legendary", colors = { rgb(255, 80, 30), rgb(255, 200, 40) }, mult = 5, price = 2000000000 },
	{ id = "Rainbow", name = "Rainbow Trail", rarity = "Legendary", colors = { rgb(255, 80, 80), rgb(255, 200, 60), rgb(90, 220, 110), rgb(80, 160, 255), rgb(180, 110, 255) }, mult = 7, price = 100000000000 },
}

local byId: { [string]: Trail } = {}
for _, trail in LIST do
	byId[trail.id] = trail
end

return { LIST = LIST, byId = byId }
