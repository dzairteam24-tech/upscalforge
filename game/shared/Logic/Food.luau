--!strict
-- Feeding the creatures (Config/Food): what a food costs, and the boost it gives, online and offline.

local FoodConfig = require(script.Parent.Parent.Config.Food)
local IslandConfig = require(script.Parent.Parent.Config.Island)

local Food = {}

-- A food's price for an island earning `rate` a second: a share of the extra coins it brings, at least its min
function Food.price(food: FoodConfig.Food, rate: number): number
	return math.max(food.min, math.floor(rate * (FoodConfig.BOOST - 1) * food.minutes * 60 * FoodConfig.SHARE))
end

-- Whether the creatures are fed at `now`
function Food.fed(fedUntil: number, now: number): boolean
	return fedUntil > now
end

-- When the creatures are fed until after eating `food` at `now` (it adds up, to at most MAX_FED ahead)
function Food.feed(fedUntil: number, now: number, food: FoodConfig.Food): number
	return math.min(math.max(fedUntil, now) + food.minutes * 60, now + FoodConfig.MAX_FED)
end

-- The extra coins the boost brought while the owner was away (from `lastSeen` to `now`, up to OFFLINE_HOURS)
function Food.offlineBonus(rate: number, lastSeen: number, fedUntil: number, now: number): number
	local stop = math.min(fedUntil, now, lastSeen + IslandConfig.OFFLINE_HOURS * 3600)
	return math.floor(rate * (FoodConfig.BOOST - 1) * math.max(0, stop - lastSeen))
end

return Food
