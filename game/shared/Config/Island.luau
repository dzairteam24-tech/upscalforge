--!strict
-- Each player's island (WorldService builds them, IslandService runs them): incubators that hatch eggs in
-- real time, and pens where hatched creatures live and earn coins, even while their owner is away.

return {
	ISLANDS = 6, -- one per player (a server holds 6)
	START_COINS = 150,
	INCUBATORS = 3, -- a new island has this many...
	INCUBATOR_PRICES = { 2500, 25000, 250000, 2500000, 25000000 }, -- ...and the 4th, 5th... cost this
	PENS = 4, -- creatures living on the island at once...
	PEN_PRICES = { 1000, 5000, 25000, 100000, 500000, 2500000, 10000000, 50000000 }, -- ...and more cost this
	BASE_INCUBATE = 60, -- seconds a tier 1 egg incubates (later tiers longer, Logic/Hatch)
	OFFLINE_HOURS = 8, -- the island earns this long while its owner is away
	SELL_SECONDS = 120, -- selling a creature pays this many seconds of its earnings
	STORAGE = 60, -- creatures a player can keep (placed or not)
}
