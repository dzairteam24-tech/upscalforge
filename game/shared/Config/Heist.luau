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
	-- The prize, the same luck for everyone (a new player as much as the strongest): the egg may be empty, or hold
	-- one egg from the middle tiers up, the better the rarer (out of 100; tier 0 = empty)
	PRIZES = {
		{ tier = 0, weight = 25 }, -- empty: no luck this time
		{ tier = 5, weight = 26 }, -- Cave
		{ tier = 6, weight = 18 }, -- Desert
		{ tier = 7, weight = 12 }, -- Snow
		{ tier = 8, weight = 8 }, -- Volcano
		{ tier = 9, weight = 6 }, -- Ice
		{ tier = 10, weight = 4 }, -- Pixel
		{ tier = 11, weight = 1 }, -- Legendary
	},
	ANNOUNCE_TIER = 9, -- a prize this good (or better) is told to the whole server
}
