--!strict
-- The Mutation Machine (Config/Mutate): the mutation a creature would get next, and what it costs.

local MutateConfig = require(script.Parent.Parent.Config.Mutate)
local Mutations = require(script.Parent.Parent.Config.Mutations)
local Earn = require(script.Parent.Earn)

local Mutate = {}

-- The next mutation up, or nil at the top
function Mutate.next(mutation: string): string?
	local current = Mutations.byId[mutation] or Mutations.byId.Normal
	for _, other in Mutations.list do
		if other.order == current.order + 1 then
			return other.id
		end
	end
	return nil
end

-- What raising this creature's mutation costs
function Mutate.price(creature: { s: string, m: string, g: string? }): number
	return math.floor(Earn.rate(creature :: any) * MutateConfig.COST_SECONDS)
end

-- Whether a player with this much ⚡ may use the machine
function Mutate.open(power: number): boolean
	return power >= MutateConfig.UNLOCK
end

return Mutate
