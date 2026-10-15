--!strict
-- Speed. The "speed stat" is the number on the screen (it can grow into the thousands); the real walking speed
-- eases toward a ceiling so a fast runner never falls through the floor.

return {
	BASE = 10, -- the stat at the very start
	PER_UPGRADE = 4, -- each speed upgrade adds this
	REBIRTH_BONUS = 0.25, -- each rebirth adds this share of the whole stat (+25%)
	WALK_MIN = 16, -- the walking speed of a stat of BASE...
	WALK_MAX = 90, -- ...easing up to this, never more
	WALK_CURVE = 700, -- bigger = slower to reach the ceiling
	FOV_MIN = 70, -- the camera's field of view standing still...
	FOV_MAX = 108, -- ...and flat out
	JUMP_HEIGHT = 7.5,
}
