--!strict
-- Raid Time's schedule (Config/Raid): the gates open on the clock, the same in every server.

local RaidConfig = require(script.Parent.Parent.Config.Raid)
local Mutations = require(script.Parent.Parent.Config.Mutations)
local SnapConfig = require(script.Parent.Parent.Config.Snap)
local Earn = require(script.Parent.Earn)

local Raid = {}

-- Whether the gates are open at time t, and when that changes next
function Raid.at(t: number): (boolean, number)
	local start = t - t % RaidConfig.EVERY
	if t - start < RaidConfig.OPEN then
		return true, start + RaidConfig.OPEN
	end
	return false, start + RaidConfig.EVERY
end

export type Guards = { power: number, lava: boolean, crystal: boolean, neon: boolean }

-- How well the creatures living in a garden guard it: their power adds up (a creature's mutation order), and the
-- special mutations each bring their trick
function Raid.guards(creatures: { [string]: Earn.Owned }, placed: { string }): Guards
	local guards = { power = 0, lava = false, crystal = false, neon = false }
	for _, id in placed do
		local creature = creatures[id]
		if creature then
			local mutation = Mutations.byId[creature.m] or Mutations.byId.Normal
			local grade = if creature.g then SnapConfig.byId[creature.g] else nil
			guards.power += mutation.order * (if grade then grade.guard else 1)
			guards.lava = guards.lava or creature.m == "Lava"
			guards.crystal = guards.crystal or creature.m == "Crystal"
			guards.neon = guards.neon or creature.m == "Neon"
		end
	end
	return guards
end

-- The chance, each second, that the guards bump into a thief
function Raid.bumpChance(power: number): number
	return math.min(RaidConfig.GUARD_MAX_CHANCE, power * RaidConfig.GUARD_CHANCE)
end

return Raid
