--!strict
-- Daily limits and cooldowns for rewarded ads, so each reward stays special.

local Products = require(script.Parent.Parent.Config.Products)
local Types = require(script.Parent.Types)

type AdState = Types.AdState

local AdLimits = {}

-- Starts a new count when the UTC day changes.
function AdLimits.refresh(state: AdState, today: number)
	if state.day ~= today then
		state.day = today
		state.counts = {}
	end
end

function AdLimits.left(state: AdState, key: string, today: number): number?
	local reward = Products.adByKey[key]
	if not reward or not reward.dailyLimit then
		return nil
	end
	local used = if state.day == today then state.counts[key] or 0 else 0
	return math.max(0, reward.dailyLimit - used)
end

-- Seconds until the reward can be watched again (0 when ready).
function AdLimits.cooldownLeft(state: AdState, key: string, now: number): number
	return math.max(0, (state.cooldowns[key] or 0) - now)
end

function AdLimits.canWatch(state: AdState, key: string, now: number, today: number): (boolean, string?)
	local reward = Products.adByKey[key]
	if not reward then
		return false, "Unknown reward"
	end
	local left = AdLimits.left(state, key, today)
	if left and left <= 0 then
		return false, "No more of these today. Come back tomorrow!"
	end
	if AdLimits.cooldownLeft(state, key, now) > 0 then
		return false, "This reward is still recharging"
	end
	return true, nil
end

-- Counts a granted reward.
function AdLimits.record(state: AdState, key: string, now: number, today: number)
	local reward = Products.adByKey[key]
	AdLimits.refresh(state, today)
	state.counts[key] = (state.counts[key] or 0) + 1
	if reward and reward.cooldown then
		state.cooldowns[key] = now + reward.cooldown
	end
end

return AdLimits
