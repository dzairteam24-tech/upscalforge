--!strict
-- What coins buy: shovels (how hard and how fast you dig) and backpacks (how many gem slots you carry).

export type Shovel = { name: string, price: number, power: number, cooldown: number }
export type Pack = { name: string, price: number, slots: number }

return {
	-- power: damage a swing does to a cube; cooldown: seconds between swings
	SHOVELS = {
		{ name = "Wooden Shovel", price = 0, power = 1, cooldown = 0.5 },
		{ name = "Stone Shovel", price = 150, power = 2, cooldown = 0.45 },
		{ name = "Iron Shovel", price = 1800, power = 4, cooldown = 0.4 },
		{ name = "Steel Shovel", price = 20000, power = 8, cooldown = 0.35 },
		{ name = "Diamond Shovel", price = 220000, power = 16, cooldown = 0.3 },
	} :: { Shovel },
	PACKS = {
		{ name = "Small Pack", price = 0, slots = 12 },
		{ name = "Pack", price = 90, slots = 25 },
		{ name = "Big Pack", price = 900, slots = 50 },
		{ name = "Huge Pack", price = 9000, slots = 100 },
		{ name = "Giant Pack", price = 90000, slots = 200 },
	} :: { Pack },
}
