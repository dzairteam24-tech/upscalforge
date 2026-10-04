-- Per-player runtime state that isn't saved (targets, combo, boosts, cached power).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Effects = require(Shared.Logic.Effects)

export type Boost = { mult: number, untilTime: number }

export type Runtime = {
	target: string?,
	auto: boolean,
	zoneId: number?,
	combo: number,
	lastBreak: number,
	lastTap: number,
	lastHatch: number,
	boosts: { [string]: Boost },
	timers: { [string]: number },
	effects: Effects.Effects,
	power: number, -- current coins per second in the player's zone
	strongest: number,
	vip: boolean,
	dirtyData: boolean, -- full data snapshot needs to be sent
	lastAction: { [string]: number }, -- simple rate limits
}

local State = {}

local runtimes: { [Player]: Runtime } = {}

function State.create(player: Player): Runtime
	local runtime: Runtime = {
		target = nil,
		auto = false,
		zoneId = nil,
		combo = 0,
		lastBreak = 0,
		lastTap = 0,
		lastHatch = 0,
		boosts = {},
		timers = {},
		effects = Effects.empty(),
		power = 0,
		strongest = 0,
		vip = false,
		dirtyData = true,
		lastAction = {},
	}
	runtimes[player] = runtime
	return runtime
end

function State.get(player: Player): Runtime?
	return runtimes[player]
end

function State.remove(player: Player)
	runtimes[player] = nil
end

function State.all(): { [Player]: Runtime }
	return runtimes
end

-- Active boost multiplier for a stat, or 1.
function State.boost(runtime: Runtime, stat: string, now: number): number
	local boost = runtime.boosts[stat]
	if boost and boost.untilTime > now then
		return boost.mult
	end
	return 1
end

function State.addBoost(runtime: Runtime, stat: string, mult: number, duration: number, now: number)
	local current = runtime.boosts[stat]
	if current and current.untilTime > now then
		current.mult = math.max(current.mult, mult)
		current.untilTime = math.max(current.untilTime, now + duration)
	else
		runtime.boosts[stat] = { mult = mult, untilTime = now + duration }
	end
end

-- Returns true if the action is allowed (at most once per `interval` seconds).
function State.throttle(runtime: Runtime, action: string, interval: number): boolean
	local now = os.clock()
	local last = runtime.lastAction[action]
	if last and now - last < interval then
		return false
	end
	runtime.lastAction[action] = now
	return true
end

return State
