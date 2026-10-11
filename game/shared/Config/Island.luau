--!strict
-- Each player's island (WorldService builds them, IslandService runs them): incubators that hatch eggs in
-- real time, and pens where hatched creatures live and earn coins, even while their owner is away.

return {
	ISLANDS = 6, -- one per player (a server holds 6)
	START_COINS = 150,
	-- Testing in Studio only: every player starts the session with this many coins (0: off). Studio then doesn't
	-- save, so the test coins never reach the real game's saves.
	STUDIO_COINS = 500000000,
	INCUBATORS = 3, -- a new island has this many...
	INCUBATOR_PRICES = { -- ...and the 4th, 5th... (up to 16) cost this
		1000, 5000, 15000, 50000, 150000, 500000, 1500000, 5000000, 15000000, 50000000, 150000000, 500000000, 1500000000,
	},
	-- The incubators at the back of the garden: machines bought one by one, an egg in one hatches MACHINE_SPEED
	-- times faster than in a nest on the ground
	MACHINE_PRICES = { 25000, 250000, 2500000, 25000000 },
	MACHINE_SPEED = 2,
	MACHINE_SLOT = 100, -- (their slots are 101, 102...: the nests' are 1 to 16)
	PENS = 4, -- creatures living on the island at once...
	PEN_PRICES = { 1000, 5000, 25000, 100000, 500000, 2500000, 10000000, 50000000 }, -- ...and more cost this
	-- Seconds each egg incubates on the grass (by tier, Config/Eggs: Meadow... Legendary). In real time, even
	-- while the player is away; an incubator (machine) halves it.
	HATCH_SECONDS = {
		2 * 60, -- Meadow
		5 * 60, -- Flower
		10 * 60, -- Forest
		20 * 60, -- Beach
		35 * 60, -- Cave
		60 * 60, -- Desert
		90 * 60, -- Snow
		2 * 3600, -- Volcano
		3 * 3600, -- Ice
		4 * 3600, -- Pixel
		6 * 3600, -- Legendary
	},
	STARTER_HATCH = 30, -- a new player's free first egg is already in their golden nest, hatching this fast
	OFFLINE_HOURS = 8, -- the island earns this long while its owner is away
	SELL_SECONDS = 120, -- selling a creature pays this many seconds of its earnings
	STORAGE = { 60, 100, 150 }, -- creatures a player can keep (placed or not), as their barn grows...
	STORAGE_PRICES = { 50000, 2500000 }, -- ...for this much
	PASTURE_GROWTH = { 0, 20, 40, 60 }, -- studs the pasture reaches back past the garden's back fence, as it grows...
	PASTURE_PRICES = { 10000, 200000, 4000000 }, -- ...for this much
}
