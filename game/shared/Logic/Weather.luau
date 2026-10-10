--!strict
-- The weather at any moment (Config/Weather). It follows the clock, so it's the same in every server and can
-- be worked out for an egg that finished while its owner was away.

local WeatherConfig = require(script.Parent.Parent.Config.Weather)
local Hash = require(script.Parent.Hash)

local Weather = {}

-- The weather at a time (os.time()), and when it ends
function Weather.at(t: number): (WeatherConfig.Weather, number)
	local window = t // WeatherConfig.SECONDS
	local total = 0
	for _, weather in WeatherConfig.LIST do
		total += weather.weight
	end
	local roll = Hash.unit(window, 7) * total
	local pick = WeatherConfig.LIST[1]
	for _, weather in WeatherConfig.LIST do
		if roll < weather.weight then
			pick = weather
			break
		end
		roll -= weather.weight
	end
	return pick, (window + 1) * WeatherConfig.SECONDS
end

return Weather
