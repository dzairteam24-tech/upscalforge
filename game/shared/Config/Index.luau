--!strict
-- The Index (Logic/Index), as in Steal an Egg: a page for each egg, with every creature it can hatch. Hatch
-- them all and the page's reward can be claimed once: coins and speed (⚡), more for later eggs.

export type Reward = { coins: number, power: number }

-- By egg tier (Config/Eggs: Meadow... Legendary)
local REWARDS: { Reward } = {
	{ coins = 540000, power = 3000 },
	{ coins = 4500000, power = 15000 },
	{ coins = 36000000, power = 75000 },
	{ coins = 300000000, power = 300000 },
	{ coins = 2400000000, power = 1500000 },
	{ coins = 18000000000, power = 6000000 },
	{ coins = 150000000000, power = 30000000 },
	{ coins = 1200000000000, power = 150000000 },
	{ coins = 9000000000000, power = 600000000 },
	{ coins = 75000000000000, power = 3000000000 },
	{ coins = 600000000000000, power = 15000000000 },
}

-- Each creature, the first time it's found: coins worth CREATURE_SECONDS of what it earns, and speed by rarity
return {
	REWARDS = REWARDS, -- (a whole page: the big one)
	CREATURE_SECONDS = 300,
	CREATURE_POWER = { Common = 50, Uncommon = 120, Rare = 300, Epic = 800, Legendary = 3000, Mythic = 12000 } :: { [string]: number },
}
