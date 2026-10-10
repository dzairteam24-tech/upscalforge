--!strict
-- Raid Time: every garden's laser gate opens at the same moment, for everyone in every server (it follows the
-- clock, Logic/Raid), so nobody can keep re-locking. While the gates are open, players can walk into other
-- gardens and carry off an egg from an incubator. Only eggs: hatched creatures are never stolen.

return {
	EVERY = 10 * 60, -- the gates open this often...
	OPEN = 60, -- ...for this long
	WARNING = 15, -- everyone is told this long before
	SAFE_SLOT = 1, -- this incubator can never be robbed
	NEW_PLAYER_SAFE = 15 * 60, -- a new player's garden can't be robbed for this long after they first play
	CATCH_RANGE = 7, -- the owner gets their egg back by touching the thief this close
	THIEF_SPEED = 11, -- a thief carrying an egg walks this fast (normal is 16)
	STEAL_RANGE = 9, -- how close to an incubator a thief must stand
}
