--!strict
-- Journey progress: the current step and how far it got.

local Config = script.Parent.Parent.Config
local JourneyConfig = require(Config.Journey)

export type State = { step: number, progress: number }

local Journey = {}

function Journey.current(state: State): JourneyConfig.Step?
	return JourneyConfig.steps[state.step]
end

function Journey.isDone(state: State): boolean
	local step = Journey.current(state)
	return step ~= nil and state.progress >= step.goal
end

-- Counts a progress event for the current step. Returns true when the step just got done.
function Journey.onEvent(state: State, event: string, amount: number): boolean
	local step = Journey.current(state)
	if not step or step.event ~= event or state.progress >= step.goal then
		return false
	end
	if step.max then
		state.progress = math.max(state.progress, amount)
	else
		state.progress += amount
	end
	return state.progress >= step.goal
end

-- Moves to the next step. `already` gives what the player already has for "max" steps (best zone, reloads),
-- so a step that is already true starts done.
function Journey.advance(state: State, already: { [string]: number })
	state.step += 1
	state.progress = 0
	local step = Journey.current(state)
	if step and step.max then
		state.progress = already[step.event] or 0
	end
end

return Journey
