--!strict
-- What things cost and pay. Speed grows by collecting orbs (permanently); coins buy upgrades; a stage's wall of
-- cubes needs a speed stat to smash. All formulas here so the economy can be balanced by a simulation (tests).

local Course = require(script.Parent.Parent.Config.Course)
local Speed = require(script.Parent.Speed)

local Economy = {}

Economy.RUN_SECONDS = 38 -- a stage is this many seconds long at its planned walking speed
Economy.ORB_EVERY = 22 -- studs between orbs, on average
Economy.WALK_FIRST = 18.5 -- the walking speed stage 1 is planned for...
Economy.WALK_MORE = 3.3 -- ...and this much quicker for each stage further on

function Economy.plannedWalk(stage: number): number
	return Economy.WALK_FIRST + Economy.WALK_MORE * (math.min(stage, Course.STAGES) - 1)
end

-- How long a stage is (studs): about RUN_SECONDS of running at its planned speed
function Economy.stageLength(stage: number): number
	return math.floor(Economy.RUN_SECONDS * Economy.plannedWalk(stage) / 10 + 0.5) * 10
end

function Economy.orbsIn(stage: number): number
	return math.floor(Economy.stageLength(stage) / Economy.ORB_EVERY)
end

Economy.ORB_GROWTH = 2.2 -- an orb of each stage is worth this many times one of the stage before
Economy.ORB_UPGRADE = 0.15 -- each level of Orb Power: +15% speed from every orb
Economy.PLAN_SHARE = 0.7 -- the share of a stage's orbs a run is planned to pick up
Economy.RUNS_FIRST = 2 -- a stage's wall is planned to need this many runs of it (with no upgrades)...
Economy.RUNS_MORE = 3.5 -- ...and this many more for each stage further on

-- How many runs of a stage its wall is planned for, with no upgrades (stage 1: one)
function Economy.plannedRuns(stage: number): number
	if stage <= 1 then
		return 0.8 -- (the first wall breaks on the first run)
	end
	return Economy.RUNS_FIRST + Economy.RUNS_MORE * (stage - 2)
end

-- The speed stat a stage's wall needs: the one before plus the planned runs' worth of its orbs (rounded to two
-- figures: 20, 64, 230...)
local needsCache: { [number]: number } = {}
Economy._needsCache = needsCache -- (for the balancing tests)
function Economy.needs(stage: number): number
	if needsCache[stage] then
		return needsCache[stage]
	end
	local raw = 10 -- the base stat
	for k = 1, stage do
		raw += Economy.plannedRuns(k) * Economy.PLAN_SHARE * Economy.orbsIn(k) * Economy.orbWorth(k)
	end
	local round = 10 ^ math.max(0, math.floor(math.log10(raw)) - 1)
	local value = math.floor(raw / round + 0.5) * round
	needsCache[stage] = value
	return value
end

-- What an orb of a stage is worth before upgrades (later stages have richer orbs)
function Economy.orbWorth(stage: number): number
	return math.floor(Economy.ORB_GROWTH ^ (math.min(stage, Course.STAGES) - 1) + 0.5)
end

-- Coins for an orb of a stage (upgrades to Orb Power don't change it; Coin Gain does)
function Economy.orbCoins(stage: number): number
	return math.floor(Economy.COIN_GROWTH ^ (math.min(stage, Course.STAGES) - 1) + 0.5)
end
Economy.COIN_GROWTH = 1.7

-- Coins for smashing a stage's wall the first time, and for finishing a stage run after that
function Economy.wallCoins(stage: number): number
	return math.floor(25 * 1.7 ^ (stage - 1))
end
function Economy.finishCoins(stage: number): number
	return math.max(5, math.floor(Economy.wallCoins(stage) * 0.25))
end

Economy.REBIRTH_BONUS = 0.25 -- each rebirth: +25% orb value and coins
Economy.REBIRTH_COST = 200000 -- coins for the first, times REBIRTH_GROWTH for each one after
Economy.REBIRTH_GROWTH = 4

function Economy.rebirthCost(rebirths: number): number
	return math.floor(Economy.REBIRTH_COST * Economy.REBIRTH_GROWTH ^ rebirths)
end

-- The upgrades: name, how much each level costs (level = how many you have)
export type Upgrade = { key: string, name: string, desc: string, max: number, base: number, growth: number }
Economy.UPGRADES = {
	{ key = "orb", name = "Orb Power", desc = "+15% speed from every orb", max = 40, base = 30, growth = 1.55 },
	{ key = "coin", name = "Coin Gain", desc = "+25% coins from everything", max = 20, base = 60, growth = 1.7 },
	{ key = "magnet", name = "Magnet", desc = "Orbs fly to you from further away", max = 10, base = 80, growth = 2.1 },
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

-- How close an orb must be to fly to them (studs): the Magnet upgrade, doubled by the Super Magnet pass
Economy.MAGNET_BASE = 5
Economy.MAGNET_PER_LEVEL = 1.1
function Economy.magnetReach(level: number, pass: boolean): number
	local reach = Economy.MAGNET_BASE + Economy.MAGNET_PER_LEVEL * level
	return if pass then reach * 2 else reach
end

Economy.STAGES = Course.STAGES

return Economy
