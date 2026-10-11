--!strict
-- The Index (Logic/Index), as in Steal an Egg: a page for each egg, with every creature it can hatch. Hatch
-- them all and the page's reward can be claimed once: coins and speed (⚡), more for later eggs.

export type Reward = { coins: number, power: number }

-- By egg tier (Config/Eggs: Meadow... Legendary)
local REWARDS: { Reward } = {
	{ coins = 2000, power = 100 },
	{ coins = 15000, power = 300 },
	{ coins = 40000, power = 1000 },
	{ coins = 100000, power = 2500 },
	{ coins = 250000, power = 6000 },
	{ coins = 600000, power = 15000 },
	{ coins = 1500000, power = 40000 },
	{ coins = 4000000, power = 100000 },
	{ coins = 10000000, power = 250000 },
	{ coins = 25000000, power = 600000 },
	{ coins = 100000000, power = 1500000 },
}

return { REWARDS = REWARDS }
