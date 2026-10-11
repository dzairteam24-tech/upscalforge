--!strict
-- The Index (Logic/Index), as in Steal an Egg: a page for each egg, with every creature it can hatch. Hatch
-- them all and the page's reward can be claimed once: coins and speed (⚡), more for later eggs.

export type Reward = { coins: number, power: number }

-- By egg tier (Config/Eggs: Meadow... Legendary)
local REWARDS: { Reward } = {
	{ coins = 180000, power = 1000 },
	{ coins = 1500000, power = 5000 },
	{ coins = 12000000, power = 25000 },
	{ coins = 100000000, power = 100000 },
	{ coins = 800000000, power = 500000 },
	{ coins = 6000000000, power = 2000000 },
	{ coins = 50000000000, power = 10000000 },
	{ coins = 400000000000, power = 50000000 },
	{ coins = 3000000000000, power = 200000000 },
	{ coins = 25000000000000, power = 1000000000 },
	{ coins = 200000000000000, power = 5000000000 },
}

return { REWARDS = REWARDS }
