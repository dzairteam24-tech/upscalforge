--!strict
-- The daily reward, a 7-day cycle. A missed day pauses the streak, it never wipes it. `income`: minutes of the
-- player's own coin income paid as coins (never less than `min`); `boost`: minutes of a double-coins boost.

export type Reward = { income: number, min: number, boost: number? }

return {
	REWARDS = {
		{ income = 5, min = 50 },
		{ income = 8, min = 80 },
		{ income = 12, min = 120 },
		{ income = 18, min = 180, boost = 10 },
		{ income = 25, min = 250 },
		{ income = 35, min = 350, boost = 15 },
		{ income = 60, min = 600, boost = 30 },
	} :: { Reward },
}
