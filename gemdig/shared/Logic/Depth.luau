--!strict
-- The elevator: your depth is saved in steps, and a mine that starts again (when you join, or press Reset) has a
-- cleared shaft down the middle to there.

local MineConfig = require(script.Parent.Parent.Config.Mine)

local Depth = {}

-- The last saved step at or above this deepest layer (0 = none)
function Depth.checkpoint(deepest: number): number
	local step = MineConfig.CHECKPOINT_EVERY
	return math.max(0, (math.max(deepest, 1) - 1) // step * step)
end

return Depth
