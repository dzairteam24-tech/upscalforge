--!strict
-- Cube Stack (the Arcade booth in the town): drop sliding cubes on top of each other; whatever hangs over
-- the edge falls off. Free, a few plays a day, rewards grow with the height.

return {
	PLAYS_PER_DAY = 5,
	MAX_SCORE = 120, -- higher scores are treated as cheating
	SECONDS_PER_CUBE = 0.35, -- a real game can't place cubes faster than this
	TICKETS_EVERY = 5, -- 1 ticket per 5 cubes
	MAX_TICKETS = 6,
	GEMS_PER_CUBE = 2,
	MAX_GEMS = 80,
}
