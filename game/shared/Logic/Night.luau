--!strict
-- When it's night (Config/Night: the last LENGTH seconds of every CYCLE, on the clock), and how much an egg
-- grows between two times, nights counting SPEED times: when an egg set down at `start` that needs `seconds`
-- of growing is done. The same on the server and on every screen.

local NightConfig = require(script.Parent.Parent.Config.Night)

local Night = {}

local CYCLE, LENGTH, SPEED = NightConfig.CYCLE, NightConfig.LENGTH, NightConfig.SPEED

-- Whether it's night at time t
function Night.isNight(t: number): boolean
	return t % CYCLE >= CYCLE - LENGTH
end

-- When the night going on at t ends, or when the next one starts and ends
function Night.window(t: number): (number, number)
	local base = t - t % CYCLE
	return base + CYCLE - LENGTH, base + CYCLE
end

-- Seconds of night between a and b
function Night.overlap(a: number, b: number): number
	if b <= a then
		return 0
	end
	local total = 0
	local base = a - a % CYCLE
	while base < b do
		local from, to = base + CYCLE - LENGTH, base + CYCLE
		total += math.max(0, math.min(b, to) - math.max(a, from))
		base += CYCLE
	end
	return total
end

-- How much an egg grows between a and b (seconds of day count once, of night SPEED times)
function Night.growth(a: number, b: number): number
	if b <= a then
		return 0
	end
	return (b - a) + (SPEED - 1) * Night.overlap(a, b)
end

-- When an egg set down at `start` that needs `seconds` of growing is done
function Night.doneAt(start: number, seconds: number): number
	local t, left = start, seconds
	for _ = 1, 100000 do
		local from, to = Night.window(t)
		if t >= from then -- (night)
			local can = (to - t) * SPEED
			if left <= can then
				return t + left / SPEED
			end
			left -= can
			t = to
		else
			local can = from - t
			if left <= can then
				return t + left
			end
			left -= can
			t = from
		end
	end
	return t
end

return Night
