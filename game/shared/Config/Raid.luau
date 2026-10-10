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

	-- The creatures in a garden guard it (Logic/Raid.guards): each second a thief carrying an egg is inside, they
	-- may bump into them, more often the more and the better they are
	GUARD_CHANCE = 0.04, -- a second, for each point of guard power (a creature's mutation order: Normal 1 ... Neon 5)
	GUARD_MAX_CHANCE = 0.5,
	STUN = 1, -- seconds a bumped thief stumbles...
	LAVA_STUN = 2, -- ...longer with a Lava creature on guard (it burns)
	STUN_SPEED = 3, -- how fast a stumbling thief walks
	CRYSTAL_PUSH = 45, -- a Crystal creature also knocks them sideways (studs a second)
	-- (and a Neon creature makes the thief glow, so everyone sees them)

	-- A stolen egg remembers its home: what hatches from it is Homesick, and sends this share of what it earns to
	-- the one it was stolen from, for as long as the thief keeps it
	HOME_SHARE = 0.2,
	SEND_HOME_REWARD = 2, -- or the thief sends it home, and gets this many times its sell price
}
