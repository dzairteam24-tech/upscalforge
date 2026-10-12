--!strict
-- Stealing: an egg on its way home (from the Wild, or the Heist Egg) can be knocked out of its carrier's hands
-- with a bat (StealService); once it's in its taker's garden it's safe. Nothing happens inside a garden.

return {
	HITS = 2, -- hits on the same player, close together, to knock something loose
	COMBO_WINDOW = 4, -- seconds the hits must come within
	COOLDOWN = 0.5, -- seconds between two swings
	REACH = 9, -- how close (studs) the target must be, in front of the swinger
	HIT_PUSH = 34, -- how hard a hit pushes the target back (studs a second)...
	KNOCK_PUSH = 60, -- ...and the knock-out hit (it knocks them down too)
}
