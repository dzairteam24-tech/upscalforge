--!strict
-- The stacking loop as pure whole-number maths: a block slides back and forth over the tower (along x on even
-- layers, z on odd ones); a tap drops it. Close enough to dead center it snaps exactly (a perfect); otherwise the
-- overhang is cut off; past the edge, the run is over. The phone plays it for instant feedback, the server
-- replays the same tap times and must get the same result.

local Stack = require(script.Parent.Parent.Config.Stack)

export type State = {
	preset: Stack.Preset,
	layer: number, -- blocks placed
	w: number, -- top block's size along x...
	d: number, -- ...and z
	cx: number, -- its center
	cz: number,
	combo: number, -- perfects in a row
	perfects: number,
	over: boolean,
}

export type Cut = { axis: string, center: number, size: number }
export type Outcome = { kind: string, cut: Cut? } -- kind: "perfect", "cut" or "miss"

local StackSim = {}

function StackSim.new(presetKey: string?): State
	local preset = Stack.PRESETS[presetKey or Stack.DEFAULT] or Stack.PRESETS[Stack.DEFAULT]
	return { preset = preset, layer = 0, w = preset.start, d = preset.start, cx = 0, cz = 0, combo = 0, perfects = 0, over = false }
end

-- Which way the next block slides
function StackSim.axis(state: State): string
	return if state.layer % 2 == 0 then "x" else "z"
end

function StackSim.speed(state: State): number
	local p = state.preset
	return math.min(p.maxSpeed, p.speed + p.perLayer * state.layer)
end

-- Where the sliding block's center is, relative to the top block's center, `t` ms after it appeared
function StackSim.offset(state: State, t: number): number
	local span = state.preset.span
	local travelled = (math.max(0, math.floor(t)) * StackSim.speed(state)) // 1000
	local u = travelled % (4 * span)
	return if u <= 2 * span then -span + u else 3 * span - u
end

-- The tap time that lands dead center (the first pass); bots aim for it
function StackSim.idealTime(state: State): number
	return math.ceil(state.preset.span * 1000 / StackSim.speed(state))
end

-- How far from center still counts as perfect, in units
function StackSim.window(state: State): number
	local p = state.preset
	local ms = math.max(p.perfectMinMs, p.perfectMs - state.layer // p.shrinkEvery)
	local w = (ms * StackSim.speed(state)) // 1000
	return if state.layer < p.easyLayers then w * p.easyFactor else w
end

-- Drops the block `t` ms after it appeared
function StackSim.tap(state: State, t: number): Outcome
	if state.over then
		return { kind = "miss" }
	end
	local p = state.preset
	local axis = StackSim.axis(state)
	local delta = StackSim.offset(state, t)
	local size = if axis == "x" then state.w else state.d
	local center = if axis == "x" then state.cx else state.cz
	local distance = math.abs(delta)
	if distance <= StackSim.window(state) then
		state.combo += 1
		state.perfects += 1
		if state.combo % p.regrowEvery == 0 then
			size = math.min(p.start, size + p.regrow)
		end
		state.layer += 1
		if axis == "x" then
			state.w = size
		else
			state.d = size
		end
		return { kind = "perfect" }
	end
	local kept = size - distance
	if kept <= 0 then
		state.over = true
		return { kind = "miss" }
	end
	state.combo = 0
	local sign = if delta > 0 then 1 else -1
	-- (the kept part is the overlap; the cut part hangs off on the block's side)
	local keptCenter = center + sign * (distance // 2)
	local cutCenter = center + sign * ((size + distance) // 2)
	state.layer += 1
	if axis == "x" then
		state.w, state.cx = kept, keptCenter
	else
		state.d, state.cz = kept, keptCenter
	end
	return { kind = "cut", cut = { axis = axis, center = cutCenter, size = distance } }
end

-- Plays a whole run from its tap times (ms after each block appeared). Taps after the run ended are ignored.
function StackSim.replay(presetKey: string?, taps: { number }): State
	local state = StackSim.new(presetKey)
	for _, t in taps do
		if state.over then
			break
		end
		StackSim.tap(state, t)
	end
	return state
end

-- The tier a run of this many layers earns (nil below the first)
function StackSim.tier(layers: number): string?
	local found: string? = nil
	for _, tier in Stack.TIERS do
		if layers >= tier.layers then
			found = tier.name
		end
	end
	return found
end

return StackSim
