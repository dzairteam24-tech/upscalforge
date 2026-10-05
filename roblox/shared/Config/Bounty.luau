--!strict
-- Daily Bounty: three creatures to hatch each day (easy, medium, hard), picked from the zones you reached.
-- Bigger variants count too (a Golden counts for a Normal bounty).

local Progression = require(script.Parent.Progression)

return {
	REWARDS = {
		{ gems = 25, tickets = 1 },
		{ gems = 75, tickets = 3 },
		{ gems = 200, tickets = 6, items = { { id = "Key_Golden", amount = 1 } } },
	} :: { Progression.Reward },
	-- Extra for finishing all three
	ALL_DONE = { gems = 100, items = { { id = "KeyHalf_Rift", amount = 1 } } } :: Progression.Reward,
	TIER_NAMES = { "Easy", "Medium", "Hard" },
}
