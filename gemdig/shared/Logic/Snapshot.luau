--!strict
-- What the server tells a client about its player: a small picture of their data (the gems grouped, not each one).

local Backpack = require(script.Parent.Backpack)
local Daily = require(script.Parent.Daily)
local Multiplier = require(script.Parent.Multiplier)
local Rebirth = require(script.Parent.Rebirth)

local Snapshot = {}

function Snapshot.of(data: any, now: number): any
	local dailyReady, dailyIndex = Daily.status(data, now)
	local canRebirth, rebirthWhy = Rebirth.can(data)
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
		rebirths = data.rebirths,
		multiplier = Multiplier.sell(data, now),
		boostLeft = math.max(0, data.boostUntil - now),
		passes = data.passes,
		dailyReady = dailyReady,
		dailyIndex = dailyIndex,
		rebirthCost = Rebirth.cost(data.rebirths),
		canRebirth = canRebirth,
		rebirthWhy = rebirthWhy,
		checkpoint = data.checkpoint,
	}
end

return Snapshot
