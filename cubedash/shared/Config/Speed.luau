--!strict
-- Speed. The "speed stat" is the number on the screen (it can grow into the thousands); the real walking speed
-- eases toward a ceiling so a fast runner never falls through the floor.

return {
	BASE = 10, -- the stat at the very start
	WALK_MIN = 16, -- the walking speed of a stat of BASE...
	WALK_MAX = 90, -- ...growing with the log of the stat, never more than this
	WALK_LOG = 2.75, -- studs a second for each doubling-and-a-bit (e) of the stat above the base...
	WALK_SCALE = 15, -- ...counted in steps of this
	FEEL_TOP = 60, -- the walking speed that feels flat out (the view at its widest)
	FOV_MIN = 70, -- the camera's field of view standing still...
	FOV_MAX = 108, -- ...and flat out
	JUMP_HEIGHT = 7.5,
}
