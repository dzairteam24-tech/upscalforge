--!strict
-- Coin sources. Coin amounts are for zone 1 and scale with each zone's `scale`.

export type BreakableKind = {
	id: string,
	coins: number, -- coins inside at zone 1
	respawn: number, -- seconds until it comes back
	count: number, -- how many spawn per zone
	size: Vector3,
	color: Color3,
	isChest: boolean, -- affected by Chest skills
	isPile: boolean, -- affected by Pile skills
}

local list: { BreakableKind } = {
	{
		id = "Pile",
		coins = 50,
		respawn = 5,
		count = 16,
		size = Vector3.new(4, 2.5, 4),
		color = Color3.fromRGB(245, 197, 66),
		isChest = false,
		isPile = true,
	},
	{
		id = "Chest",
		coins = 500,
		respawn = 30,
		count = 5,
		size = Vector3.new(5, 4, 4),
		color = Color3.fromRGB(161, 107, 59),
		isChest = true,
		isPile = false,
	},
	{
		id = "Safe",
		coins = 5000,
		respawn = 120,
		count = 2,
		size = Vector3.new(7, 7, 6),
		color = Color3.fromRGB(120, 128, 140),
		isChest = true,
		isPile = false,
	},
	{
		id = "Vault",
		coins = 50000,
		respawn = 600,
		count = 1,
		size = Vector3.new(12, 11, 10),
		color = Color3.fromRGB(58, 62, 80),
		isChest = true,
		isPile = false,
	},
}

local byId: { [string]: BreakableKind } = {}
for _, kind in list do
	byId[kind.id] = kind
end

return {
	list = list,
	byId = byId,
}
