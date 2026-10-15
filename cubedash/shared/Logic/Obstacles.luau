--!strict
-- The obstacles, as pure maths: where each one is at time `t` (seconds, the server's clock, so every phone draws it
-- the same), and whether a runner at lane position `x`, distance `d` along the stage and `feet` above the floor,
-- with a body radius `r`, is touching it. Drawn on the phone, checked on the phone and (for the rules) by the
-- server's own copy of the same numbers.

export type Obstacle = {
	kind: string,
	d: number, -- where along the stage
	x: number?, -- lane position of its middle (not every kind has one)
	w: number?, -- sweeper: its width
	amp: number?, -- sweeper: how far it slides; pendulum: how far it swings (radians)
	omega: number, -- how fast it moves (radians a second)
	phase: number,
	R: number?, -- spinner: arm length
	period: number?, -- laser, falling: seconds a cycle
	on: number?, -- laser: the share of a cycle it is on
	h: number?, -- laser: how high it reaches
	size: number?, -- falling: the cube's size
	len: number?, -- pendulum: its arm
}

local Obstacles = {}

Obstacles.BODY = 1.3 -- a runner's body radius
Obstacles.SWEEPER_THICK = 1.6 -- half
Obstacles.SPINNER_THICK = 1.2 -- half
Obstacles.SPINNER_TOP = 2.6
Obstacles.LASER_HALF = 0.8
Obstacles.PENDULUM_PIVOT = 15
Obstacles.PENDULUM_BOB = 3
Obstacles.FALL_FROM = 0.34 -- the share of a falling cube's cycle it starts to be solid...
Obstacles.FALL_TO = 0.72 -- ...and stops

function Obstacles.sweeperX(o: Obstacle, t: number): number
	return (o.amp :: number) * math.sin(o.omega * t + o.phase)
end

function Obstacles.spinnerAngle(o: Obstacle, t: number): number
	return o.omega * t + o.phase
end

-- Whether a laser is on at this time
function Obstacles.laserOn(o: Obstacle, t: number): boolean
	local period = o.period :: number
	return (t + o.phase) % period < period * (o.on :: number)
end

-- 0..1 through a falling cube's cycle
function Obstacles.fallPhase(o: Obstacle, t: number): number
	local period = o.period :: number
	return ((t + o.phase) % period) / period
end

function Obstacles.pendulumAngle(o: Obstacle, t: number): number
	return (o.amp :: number) * math.sin(o.omega * t + o.phase)
end

-- The pendulum's ball: lane position and height
function Obstacles.pendulumBob(o: Obstacle, t: number): (number, number)
	local theta = Obstacles.pendulumAngle(o, t)
	local len = o.len :: number
	return (o.x or 0) + len * math.sin(theta), Obstacles.PENDULUM_PIVOT - len * math.cos(theta)
end

-- Is the runner touching it? (x: lane, feet: height above the floor, d: along the stage, r: body radius)
function Obstacles.hit(o: Obstacle, t: number, x: number, feet: number, d: number, r: number): boolean
	local kind = o.kind
	if kind == "sweeper" then
		if math.abs(d - o.d) > Obstacles.SWEEPER_THICK + r or feet > 8 then
			return false
		end
		return math.abs(x - Obstacles.sweeperX(o, t)) <= (o.w :: number) / 2 + r
	elseif kind == "spinner" then
		if feet > Obstacles.SPINNER_TOP then
			return false
		end
		local dx, dd = x - (o.x or 0), d - o.d
		local reach = (o.R :: number) + Obstacles.SPINNER_THICK + r
		if dx * dx + dd * dd > reach * reach then
			return false
		end
		local theta = Obstacles.spinnerAngle(o, t)
		local ux, ud = math.cos(theta), math.sin(theta)
		local along = dx * ux + dd * ud
		local across = math.abs(-dx * ud + dd * ux)
		local overshoot = math.max(0, math.abs(along) - (o.R :: number))
		return math.sqrt(overshoot * overshoot + across * across) <= Obstacles.SPINNER_THICK + r
	elseif kind == "laser" then
		if feet > (o.h :: number) or math.abs(d - o.d) > Obstacles.LASER_HALF + r then
			return false
		end
		return Obstacles.laserOn(o, t)
	elseif kind == "falling" then
		local phase = Obstacles.fallPhase(o, t)
		if phase < Obstacles.FALL_FROM or phase > Obstacles.FALL_TO then
			return false
		end
		local half = (o.size :: number) / 2 + r
		return math.abs(x - (o.x or 0)) <= half and math.abs(d - o.d) <= half and feet <= (o.size :: number)
	elseif kind == "pendulum" then
		if math.abs(d - o.d) > 2.4 + r then
			return false
		end
		local bx, by = Obstacles.pendulumBob(o, t)
		local dx, dy = x - bx, feet + 3 - by
		local reach = Obstacles.PENDULUM_BOB + r
		return dx * dx + dy * dy <= reach * reach
	end
	return false
end

-- Whether any obstacle of the list is touching the runner
function Obstacles.anyHit(list: { Obstacle }, t: number, x: number, feet: number, d: number, r: number): boolean
	for _, o in list do
		if Obstacles.hit(o, t, x, feet, d, r) then
			return true
		end
	end
	return false
end

return Obstacles
