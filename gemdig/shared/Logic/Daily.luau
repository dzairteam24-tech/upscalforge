--!strict
-- The daily reward: once a day (UTC), a 7-day cycle that grows. A missed day just pauses the streak.

local Config = script.Parent.Parent.Config
local DailyConfig = require(Config.Daily)

export type Holder = { daily: { last: number, streak: number } }

local Daily = {}

function Daily.dayOf(now: number): number
	return now // 86400
end

-- Whether today's reward is waiting, and which day of the cycle it is
function Daily.status(data: Holder, now: number): (boolean, number)
	local cycle = #DailyConfig.REWARDS
	local nextIndex = data.daily.streak % cycle + 1
	return data.daily.last < Daily.dayOf(now), nextIndex
end

-- Claims it: the reward (income = coins worth `income` minutes of the player's own earnings, `perMinute`)
function Daily.claim(data: Holder, now: number, perMinute: number): (number, number, number)
	local ready, index = Daily.status(data, now)
	if not ready then
		return 0, 0, index
	end
	local reward = DailyConfig.REWARDS[index]
	local coins = math.max(reward.min, math.floor(reward.income * perMinute))
	data.daily.last = Daily.dayOf(now)
	data.daily.streak += 1
	return coins, reward.boost or 0, index
end

return Daily
