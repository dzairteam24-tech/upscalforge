--!strict
-- Raid Time's schedule (Config/Raid): the gates open on the clock, the same in every server.

local RaidConfig = require(script.Parent.Parent.Config.Raid)

local Raid = {}

-- Whether the gates are open at time t, and when that changes next
function Raid.at(t: number): (boolean, number)
	local start = t - t % RaidConfig.EVERY
	if t - start < RaidConfig.OPEN then
		return true, start + RaidConfig.OPEN
	end
	return false, start + RaidConfig.EVERY
end

return Raid
