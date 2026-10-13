--!strict
-- The drone: what it earned while the player was away.

local OfflineConfig = require(script.Parent.Parent.Config.Offline)

local Offline = {}

-- Seconds of work that count (capped), for a player with or without the Long Offline Miner pass
function Offline.counted(awaySeconds: number, longPass: boolean): number
	local cap = (if longPass then OfflineConfig.PASS_HOURS else OfflineConfig.FREE_HOURS) * 3600
	return math.max(0, math.min(awaySeconds, cap))
end

-- The coins: a share of what they earn by hand per minute (`perMinute`), times what they sell for (`multiplier`)
function Offline.coins(awaySeconds: number, longPass: boolean, perMinute: number, multiplier: number): number
	if awaySeconds < OfflineConfig.MIN_AWAY then
		return 0
	end
	return math.floor(Offline.counted(awaySeconds, longPass) / 60 * perMinute * OfflineConfig.RATE * multiplier)
end

return Offline
