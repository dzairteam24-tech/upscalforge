--!strict
-- Egg Heist's schedule (Config/Heist): rounds on the clock, on weekend days only, so every server runs them
-- at the same times and players can plan for them.

local HeistConfig = require(script.Parent.Parent.Config.Heist)

local Heist = {}

-- Day of the week (UTC, 0 = Sunday) of a time (os.time())
function Heist.weekday(t: number): number
	-- 1 January 1970 was a Thursday
	return (t // 86400 + 4) % 7
end

-- Whether a round is on at time t, and when it started
function Heist.round(t: number, always: boolean?): (boolean, number)
	local start = t - t % HeistConfig.EVERY
	local on = (always or HeistConfig.WEEKEND_DAYS[Heist.weekday(start)] == true) and t - start < HeistConfig.ROUND
	return on, start
end

-- When the next round starts (from time t on)
function Heist.nextRound(t: number, always: boolean?): number
	local start = t - t % HeistConfig.EVERY + HeistConfig.EVERY
	for _ = 1, 7 * 86400 // HeistConfig.EVERY + 1 do
		if always or HeistConfig.WEEKEND_DAYS[Heist.weekday(start)] then
			return start
		end
		start += HeistConfig.EVERY
	end
	return start
end

-- What the Heist Egg holds, for a roll in [0, 1): an egg's tier, or nil when it's empty (Config/Heist PRIZES)
function Heist.prize(roll: number): number?
	local total = 0
	for _, prize in HeistConfig.PRIZES do
		total += prize.weight
	end
	local at = roll * total
	for _, prize in HeistConfig.PRIZES do
		at -= prize.weight
		if at < 0 then
			return if prize.tier > 0 then prize.tier else nil
		end
	end
	return nil
end

return Heist
