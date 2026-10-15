--!strict
-- What things cost and pay. Speed grows by collecting orbs (permanently); coins buy upgrades; a stage's wall of
-- cubes needs a speed stat to smash. All formulas here so the economy can be balanced by a simulation (tests).

local Course = require(script.Parent.Parent.Config.Course)
local Speed = require(script.Parent.Speed)

local Economy = {}

Economy.RUN_SECONDS = 38 -- a stage is this many seconds long at the walking speed of someone who can just smash its wall
Economy.ORB_EVERY = 22 -- studs between orbs, on average

-- How long a stage is (studs): about RUN_SECONDS of running
function Economy.stageLength(stage: number): number
	return math.floor(Economy.RUN_SECONDS * Speed.walk(Economy.needs(stage)) / 10 + 0.5) * 10
end

function Economy.orbsIn(stage: number): number
	return math.floor(Economy.stageLength(stage) / Economy.ORB_EVERY)
end

-- The speed stat a stage's wall needs
function Economy.needs(stage: number): number
	return math.floor(20 + 14 * (stage - 1) ^ 1.5)
end

-- Coins for smashing a stage's wall the first time, and for finishing a stage run after that
function Economy.wallCoins(stage: number): number
	return math.floor(25 * 1.7 ^ (stage - 1))
end
function Economy.finishCoins(stage: number): number
	return math.max(5, math.floor(Economy.wallCoins(stage) * 0.25))
end

Economy.REBIRTH_BONUS = 0.25 -- each rebirth: +25% orb value and coins
Economy.REBIRTH_COST = 20000 -- coins for the first, times REBIRTH_GROWTH for each one after
Economy.REBIRTH_GROWTH = 4

function Economy.rebirthCost(rebirths: number): number
	return math.floor(Economy.REBIRTH_COST * Economy.REBIRTH_GROWTH ^ rebirths)
end

-- The upgrades: name, how much each level costs (level = how many you have)
export type Upgrade = { key: string, name: string, desc: string, max: number, base: number, growth: number }
Economy.UPGRADES = {
	{ key = "orb", name = "Orb Power", desc = "Each orb gives more speed", max = 40, base = 30, growth = 1.55 },
	{ key = "coin", name = "Coin Gain", desc = "+25% coins from everything", max = 20, base = 60, growth = 1.7 },
	{ key = "magnet", name = "Magnet", desc = "Orbs fly to you from further away", max = 10, base = 80, growth = 1.8 },
} :: { Upgrade }

function Economy.upgrade(key: string): Upgrade?
	for _, u in Economy.UPGRADES do
		if u.key == key then
			return u
		end
	end
	return nil
end

-- What the next level of an upgrade costs (level = the ones they have now)
function Economy.upgradeCost(upgrade: Upgrade, level: number): number
	return math.floor(upgrade.base * upgrade.growth ^ level)
end

Economy.STAGES = Course.STAGES

return Economy
