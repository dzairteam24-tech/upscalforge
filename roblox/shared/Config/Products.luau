--!strict
-- Robux products and rewarded video ads.
-- Rule: eggs, luck and currencies are never sold for Robux.
-- Create these in the Creator Dashboard and paste the IDs here. An ID of 0 hides the product.
--
-- Rewarded video ads: Roblox grants an ad reward through a Developer Product (it arrives in
-- ProcessReceipt with PurchaseChannel = AdReward). Those products are marked `adOnly` and are never
-- shown for sale.

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
	adOnly: boolean?,
}

export type AdReward = {
	key: string, -- matches a DevProduct key
	label: string,
	boost: { stat: string, mult: number, seconds: number }?,
	freeEggs: number?,
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
	{
		key = "PassPremium",
		id = 0,
		name = "Battle Pass Premium",
		description = "Unlocks the premium track of this season: titles and trails for your character. Cosmetic only.",
	},
	-- Rewarded video ads (never sold)
	{ key = "AdCoins", id = 0, name = "Ad: Coins x2", description = "", adOnly = true },
	{ key = "AdLuck", id = 0, name = "Ad: Luck x2", description = "", adOnly = true },
	{ key = "AdPower", id = 0, name = "Ad: Power x2", description = "", adOnly = true },
	{ key = "AdEggs", id = 0, name = "Ad: 3 free eggs", description = "", adOnly = true },
}

local adRewards: { AdReward } = {
	{ key = "AdCoins", label = "Coins x2 · 30 min", boost = { stat = "Coins", mult = 2, seconds = 1800 } },
	{ key = "AdLuck", label = "Luck x2 · 15 min", boost = { stat = "Luck", mult = 2, seconds = 900 } },
	{ key = "AdPower", label = "Power x2 · 15 min", boost = { stat = "Power", mult = 2, seconds = 900 } },
	{ key = "AdEggs", label = "3 free eggs", freeEggs = 3 },
}

local passByKey: { [string]: GamePass } = {}
for _, pass in gamePasses do
	passByKey[pass.key] = pass
end

local productByKey: { [string]: DevProduct } = {}
local productById: { [number]: DevProduct } = {}
for _, product in devProducts do
	productByKey[product.key] = product
	if product.id ~= 0 then
		productById[product.id] = product
	end
end

local adByKey: { [string]: AdReward } = {}
for _, reward in adRewards do
	adByKey[reward.key] = reward
end

return {
	gamePasses = gamePasses,
	devProducts = devProducts,
	adRewards = adRewards,
	passByKey = passByKey,
	productByKey = productByKey,
	productById = productById,
	adByKey = adByKey,
	VIP_EXTRA_SLOTS = 1,
	VIP_EXTRA_OFFLINE_HOURS = 4,
}
