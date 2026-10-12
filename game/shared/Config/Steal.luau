--!strict
-- Stealing: what a player carries outside their garden can be knocked out of their hands with a bat. Gardens are
-- the only safe place (Logic/Layout gardenAt); the barn keeps eggs and creatures safe anywhere.

return {
	HITS = 2, -- hits on the same player, close together, to knock something loose
	COMBO_WINDOW = 4, -- seconds the hits must come within
	COOLDOWN = 0.5, -- seconds between two swings
	REACH = 9, -- how close (studs) the target must be, in front of the swinger
	DROP_TIME = 60, -- seconds a knocked-out egg or creature waits on the ground before going back to its owner
	GRAB_RANGE = 10, -- how close to grab it
}
