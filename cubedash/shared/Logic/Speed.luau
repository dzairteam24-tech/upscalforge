--!strict
-- From the speed stat (the number on the screen) to what the runner really does.

local SpeedConfig = require(script.Parent.Parent.Config.Speed)

local Speed = {}

-- The stat: the base and every orb ever collected
function Speed.stat(speed: number): number
	return SpeedConfig.BASE + speed
end

-- The walking speed: it grows with the log of the stat (each stage's wall needs about twice the speed of the one
-- before, and each feels a step quicker), up to WALK_MAX
function Speed.walk(stat: number): number
	local over = math.max(0, stat - SpeedConfig.BASE)
	return math.min(SpeedConfig.WALK_MAX, SpeedConfig.WALK_MIN + SpeedConfig.WALK_LOG * math.log(1 + over / SpeedConfig.WALK_SCALE))
end

-- 0..1: how fast they feel (for the view, trails, speed lines and sound)
function Speed.feel(stat: number): number
	return math.clamp((Speed.walk(stat) - SpeedConfig.WALK_MIN) / (SpeedConfig.FEEL_TOP - SpeedConfig.WALK_MIN), 0, 1)
end

-- The camera's field of view: wider the faster you go
function Speed.fov(stat: number): number
	return SpeedConfig.FOV_MIN + (SpeedConfig.FOV_MAX - SpeedConfig.FOV_MIN) * Speed.feel(stat)
end

return Speed
