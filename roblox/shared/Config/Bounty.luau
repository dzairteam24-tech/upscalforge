--!strict
-- Daily Bounty: three creatures to hatch each day (easy, medium, hard), picked from the zones you reached.
-- Bigger variants count too (a Golden counts for a Normal bounty).

local Progression = require(script.Parent.Progression)

return {
	REWARDS = {
		{ gems = 10, tickets = 1 },
		{ gems = 25, tickets = 2 },
		{ gems = 60, tickets = 4 },
	} :: { Progression.Reward },
	-- Extra for finishing all three
	ALL_DONE = { gems = 40, items = { { id = "Key_Golden", amount = 1 }, { id = "KeyHalf_Rift", amount = 1 } } } :: Progression.Reward,
	TIER_NAMES = { "Easy", "Medium", "Hard" },
}
