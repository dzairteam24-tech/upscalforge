--!strict
-- What happens to a player's data when they collect an orb, smash a wall, finish a stage, buy an upgrade or
-- rebirth. Pure functions on the data table, so the rules are tested without the engine.

local Economy = require(script.Parent.Economy)
local Speed = require(script.Parent.Speed)

export type Data = {
	coins: number,
	speed: number, -- speed collected from orbs (the stat is the base plus this)
	stage: number, -- the furthest stage they may run (every stage before it has been smashed through)
	upgrades: { [string]: number },
	rebirths: number,
	passes: { [string]: boolean },
	boostUntil: number,
	stats: { orbs: number, smashes: number, falls: number, runs: number },
}

local Progress = {}

-- How much one orb of a stage is worth in speed now (the stage they are on if not said)
function Progress.orbValue(data: Data, stage: number?): number
	local level = data.upgrades.orb or 0
	local value = Economy.orbWorth(stage or math.min(data.stage, Economy.STAGES)) * (1 + Economy.ORB_UPGRADE * level) * (1 + Economy.REBIRTH_BONUS * data.rebirths)
	if data.passes.Orbs2 then
		value *= 2
	end
	return math.max(1, math.floor(value))
end

-- Coins multiplier: the coin upgrade, rebirths, the pass and a boost
function Progress.coinMultiplier(data: Data, now: number): number
	local m = 1 + 0.25 * (data.upgrades.coin or 0) + Economy.REBIRTH_BONUS * data.rebirths
	if data.passes.Coins2 then
		m += 1
	end
	if data.boostUntil > now then
		m += 1
	end
	if data.passes.Vip then
		m += 0.25
	end
	return m
end

function Progress.coins(base: number, data: Data, now: number): number
	return math.max(1, math.floor(base * Progress.coinMultiplier(data, now) + 0.5))
end

-- An orb of a stage picked up: speed and coins. Returns the speed gained and the coins
function Progress.pickup(data: Data, now: number, stage: number?): (number, number)
	local gain = Progress.orbValue(data, stage)
	data.speed += gain
	data.stats.orbs += 1
	local coins = Progress.coins(Economy.orbCoins(stage or math.min(data.stage, Economy.STAGES)), data, now)
	data.coins += coins
	return gain, coins
end

-- How close an orb must be to fly to them
function Progress.magnet(data: Data): number
	return Economy.magnetReach(data.upgrades.magnet or 0, data.passes.Magnet == true)
end

-- The stage they are running for (their furthest, or the last once the course is done)
function Progress.frontier(data: Data): number
	return math.min(data.stage, Economy.STAGES)
end

-- About how many coins a minute they make running their furthest stage (for the coin packs and daily reward)
function Progress.perMinute(data: Data, now: number): number
	local k = Progress.frontier(data)
	local perRun = Economy.orbsIn(k) * Economy.PLAN_SHARE * Economy.orbCoins(k) + Economy.finishCoins(k)
	local minutes = Economy.RUN_SECONDS * 1.5 / 60
	return math.floor(perRun * Progress.coinMultiplier(data, now) / minutes)
end

-- The speed stat now
function Progress.stat(data: Data): number
	return Speed.stat(data.speed)
end

-- Whether they can smash stage k's wall
function Progress.canSmash(data: Data, stage: number): boolean
	return stage == data.stage and Progress.stat(data) >= Economy.needs(stage)
end

-- Smashes the wall: the next stage opens, coins. Returns the coins, or nil if they can't
function Progress.smash(data: Data, stage: number, now: number): number?
	if not Progress.canSmash(data, stage) then
		return nil
	end
	local coins = Progress.coins(Economy.wallCoins(stage), data, now)
	data.coins += coins
	data.stage = math.min(Economy.STAGES + 1, data.stage + 1)
	data.stats.smashes += 1
	return coins
end

-- A finished run of an already smashed stage: a bonus
function Progress.finish(data: Data, stage: number, now: number): number
	local coins = Progress.coins(Economy.finishCoins(stage), data, now)
	data.coins += coins
	data.stats.runs += 1
	return coins
end

-- Buying the next level of an upgrade. Returns the new level, or nil with a reason
function Progress.buy(data: Data, key: string): (number?, string?)
	local upgrade = Economy.upgrade(key)
	if not upgrade then
		return nil, "unknown"
	end
	local level = data.upgrades[key] or 0
	if level >= upgrade.max then
		return nil, "max"
	end
	local cost = Economy.upgradeCost(upgrade, level)
	if data.coins < cost then
		return nil, "coins"
	end
	data.coins -= cost
	data.upgrades[key] = level + 1
	return level + 1, nil
end

-- Rebirth: they start the course again, but every orb and coin is worth more for good
function Progress.canRebirth(data: Data): (boolean, string?)
	if data.stage <= Economy.STAGES then
		return false, ("Smash the wall of stage %d first"):format(Economy.STAGES)
	end
	local cost = Economy.rebirthCost(data.rebirths)
	if data.coins < cost then
		return false, ("You need %d coins (you have %d)"):format(cost, math.floor(data.coins))
	end
	return true, nil
end

function Progress.rebirth(data: Data)
	data.coins -= Economy.rebirthCost(data.rebirths)
	data.rebirths += 1
	data.speed = 0
	data.stage = 1
	data.coins = 0
	data.upgrades = {}
end

return Progress
