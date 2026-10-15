--!strict
-- From the speed stat (the number on the screen) to what the runner really does.

local SpeedConfig = require(script.Parent.Parent.Config.Speed)

local Speed = {}

-- The stat: the base and every orb ever collected
function Speed.stat(speed: number): number
	return SpeedConfig.BASE + speed
end

-- The walking speed, easing from WALK_MIN toward WALK_MAX so it never gets out of hand
function Speed.walk(stat: number): number
	local over = math.max(0, stat - SpeedConfig.BASE)
	return SpeedConfig.WALK_MIN + (SpeedConfig.WALK_MAX - SpeedConfig.WALK_MIN) * (1 - math.exp(-over / SpeedConfig.WALK_CURVE))
end

-- The camera's field of view: wider the faster you go (0..1 of the way to flat out)
function Speed.fov(stat: number): number
	local share = 1 - math.exp(-math.max(0, stat - SpeedConfig.BASE) / (SpeedConfig.WALK_CURVE * 0.8))
	return SpeedConfig.FOV_MIN + (SpeedConfig.FOV_MAX - SpeedConfig.FOV_MIN) * share
end

-- 0..1: how fast they feel (for trails, speed lines and sound)
function Speed.feel(stat: number): number
	return 1 - math.exp(-math.max(0, stat - SpeedConfig.BASE) / (SpeedConfig.WALK_CURVE * 0.8))
end

return Speed
