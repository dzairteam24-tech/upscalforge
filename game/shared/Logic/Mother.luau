--!strict
-- The Mother Cube's schedule and sums (Config/Mother): it comes on the clock, the same in every server.

local MotherConfig = require(script.Parent.Parent.Config.Mother)

local Mother = {}

-- When the visit that time t falls in (or the last one) started, and whether it's still on
function Mother.at(t: number, studio: boolean?): (boolean, number)
	local every = if studio then MotherConfig.STUDIO_EVERY else MotherConfig.EVERY
	local offset = if studio then MotherConfig.STUDIO_AT else MotherConfig.AT
	local start = t - (t - offset) % every
	return t - start < MotherConfig.LASTS, start
end

-- When the next visit starts (after time t)
function Mother.nextVisit(t: number, studio: boolean?): number
	local _, start = Mother.at(t, studio)
	return start + (if studio then MotherConfig.STUDIO_EVERY else MotherConfig.EVERY)
end

-- How many points it takes to fill it, for a server with this many players
function Mother.goal(players: number): number
	return math.max(MotherConfig.GOAL_MIN, MotherConfig.GOAL_PER_PLAYER * players)
end

-- What a snack costs a player whose garden earns `rate` a second
function Mother.snackPrice(rate: number): number
	return math.max(MotherConfig.SNACK_MIN, math.floor(rate * MotherConfig.SNACK_SECONDS))
end

-- A player's chance of a Legendary Egg, for the points they gave
function Mother.legendaryChance(points: number): number
	return math.min(MotherConfig.LEGENDARY_MAX, points * MotherConfig.LEGENDARY_PER_POINT)
end

return Mother
