--!strict
-- What the server tells a client about its player: their data, and the numbers worked out from it.

local Land = require(script.Parent.Land)
local Level = require(script.Parent.Level)

local Snapshot = {}

function Snapshot.of(data: any, farm: number?): any
	local level, share = Level.of(data.xp)
	return {
		farm = farm, -- which farm of the village is theirs
		coins = data.coins,
		xp = data.xp,
		level = level,
		levelShare = share,
		lots = data.lots,
		lotCost = Land.cost(Land.count(data.lots)),
		plots = data.plots,
		seeds = data.seeds,
		barn = data.barn,
		stand = data.stand,
		orders = data.orders,
		swapAt = data.swapAt,
		stats = data.stats,
		guide = data.guide,
	}
end

return Snapshot
