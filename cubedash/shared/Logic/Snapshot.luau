--!strict
-- What the server tells a client about its player: their data, and the numbers worked out from it.

local Daily = require(script.Parent.Daily)
local Economy = require(script.Parent.Economy)
local Progress = require(script.Parent.Progress)

local Snapshot = {}

function Snapshot.of(data: any, now: number): any
	local dailyReady, dailyIndex = Daily.status(data, now)
	local canRebirth, rebirthWhy = Progress.canRebirth(data)
	local done = data.stage > Economy.STAGES
	return {
		coins = data.coins,
		speed = data.speed,
		stat = Progress.stat(data),
		stage = data.stage, -- their furthest stage (STAGES + 1 once the last wall is smashed)
		needs = if done then nil else Economy.needs(data.stage),
		upgrades = data.upgrades,
		rebirths = data.rebirths,
		passes = data.passes,
		boostLeft = math.max(0, data.boostUntil - now),
		multiplier = Progress.coinMultiplier(data, now),
		magnet = Progress.magnet(data),
		dailyReady = dailyReady,
		dailyIndex = dailyIndex,
		rebirthCost = Economy.rebirthCost(data.rebirths),
		canRebirth = canRebirth,
		rebirthWhy = rebirthWhy,
		guide = data.guide,
		stats = data.stats,
	}
end

return Snapshot
