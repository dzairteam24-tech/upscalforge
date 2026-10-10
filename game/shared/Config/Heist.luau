--!strict
-- Egg Heist: on weekends a golden Heist Egg drops in the town plaza every few minutes. Whoever grabs it has to
-- carry it home to their island; anyone close enough can steal it on the way. Logic/Heist has the schedule,
-- HeistService runs the rounds.

return {
	EVERY = 15 * 60, -- a round starts this often (on the clock: :00, :15, :30, :45)
	ROUND = 4 * 60, -- and lasts this long before the egg cracks
	WARNING = 60, -- the server is told this long before a round
	WEEKEND_DAYS = { [0] = true, [6] = true }, -- days of the week (UTC, 0 = Sunday) with rounds
	STEAL_RANGE = 10, -- how close to the carrier a thief must be
	STEAL_GUARD = 4, -- seconds a new carrier can't be robbed
	HOME_RANGE = 26, -- how close to the middle of their island the carrier must get
	REWARD_EGGS = 2, -- the prize: eggs of the best tier the winner has hatched
}
