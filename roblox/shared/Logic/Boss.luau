--!strict
-- World Boss math: when it comes, how much health it has, and what each fighter gets.

local Config = require(script.Parent.Parent.Config.Boss)

local Boss = {}

export type Tier = "full" | "small"

-- Unix time of the next boss strictly after `now`.
function Boss.nextSpawn(now: number): number
	local index = (now - Config.OFFSET) // Config.INTERVAL + 1
	return index * Config.INTERVAL + Config.OFFSET
end

function Boss.health(totalPower: number): number
	return math.max(Config.MIN_HEALTH, totalPower * Config.HEALTH_SECONDS)
end

-- How a fighter did: damage measured against their own team power, so weak and strong players are equal.
-- Taps count too, so a player with a weak team who keeps tapping still gets the reward.
function Boss.tier(damage: number, power: number): Tier?
	local seconds = damage / math.max(1, power)
	if seconds >= Config.FULL_SECONDS then
		return "full"
	elseif seconds >= Config.MIN_SECONDS then
		return "small"
	end
	return nil
end

-- Gems and tickets for a fighter. An escaped boss gives half; a small part gives a third.
function Boss.reward(tier: Tier, bestZone: number, defeated: boolean): { gems: number, tickets: number }
	local gems = Config.GEMS_BASE + Config.GEMS_PER_ZONE * math.max(1, bestZone)
	local tickets = Config.TICKETS
	if tier == "small" then
		gems //= 3
		tickets = 1
	end
	if not defeated then
		gems //= 2
		tickets = 0
	end
	return { gems = gems, tickets = tickets }
end

return Boss
