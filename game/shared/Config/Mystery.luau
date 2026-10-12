--!strict
-- The Mystery Egg: a rare egg in the Wild's nests (a new egg is one this often), drawn in rainbow layers and
-- sparkling. It doesn't show a creature: hatched, it gives one of these, by luck (weight), announced big.
--   creature: one of its tier's creatures of that rarity
--   coins: this many seconds of what the player's garden earns (at least `min`)
--   power: this much ⚡ speed
--   eggs: this many eggs of its tier, in the bag

export type Reward = { kind: string, weight: number, rarity: string?, seconds: number?, min: number?, amount: number?, count: number? }

return {
	ID = "Mystery", -- (in an egg's key, where a creature would be: "1@Mystery")
	CHANCE = 0.03, -- each new egg in a Wild nest
	SELL = 8, -- it sells for this many times a common egg
	REWARDS = {
		{ kind = "creature", rarity = "Epic", weight = 15 },
		{ kind = "creature", rarity = "Rare", weight = 30 },
		{ kind = "coins", seconds = 600, min = 2000, weight = 25 },
		{ kind = "power", amount = 300, weight = 15 },
		{ kind = "eggs", count = 3, weight = 15 },
	} :: { Reward },
}
