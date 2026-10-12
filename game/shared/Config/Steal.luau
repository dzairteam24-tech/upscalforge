--!strict
-- Stealing: an egg on its way home (from the Wild, or the Heist Egg) can be knocked out of its carrier's hands
-- with a bat (StealService); once it's in its taker's garden it's safe. Nothing happens inside a garden.

return {
	HITS = 1, -- hits on the same player, close together, to knock them down (and the egg they carry loose)
	COMBO_WINDOW = 4, -- seconds the hits must come within
	COOLDOWN = 0.5, -- seconds between two swings
	REACH = 9, -- how close (studs) the target must be, in front of the swinger
	HIT_PUSH = 34, -- how hard a hit pushes the target back (studs a second), when it takes more than one...
	KNOCK_PUSH = 50, -- ...and the hit that knocks them down
	-- Test bots that steal eggs and swing bats, so one person can try it all alone (TestBotService). In Studio
	-- only: the published game never has them. 0: none.
	TEST_BOTS = 3,
	STUN = 2, -- seconds a knocked-down player lies there, unable to move (and can't be hit again meanwhile)
}
