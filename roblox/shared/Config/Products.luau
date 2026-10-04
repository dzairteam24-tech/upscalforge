--!strict
-- Robux products. Rule: eggs, luck and currencies are never sold for Robux.
-- Create these in the Creator Dashboard and paste the IDs here. An ID of 0 hides the product in the shop.

export type GamePass = {
	key: string,
	id: number,
	name: string,
	description: string,
}

export type DevProduct = {
	key: string,
	id: number,
	name: string,
	description: string,
}

local gamePasses: { GamePass } = {
	{
		key = "VIP",
		id = 0,
		name = "VIP",
		description = "+1 team slot, +4h offline earnings, VIP title",
	},
}

local devProducts: { DevProduct } = {
	{
		key = "SupporterTitle",
		id = 0,
		name = "Supporter Title",
		description = "A golden 'Supporter' title above your head. Cosmetic only.",
	},
}

local passByKey: { [string]: GamePass } = {}
for _, pass in gamePasses do
	passByKey[pass.key] = pass
end

local productById: { [number]: DevProduct } = {}
for _, product in devProducts do
	if product.id ~= 0 then
		productById[product.id] = product
	end
end

return {
	gamePasses = gamePasses,
	devProducts = devProducts,
	passByKey = passByKey,
	productById = productById,
	VIP_EXTRA_SLOTS = 1,
	VIP_EXTRA_OFFLINE_HOURS = 4,
}
