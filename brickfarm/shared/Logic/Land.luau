--!strict
-- Land: a farm starts with a few tiles and buys the rest one at a time, for coins and once it is a high enough level.

local FarmConfig = require(script.Parent.Parent.Config.Farm)

local Land = {}

Land.MAX = FarmConfig.COLUMNS * FarmConfig.ROWS
Land.START = FarmConfig.START_TILES

-- What tile n costs (n = how many tiles they'll have with it), and the level it needs
function Land.cost(n: number): number
	return math.floor(40 * 1.33 ^ (n - Land.START - 1) / 5 + 0.5) * 5
end

function Land.level(n: number): number
	return 1 + (n - Land.START - 1) * 5 // 6
end

-- Whether they can buy the next tile, and why not
function Land.canExpand(tiles: number, coins: number, level: number): (boolean, string?)
	if tiles >= Land.MAX then
		return false, "Your farm is as big as it gets"
	end
	local n = tiles + 1
	if level < Land.level(n) then
		return false, ("More land at level %d"):format(Land.level(n))
	end
	if coins < Land.cost(n) then
		return false, "Not enough coins yet"
	end
	return true, nil
end

return Land
