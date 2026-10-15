--!strict
-- How far along a planted crop is. It grows on the clock (seconds since it was planted), so it keeps growing while
-- its farmer is away, and every screen agrees.

local Growth = {}

Growth.STAGES = 4 -- 1 a sprout, 2 young, 3 nearly there, 4 ready

-- 0..1
function Growth.progress(planted: number, grow: number, now: number): number
	if grow <= 0 then
		return 1
	end
	return math.clamp((now - planted) / grow, 0, 1)
end

function Growth.ready(planted: number, grow: number, now: number): boolean
	return now - planted >= grow
end

-- Which stage it shows (1..4)
function Growth.stage(planted: number, grow: number, now: number): number
	local p = Growth.progress(planted, grow, now)
	if p >= 1 then
		return 4
	elseif p >= 0.6 then
		return 3
	elseif p >= 0.25 then
		return 2
	end
	return 1
end

-- Seconds until ready
function Growth.left(planted: number, grow: number, now: number): number
	return math.max(0, planted + grow - now)
end

return Growth
