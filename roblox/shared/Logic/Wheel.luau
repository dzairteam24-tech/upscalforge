--!strict
-- Lucky Spin rolls and the free daily spin.

local Wheel = require(script.Parent.Parent.Config.Wheel)

local Logic = {}

function Logic.totalWeight(): number
	local total = 0
	for _, slice in Wheel.slices do
		total += slice.weight
	end
	return total
end

function Logic.chance(index: number): number
	local slice = Wheel.slices[index]
	return if slice then slice.weight / Logic.totalWeight() else 0
end

-- Index of the slice the spin lands on.
function Logic.spin(rng: () -> number): number
	local pick = rng() * Logic.totalWeight()
	for index, slice in Wheel.slices do
		pick -= slice.weight
		if pick < 0 then
			return index
		end
	end
	return #Wheel.slices
end

function Logic.freeReady(lastFreeDay: number, today: number): boolean
	return lastFreeDay ~= today
end

return Logic
