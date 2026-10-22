--!strict
-- Each player's island (WorldService builds them, IslandService runs them): incubators that hatch eggs in
-- real time, and pens where hatched creatures live and earn coins, even while their owner is away.

return {
	ISLANDS = 6, -- one per player (a server holds 6)
	START_COINS = 500,
	-- The maps (eggs and Wild biomes) open so far, by egg tier: the others say Coming Soon (their eggs aren't sold,
	-- their biomes are walled off, and prizes give eggs of the open ones). Meadow to Beach are open, with their animals.
	OPEN_TIER = 4,
	FRIEND_BOOST = 0.1, -- each friend in the same server: +10% coins...
	FRIEND_MAX = 5, -- ...for up to this many friends
	-- Testing in Studio only: every player starts the session with this many coins (0: off). Studio then doesn't
	-- save, so the test coins never reach the real game's saves.
	STUDIO_COINS = 500000000,
	INCUBATORS = 3, -- a new island has this many...
	INCUBATOR_PRICES = { -- ...and the 4th, 5th... (up to 16) cost this
		20000, 100000, 300000, 1000000, 3000000, 10000000, 30000000, 100000000, 300000000, 1000000000, 3000000000, 10000000000,
		30000000000,
	},
	-- The incubators at the back of the garden: machines bought one by one, an egg in one hatches MACHINE_SPEED
	-- times faster than in a nest on the ground
	MACHINE_PRICES = { 500000, 25000000, 1000000000, 50000000000 },
	MACHINE_SPEED = 2,
	MACHINE_SLOT = 100, -- (their slots are 101, 102...: the nests' are 1 to 16)
	PENS = 4, -- creatures living on the island at once...
	PEN_PRICES = { 10000, 100000, 1000000, 10000000, 100000000, 1000000000, 10000000000, 100000000000 }, -- ...and more cost this
	-- Seconds each egg incubates on the grass (by tier, Config/Eggs: Meadow... Legendary), paced like Steal an
	-- Egg: the first eggs in seconds, the middle ones in minutes, the best in hours (an hour, a few, half a day).
	-- In real time, even while the player is away; an incubator (machine) halves it.
	HATCH_SECONDS = {
		30, -- Meadow
		60, -- Flower
		2 * 60, -- Forest
		4 * 60, -- Beach
		8 * 60, -- Cave
		15 * 60, -- Desert
		30 * 60, -- Snow
		3600, -- Volcano
		3 * 3600, -- Ice
		6 * 3600, -- Pixel
		12 * 3600, -- Legendary
	},
	STARTER_HATCH = 15, -- a new player's free first egg is already in their golden nest, hatching this fast
	OFFLINE_HOURS = 8, -- the island earns this long while its owner is away
	SELL_SECONDS = 120, -- selling a creature pays this many seconds of its earnings
	STORAGE = { 60, 100, 150 }, -- creatures a player can keep (placed or not), as their barn grows...
	STORAGE_PRICES = { 5000000, 500000000 }, -- ...for this much
	PASTURE_GROWTH = { 0, 20, 40, 60 }, -- studs the pasture reaches back past the garden's back fence, as it grows...
	PASTURE_PRICES = { 1000000, 100000000, 10000000000 }, -- ...for this much
}
