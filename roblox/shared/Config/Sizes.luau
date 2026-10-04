--!strict
-- Size tiers. Big and Titan use the species' Big/Titan skills.

local Constants = require(script.Parent.Constants)

export type Size = {
	id: string,
	order: number,
	mult: number,
	chance: number,
	scale: number, -- visual scale of the model
}

local list: { Size } = {
	{ id = "Normal", order = 1, mult = 1, chance = 0, scale = 1 },
	{ id = "Big", order = 2, mult = Constants.BIG_POWER_MULT, chance = 1 / 10000, scale = 1.7 },
	{ id = "Titan", order = 3, mult = Constants.TITAN_POWER_MULT, chance = 1 / 2000000, scale = 2.8 },
}

local byId: { [string]: Size } = {}
for _, size in list do
	byId[size.id] = size
end

return {
	list = list,
	byId = byId,
}
