--!strict
-- The catching game (Config/Hunt): a marker sweeps back and forth along a bar; stopping it in the green catches
-- the creature. The server picks the green and the start time, so it can check a click on its own.

local HuntConfig = require(script.Parent.Parent.Config.Hunt)
local Hatch = require(script.Parent.Hatch)

local Hunt = {}

-- Where the marker is (0..1) `elapsed` seconds into the game
function Hunt.marker(elapsed: number, speed: number): number
	local p = (math.max(0, elapsed) * speed) % 2
	return if p <= 1 then p else 2 - p
end

-- Whether a click `elapsed` seconds in lands in the green (`center`, `width`)
function Hunt.hit(elapsed: number, speed: number, center: number, width: number): boolean
	return math.abs(Hunt.marker(elapsed, speed) - center) <= width / 2
end

-- The green's width and the marker's speed for a creature of `rarity` with `net`
function Hunt.bar(rarity: string, net: HuntConfig.Net): (number, number)
	local bar = HuntConfig.BAR[rarity] or HuntConfig.BAR.Common
	return math.min(HuntConfig.MAX_WIDTH, bar.width * net.mult), bar.speed
end

-- A net's price for a player whose best egg tier is `bestTier`
function Hunt.netPrice(net: HuntConfig.Net, bestTier: number): number
	if net.share == 0 then
		return 0
	end
	local egg = Hatch.egg(bestTier)
	return math.max(net.min, math.floor(net.share * (if egg then egg.price else 0)))
end

-- Whether a zone is open to a player whose best egg tier is `bestTier`
function Hunt.unlocked(zone: HuntConfig.Zone, bestTier: number): boolean
	return bestTier >= zone.need
end

return Hunt
