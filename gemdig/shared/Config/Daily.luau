--!strict
-- The daily reward, a 7-day cycle. A missed day pauses the streak, it never wipes it. `income`: minutes of the
-- player's own income paid as coins (never less than `min`); `boost`: minutes of a double-coins boost.

export type Reward = { income: number, min: number, boost: number? }

return {
	REWARDS = {
		{ income = 5, min = 60 },
		{ income = 8, min = 100 },
		{ income = 12, min = 150 },
		{ income = 18, min = 220, boost = 10 },
		{ income = 25, min = 300 },
		{ income = 35, min = 400, boost = 15 },
		{ income = 60, min = 700, boost = 30 },
	} :: { Reward },
}
