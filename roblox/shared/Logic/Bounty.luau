--!strict
-- Daily Bounty targets: the same three for a player all day (they're saved when the day starts).

local Config = script.Parent.Parent.Config
local Variants = require(Config.Variants)
local World1 = require(Config.World1)

export type Target = { tier: number, species: string, variant: string }

local Bounty = {}

-- Small deterministic random generator so a day always gives the same picks
local function seeded(seed: number): (number, number) -> number
	local state = (seed * 1103515245 + 12345) % 2147483648
	return function(lo: number, hi: number): number
		state = (state * 1103515245 + 12345) % 2147483648
		return lo + state % (hi - lo + 1)
	end
end

-- Three targets for a UTC day, from the zones the player reached (1..bestZone).
function Bounty.forDay(day: number, bestZone: number, userId: number?): { Target }
	local zones: { World1.Zone } = {}
	for _, zone in World1.zones do
		if zone.eggPrice > 0 and zone.id <= math.max(1, bestZone) then
			table.insert(zones, zone)
		end
	end
	local rand = seeded(day * 7919 + (userId or 0) % 100000)
	local function pickZone(): World1.Zone
		return zones[rand(1, #zones)]
	end
	local targets: { Target } = {}
	-- Easy: a common creature
	local easy = pickZone()
	table.insert(targets, { tier = 1, species = easy.species[rand(1, 2)], variant = "Normal" })
	-- Medium: an uncommon one, or a Golden common one
	local medium = pickZone()
	if rand(0, 1) == 0 then
		table.insert(targets, { tier = 2, species = medium.species[3], variant = "Normal" })
	else
		table.insert(targets, { tier = 2, species = medium.species[rand(1, 2)], variant = "Golden" })
	end
	-- Hard: from the furthest zone, the 1% creature, or a Golden uncommon one
	local hard = zones[#zones]
	if rand(0, 1) == 0 then
		table.insert(targets, { tier = 3, species = hard.species[4], variant = "Normal" })
	else
		table.insert(targets, { tier = 3, species = hard.species[3], variant = "Golden" })
	end
	return targets
end

-- A hatch counts when it's the right creature in the asked variant or a rarer one.
function Bounty.matches(target: Target, species: string, variant: string): boolean
	local want = Variants.byId[target.variant]
	local got = Variants.byId[variant]
	return species == target.species and want ~= nil and got ~= nil and got.order >= want.order
end

return Bounty
