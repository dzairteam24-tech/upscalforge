--!strict
-- What the server tells a client about its player: their data, and the numbers worked out from it.

local Land = require(script.Parent.Land)
local Level = require(script.Parent.Level)

local Snapshot = {}

function Snapshot.of(data: any, farm: number?): any
	local level, share = Level.of(data.xp)
	local full = data.tiles >= Land.MAX
	return {
		farm = farm, -- which farm of the village is theirs
		coins = data.coins,
		xp = data.xp,
		level = level,
		levelShare = share,
		tiles = data.tiles,
		plots = data.plots,
		seeds = data.seeds,
		barn = data.barn,
		stats = data.stats,
		guide = data.guide,
		nextTileCost = if full then nil else Land.cost(data.tiles + 1),
		nextTileLevel = if full then nil else Land.level(data.tiles + 1),
	}
end

return Snapshot
