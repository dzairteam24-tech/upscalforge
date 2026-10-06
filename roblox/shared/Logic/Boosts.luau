--!strict
-- Saved timed boosts (from elixirs and rewarded ads).
-- Each stat keeps one timer per multiplier. Only the strongest active one counts and only it ticks down,
-- so a short strong boost never wastes the time left on a weaker one. Time only passes while playing.
-- Shape in data: boosts[stat][tostring(mult)] = seconds left. String keys keep it DataStore-safe.

export type BoostMap = { [string]: { [string]: number } }

local Boosts = {}

function Boosts.add(boosts: BoostMap, stat: string, mult: number, seconds: number, cap: number): number
	local timers = boosts[stat]
	if not timers then
		timers = {}
		boosts[stat] = timers
	end
	local key = tostring(mult)
	local total = math.min(cap, (timers[key] or 0) + seconds)
	timers[key] = total
	return total
end

-- Seconds saved on one timer (a stat at one multiplier).
function Boosts.left(boosts: BoostMap, stat: string, mult: number): number
	local timers = boosts[stat]
	return if timers then timers[tostring(mult)] or 0 else 0
end

-- Strongest active multiplier for a stat, or 1.
function Boosts.active(boosts: BoostMap, stat: string): number
	local timers = boosts[stat]
	if not timers then
		return 1
	end
	local best = 1
	for key, seconds in timers do
		local mult = tonumber(key)
		if mult and seconds > 0 and mult > best then
			best = mult
		end
	end
	return best
end

-- Advances time. Returns the stats whose strongest multiplier changed.
function Boosts.tick(boosts: BoostMap, dt: number): { string }
	local changed = {}
	for stat, timers in boosts do
		local before = Boosts.active(boosts, stat)
		local key = tostring(before)
		if before > 1 and timers[key] then
			timers[key] -= dt
			if timers[key] <= 0 then
				timers[key] = nil
			end
		end
		for k, seconds in timers do
			if seconds <= 0 then
				timers[k] = nil
			end
		end
		if next(timers) == nil then
			boosts[stat] = nil
		end
		if Boosts.active(boosts, stat) ~= before then
			table.insert(changed, stat)
		end
	end
	return changed
end

-- For the UI: strongest multiplier and its time left, plus the total queued time.
function Boosts.summary(boosts: BoostMap): { [string]: { mult: number, left: number, queued: number } }
	local out = {}
	for stat, timers in boosts do
		local mult = Boosts.active(boosts, stat)
		local queued = 0
		for _, seconds in timers do
			queued += math.max(0, seconds)
		end
		if mult > 1 then
			out[stat] = { mult = mult, left = timers[tostring(mult)] or 0, queued = queued }
		end
	end
	return out
end

return Boosts
