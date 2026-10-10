--!strict
-- The Mother Cube: once an hour a giant hungry cube lands over the square, and the whole server feeds it
-- together. If it's full before it leaves, it lays an egg for everyone who fed it; the more they gave, the
-- better their chance of a Legendary Egg. Logic/Mother has the schedule, MotherService runs it.

return {
	EVERY = 60 * 60, -- it comes this often...
	AT = 35 * 60, -- ...at this many seconds past (xx:35)
	STUDIO_EVERY = 5 * 60, -- (in Studio, every 5 minutes for testing)
	STUDIO_AT = 150,
	LASTS = 2 * 60, -- it stays this long
	WARNING = 60, -- the server is told this long before

	GOAL_MIN = 8, -- how hungry it is: at least this many points...
	GOAL_PER_PLAYER = 6, -- ...or this many for each player in the server
	FOOD_POINTS = { Hay = 1, Berries = 3, GoldenApple = 10 }, -- a food from the player's trough feeds this much
	SNACK_SECONDS = 60, -- with no food, a snack costs this many seconds of what their garden earns...
	SNACK_MIN = 50, -- ...and at least this many coins, for 1 point

	LEGENDARY_PER_POINT = 0.02, -- each point a player gave adds this chance of a Legendary Egg...
	LEGENDARY_MAX = 0.25, -- ...up to this (otherwise, an egg of the best tier they've hatched)
	SIZE = 10, -- studs
	HEIGHT = 14, -- over the square
	REACH = 24, -- how close to it a player can feed it
}
