--!strict
-- What the server tells a client about its player: a small picture of their data (the gems grouped, not each one).

local Backpack = require(script.Parent.Backpack)

local Snapshot = {}

function Snapshot.of(data: any): any
	return {
		coins = data.coins,
		shovel = data.shovel,
		pack = data.pack,
		used = Backpack.used(data),
		capacity = Backpack.capacity(data),
		groups = Backpack.groups(data),
		deepest = data.deepest,
		found = data.found,
		stats = data.stats,
	}
end

return Snapshot
