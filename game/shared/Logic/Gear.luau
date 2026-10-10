--!strict
-- The bat (Config/Gear): how many hits knock an egg out of someone's hands.

local GearConfig = require(script.Parent.Parent.Config.Gear)

local Gear = {}

-- Hits a player with bat `attacker` needs to knock the egg out of one with bat `target`
function Gear.hitsNeeded(attacker: number, target: number): number
	return math.clamp(GearConfig.HITS + target - attacker, 1, GearConfig.MAX_HITS)
end

-- The bat at a level, and what the next one costs (nil at the top)
function Gear.bat(level: number): GearConfig.Bat
	return GearConfig.BATS[math.clamp(level, 1, #GearConfig.BATS)]
end

function Gear.upgradePrice(level: number): number?
	local next = GearConfig.BATS[level + 1]
	return if next then next.price else nil
end

return Gear
