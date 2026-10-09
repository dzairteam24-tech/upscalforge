--!strict
-- The Nest's math (Config/Nest): how long an egg incubates, what it costs, and the weather at any moment.
-- The weather follows the clock, so it's the same in every server and can be worked out for an egg that
-- finished while its owner was away.

local NestConfig = require(script.Parent.Parent.Config.Nest)
local World1 = require(script.Parent.Parent.Config.World1)

local Nest = {}

-- Seconds a zone's egg incubates: 1.5 min for zone 1, about 30 min for zone 10
function Nest.incubateSeconds(zoneId: number): number
	return math.floor(NestConfig.BASE_SECONDS * zoneId ^ 1.3)
end

-- Coins to put a zone's egg in an incubator
function Nest.eggPrice(zoneId: number): number
	local zone = World1.zonesById[zoneId]
	return if zone then zone.eggPrice * NestConfig.PRICE_MULT else math.huge
end

-- Coins for the next incubator, or nil when the player has them all
function Nest.slotPrice(slots: number): number?
	return NestConfig.SLOT_PRICES[slots - NestConfig.SLOTS_START + 1]
end

function Nest.maxSlots(): number
	return NestConfig.SLOTS_START + #NestConfig.SLOT_PRICES
end

-- The weather at a time (os.time()), and when it ends
function Nest.weatherAt(t: number): (NestConfig.Weather, number)
	local window = t // NestConfig.WEATHER_SECONDS
	-- A fixed shuffle of the window number (the same everywhere)
	local h = (window * 2654435761) % 4294967296
	h = ((h // 65536) * 40503 + window * 9973) % 1000003
	local total = 0
	for _, weather in NestConfig.WEATHERS do
		total += weather.weight
	end
	local roll = (h % total)
	local pick = NestConfig.WEATHERS[1]
	for _, weather in NestConfig.WEATHERS do
		if roll < weather.weight then
			pick = weather
			break
		end
		roll -= weather.weight
	end
	return pick, (window + 1) * NestConfig.WEATHER_SECONDS
end

return Nest
