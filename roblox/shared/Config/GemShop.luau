--!strict
-- Gem shop: fixed items for fixed prices (never random), so gems always have a use.
-- Items of a system that isn't open yet (Config/Unlocks) stay hidden until it opens.

export type Offer = {
	id: string,
	itemId: string?, -- item given (nil for upgrades)
	upgrade: string?, -- "Storage"
	price: number,
	feature: string?, -- shown once this system is open
}

local offers: { Offer } = {
	-- Elixirs
	{ id = "CoinElixir2", itemId = "Elixir_Coins_2", price = 30 },
	{ id = "PowerElixir2", itemId = "Elixir_Power_2", price = 30 },
	{ id = "LuckElixir2", itemId = "Elixir_Luck_2", price = 45 },
	{ id = "CoinElixir3", itemId = "Elixir_Coins_3", price = 70 },
	{ id = "LuckElixir3", itemId = "Elixir_Luck_3", price = 100 },
	-- Key halves
	{ id = "ZoneHalf", itemId = "KeyHalf_Zone", price = 60 },
	{ id = "GoldenHalf", itemId = "KeyHalf_Golden", price = 120 },
	-- No Titan halves: a Titan Key skips the guardian's 4h wait, so it stays a rare drop
	-- Boost Cards
	{ id = "CoinsCard", itemId = "Cart_Coins_1", price = 150, feature = "Cartridges" },
	{ id = "LuckyCard", itemId = "Cart_Lucky_1", price = 150, feature = "Cartridges" },
	{ id = "PowerCard", itemId = "Cart_Power_1", price = 150, feature = "Cartridges" },
	-- Stickers
	{ id = "StarSticker", itemId = "Sticker_Star_1", price = 120, feature = "Stickers" },
	{ id = "CoinSticker", itemId = "Sticker_Coin_1", price = 100, feature = "Stickers" },
	{ id = "CloverSticker", itemId = "Sticker_Clover_1", price = 100, feature = "Stickers" },
	-- Gadgets
	{ id = "Bomb", itemId = "Gadget_Bomb", price = 50, feature = "Gadgets" },
	{ id = "TimeSkip", itemId = "Gadget_TimeSkip", price = 40, feature = "Gadgets" },
	{ id = "RainCloud", itemId = "Gadget_RainCloud", price = 60, feature = "Gadgets" },
	{ id = "CoinTotem", itemId = "Gadget_CoinTotem", price = 90, feature = "Gadgets" },
	-- Permanent upgrades
	{ id = "Storage", upgrade = "Storage", price = 200 },
}

local byId: { [string]: Offer } = {}
for _, offer in offers do
	byId[offer.id] = offer
end

return {
	offers = offers,
	byId = byId,
	DEALS_PER_DAY = 3,
	DEAL_DISCOUNT = 0.4, -- 40% off, one of each per day
	STORAGE_STEP = 50, -- creature storage per Storage upgrade
	STORAGE_PRICE_STEP = 100, -- each Storage upgrade costs this much more
	STORAGE_MAX = 10,
}
