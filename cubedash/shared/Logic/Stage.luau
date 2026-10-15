--!strict
-- A stage, built from its number alone (so the server and every phone agree where everything is): the obstacles,
-- the orbs, the wall at the end and the theme. Lane position `x` is across (0 = the middle), `d` is how far along
-- the stage, `y` is the height of an orb above the floor.

local Config = script.Parent.Parent.Config
local CourseConfig = require(Config.Course)
local Economy = require(script.Parent.Economy)
local Obstacles = require(script.Parent.Obstacles)
local Rng = require(script.Parent.Rng)
local Speed = require(script.Parent.Speed)

export type Orb = { x: number, d: number, y: number }
export type Stage = {
	stage: number,
	length: number, -- where the wall is
	theme: number,
	needs: number, -- the speed stat that smashes the wall
	orbs: { Orb },
	obstacles: { Obstacles.Obstacle },
	difficulty: number, -- 0..1
}

local Stage = {}

local W = CourseConfig.WIDTH
local cache: { [number]: Stage } = {}

-- Obstacle kinds a stage may use: they come in one at a time
local function kindsFor(stage: number): { string }
	local list = { "sweeper", "laser" }
	if stage >= 2 then
		table.insert(list, "spinner")
	end
	if stage >= 3 then
		table.insert(list, "falling")
	end
	if stage >= 4 then
		table.insert(list, "pendulum")
	end
	return list
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- One obstacle of a kind at distance d; harder as `u` goes 0..1 (stage 1 is gentle, stage 10 is not)
function Stage.make(kind: string, d: number, u: number, rng: Rng.Rng): Obstacles.Obstacle
	local phase = Rng.range(rng, 0, 2 * math.pi)
	if kind == "sweeper" then
		local width = lerp(10, 23, u)
		return { kind = kind, d = d, w = width, amp = (W - width) / 2 + width * 0.18 + 4, omega = lerp(0.8, 3.0, u), phase = phase }
	elseif kind == "spinner" then
		return { kind = kind, d = d, x = Rng.range(rng, -2, 2), R = lerp(6.5, 13, u), omega = lerp(1.1, 3.8, u) * (if Rng.float(rng) < 0.5 then -1 else 1), phase = phase }
	elseif kind == "laser" then
		return { kind = kind, d = d, period = lerp(3.6, 1.5, u), on = lerp(0.2, 0.5, u), omega = 0, phase = phase, h = 2.0 }
	elseif kind == "falling" then
		return { kind = kind, d = d, x = 0, size = lerp(7, 11, u), period = lerp(3.0, 1.2, u), omega = 0, phase = phase }
	end
	-- pendulum
	return { kind = "pendulum", d = d, x = 0, len = 12, amp = lerp(0.7, 1.4, u), omega = lerp(1.0, 3.4, u), phase = phase }
end

-- A falling cube is one of a row: the same cycle across the lane, so there is always somewhere to stand
local function addFalling(list: { Obstacles.Obstacle }, d: number, u: number, rng: Rng.Rng)
	local base = Stage.make("falling", d, u, rng)
	local columns = { -11, 0, 11 }
	local skip = Rng.int(rng, 1, #columns) -- (one column is always free)
	for i, x in columns do
		if i ~= skip then
			local o = table.clone(base)
			o.x = x
			table.insert(list, o)
		end
	end
end

function Stage.generate(stage: number): Stage
	local cached = cache[stage]
	if cached then
		return cached
	end
	local rng = Rng.new(1000 + stage * 7919)
	local length = Economy.stageLength(stage)
	local u = (stage - 1) / (CourseConfig.STAGES - 1)
	local zoneStart, zoneEnd = CourseConfig.START_PAD, length - CourseConfig.END_PAD
	-- obstacles come closer together, in time, as the stages go on (4.2 s apart, then 1.8 s)
	local pace = Speed.walk(Economy.needs(stage))
	local count = math.max(4, math.floor((zoneEnd - zoneStart) / (pace * lerp(4.2, 1.8, u))))
	local spacing = (zoneEnd - zoneStart) / count
	local kinds = kindsFor(stage)
	local obstacles: { Obstacles.Obstacle } = {}
	local last = ""
	for i = 1, count do
		local d = zoneStart + (i - 0.5) * spacing + Rng.range(rng, -spacing * 0.1, spacing * 0.1)
		local kind = Rng.pick(rng, kinds)
		if kind == last and #kinds > 1 then
			kind = kinds[(table.find(kinds, kind) :: number) % #kinds + 1]
		end
		last = kind
		if kind == "falling" then
			addFalling(obstacles, d, u, rng)
		else
			table.insert(obstacles, Stage.make(kind, d, u, rng))
		end
	end
	-- the distances that are an obstacle's (orbs keep out of them)
	local zones: { number } = {}
	for _, o in obstacles do
		if #zones == 0 or math.abs(zones[#zones] - o.d) > 0.5 then
			table.insert(zones, o.d)
		end
	end
	local function blocked(d: number): boolean
		for _, z in zones do
			if math.abs(d - z) < 9 then
				return true
			end
		end
		return false
	end
	-- orbs: short lines and arcs between the obstacles
	local total = Economy.orbsIn(stage)
	local orbs: { Orb } = {}
	local cursor = zoneStart * 0.55
	local step = (zoneEnd + 14 - cursor) / math.ceil(total / 4)
	while #orbs < total do
		local n = math.min(Rng.int(rng, 3, 5), total - #orbs)
		local x0 = Rng.range(rng, -10, 10)
		local arc = Rng.float(rng) < 0.22
		local zig = Rng.float(rng) < 0.3
		local start = cursor
		while blocked(start) or blocked(start + 3.6 * (n - 1)) do
			start += 3
			if start > zoneEnd + 10 then
				start = zoneStart * 0.55 + Rng.range(rng, 0, 20)
				break
			end
		end
		for j = 0, n - 1 do
			local d = start + 3.6 * j
			local x = math.clamp(x0 + (if zig then 4 * math.sin(j * 1.4) else 0), -13, 13)
			local y = if arc then 3 + 6.5 * math.sin(math.pi * (j + 0.5) / n) else 3
			table.insert(orbs, { x = x, d = d, y = y })
		end
		cursor += step
		if cursor > zoneEnd then
			cursor = zoneStart * 0.55
		end
	end
	local made: Stage = {
		stage = stage,
		length = length,
		theme = (stage - 1) % #CourseConfig.THEMES + 1,
		needs = Economy.needs(stage),
		orbs = orbs,
		obstacles = obstacles,
		difficulty = u,
	}
	cache[stage] = made
	return made
end


return Stage
