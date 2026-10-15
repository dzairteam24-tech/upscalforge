-- A bot that runs a Cubedash stage the way a person might, to measure how hard the stage is. It sees the whole
-- course (every obstacle's rhythm is a formula) but acts like a person: it looks a limited time ahead, its guess
-- of where things will be is a little off, its thumb is late and a bit shaky, and it can only steer in a few
-- directions. Walking speed is the total: sidestepping costs forward speed, as it does for a Roblox Humanoid.

local Loader = require("./loader")

local Shared = Loader.root("cubedash/shared", "Shared")
local Rng = Loader.require(Shared.Logic.Rng)
local Obstacles = Loader.require(Shared.Logic.Obstacles)
local Speed = Loader.require(Shared.Logic.Speed)
local CourseConfig = Loader.require(Shared.Config.Course)
local SpeedConfig = Loader.require(Shared.Config.Speed)

export type Skill = {
	name: string,
	reaction: number, -- seconds from deciding to the thumb doing it
	step: number, -- seconds between decisions
	horizon: number, -- seconds it plans ahead
	wobble: number, -- studs a second of random sideways drift
	timeNoise: number, -- seconds its guess of an obstacle's rhythm is off by
	margin: number, -- extra studs of room it likes around obstacles
}

local Bot = {}

Bot.PRO = { name = "pro", reaction = 0.12, step = 0.1, horizon = 1.5, wobble = 1.5, timeNoise = 0.03, margin = 0.4 } :: Skill
Bot.CASUAL = { name = "casual", reaction = 0.22, step = 0.12, horizon = 1.2, wobble = 2.5, timeNoise = 0.06, margin = 0.6 } :: Skill
Bot.NOVICE = { name = "novice", reaction = 0.35, step = 0.16, horizon = 1.0, wobble = 4, timeNoise = 0.12, margin = 1.0 } :: Skill

-- what the thumb can do: steer a fixed way, or make for a place across the lane and stay there
type Control = { heading: number?, target: number? }
local CONTROLS: { Control } = {
	{ heading = 0 },
	{ heading = -0.5 },
	{ heading = 0.5 },
	{ heading = -1.0 },
	{ heading = 1.0 },
	{ target = -11 },
	{ target = -5.5 },
	{ target = 0 },
	{ target = 5.5 },
	{ target = 11 },
}
local JUMP_STEP = 0.1 -- the jump can be put off by this much each time
local GRAVITY = 196.2
local JUMP_V = math.sqrt(2 * GRAVITY * SpeedConfig.JUMP_HEIGHT)
local JUMP_TIME = 2 * JUMP_V / GRAVITY

local function feetAt(jt: number): number
	if jt < 0 or jt >= JUMP_TIME then
		return 0
	end
	return JUMP_V * jt - 0.5 * GRAVITY * jt * jt
end

-- Runs the stage; returns whether it got to the end, and (if not) what killed it and how far along it was
function Bot.run(stage: any, skill: Skill, seed: number, speedOverride: number?, log: ((string) -> ())?): (boolean, string?, number?)
	local rng = Rng.new(seed)
	local S = speedOverride or Speed.walk(stage.needs)
	local r = Obstacles.BODY
	local halfLane = CourseConfig.WIDTH / 2 - r
	local finish = stage.length - CourseConfig.END_PAD
	local t0 = Rng.range(rng, 0, 1000)
	local t = t0
	local dt = 1 / 30
	local x, d, jumpT = 0, 0, -1
	local heading = 0
	local wobble, wobbleUntil = 0, 0
	local nextDecision = 0
	-- what the thumb will do, and when (decisions land `reaction` seconds after they are made)
	local control: Control = { heading = 0 }
	local queue: { { at: number, control: Control } } = {}
	local jumpAt = -1 -- when a jump that is already decided will start
	-- how far off its guess of each obstacle's rhythm is (it stays the same, as it does for a person)
	local bias: { [any]: number } = {}
	for _, o in stage.obstacles do
		bias[o] = (Rng.float(rng) + Rng.float(rng) + Rng.float(rng) - 1.5) * 2 * skill.timeNoise
	end

	-- the direction a control makes the runner go, from where it is
	local function headingOf(c: Control, px: number, step: number): number
		if c.target then
			return math.asin(math.clamp((c.target - px) / (S * step), -1, 1))
		end
		return c.heading :: number
	end

	local function near(from: number, to: number): { any }
		local list = {}
		for _, o in stage.obstacles do
			if o.d > from - 14 and o.d < to + 14 then
				table.insert(list, o)
			end
		end
		return list
	end

	-- plays out a plan and says how long it lasts before a hit (the horizon if it never does), and where it ends
	-- jumpIn: seconds from now that a jump starts (-1 for none)
	local function lasts(list: { any }, c: Control, jumpIn: number): (number, number)
		local ps = math.min(0.06, 1.6 / S)
		local px, pd, jt = x, d, jumpT
		local tau = 0
		local hit = r + skill.margin * 0.5
		while tau < skill.horizon do
			tau += ps
			local cc = c
			if tau <= skill.reaction then
				cc = control
				for _, q in queue do
					if q.at - t <= tau then
						cc = q.control
					end
				end
			end
			local hh = headingOf(cc, px, ps)
			if jumpIn >= 0 and tau >= jumpIn and jt < 0 then
				jt = 0
				jumpIn = -1
			end
			px = math.clamp(px + S * math.sin(hh) * ps, -halfLane, halfLane)
			pd += S * math.cos(hh) * ps
			if jt >= 0 then
				jt += ps
				if jt >= JUMP_TIME then
					jt = -1
				end
			end
			local feet = if jt >= 0 then feetAt(jt) else 0
			for _, o in list do
				if Obstacles.hit(o, t + tau + bias[o], px, feet, pd, hit) then
					return tau, px
				end
			end
		end
		return skill.horizon, px
	end

	while d < finish do
		if t - t0 >= nextDecision then
			nextDecision += skill.step
			local list = near(d, d + S * skill.horizon + 10)
			local bestScore, bestControl, bestJumpIn = -1e9, CONTROLS[1], -1
			for _, c in CONTROLS do
				-- no jump, or the one already decided, or a jump put off by 0, 1, 2... steps
				local options: { number } = { -1 }
				if jumpAt >= 0 then
					options = { jumpAt - t }
				elseif jumpT < 0 then
					local delay = skill.reaction
					while delay < skill.horizon - 0.2 do
						table.insert(options, delay)
						delay += JUMP_STEP
					end
				end
				for _, jumpIn in options do
					local survived, endX = lasts(list, c, jumpIn)
					local score
					if survived >= skill.horizon then
						local effort = if c.heading then math.abs(c.heading) * 4 else math.abs(c.target :: number - x) * 0.25 + 1
						score = 1000 - effort - (if jumpIn >= 0 and jumpAt < 0 then 6 else 0) - math.abs(endX) * 0.35 - (if math.abs(endX) > halfLane - 3 then 5 else 0)
					else
						score = survived * 100
					end
					if score > bestScore then
						bestScore, bestControl, bestJumpIn = score, c, jumpIn
					end
				end
			end
			table.insert(queue, { at = t + skill.reaction, control = bestControl })
			if bestJumpIn >= 0 and jumpAt < 0 then
				jumpAt = t + bestJumpIn
			end
			if log then
				log(string.format("t=%.2f d=%.1f x=%.1f -> %s jumpIn=%.2f score=%.1f near=%d", t - t0, d, x, if bestControl.target then "to " .. bestControl.target else "heading " .. tostring(bestControl.heading), bestJumpIn, bestScore, #list))
			end
		end
		while queue[1] and t >= queue[1].at do
			control = (table.remove(queue, 1) :: any).control
		end
		heading = headingOf(control, x, dt)
		if jumpAt >= 0 and t >= jumpAt then
			if jumpT < 0 then
				jumpT = 0
			end
			jumpAt = -1
		end
		if t >= wobbleUntil then
			wobble = (Rng.float(rng) - 0.5) * 2 * skill.wobble
			wobbleUntil = t + 0.15
		end
		x = math.clamp(x + (S * math.sin(heading) + wobble) * dt, -halfLane, halfLane)
		d += S * math.cos(heading) * dt
		if jumpT >= 0 then
			jumpT += dt
			if jumpT >= JUMP_TIME then
				jumpT = -1
			end
		end
		t += dt
		local feet = if jumpT >= 0 then feetAt(jumpT) else 0
		for _, o in near(d, d + 4) do
			if Obstacles.hit(o, t, x, feet, d, r) then
				return false, o.kind, d
			end
		end
		if t - t0 > 200 then
			return false, "timeout", d
		end
	end
	return true, nil, nil
end

-- How often runs get through: runs a stage `runs` times with different seeds
function Bot.rate(stage: any, skill: Skill, runs: number, speedOverride: number?): (number, { [string]: number })
	local ok = 0
	local killers: { [string]: number } = {}
	for run = 1, runs do
		local passed, kind = Bot.run(stage, skill, stage.stage * 1009 + run * 37 + #skill.name * 101, speedOverride)
		if passed then
			ok += 1
		else
			killers[kind :: string] = (killers[kind :: string] or 0) + 1
		end
	end
	return ok / runs, killers
end

return Bot
