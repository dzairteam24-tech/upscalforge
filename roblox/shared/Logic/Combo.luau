--!strict
-- Combo multiplier from the number of sources broken in a row.

local Constants = require(script.Parent.Parent.Config.Constants)

local Combo = {}

function Combo.multiplier(count: number): number
	for _, step in Constants.COMBO_STEPS do
		if count >= step.at then
			return step.mult
		end
	end
	return 1
end

return Combo
