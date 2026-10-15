-- Cubedash's pacing: a simulated player runs their furthest stage again and again, picks up most of the orbs,
-- smashes the wall when fast enough and buys upgrades as soon as it can. How long the course and the rebirths take.
-- Run from the repo root:  lune run tests/cubedash_economy.luau

local process = require("@lune/process")
local Loader = require("./loader")
local Shared = Loader.root("cubedash/shared", "Shared")
local Economy = Loader.require(Shared.Logic.Economy)
local Progress = Loader.require(Shared.Logic.Progress)
local Speed = Loader.require(Shared.Logic.Speed)

local passed, failed = 0, 0
local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (if detail then " (" .. detail .. ")" else ""))
	end
end

local OVERHEAD = 1.5 -- deaths, the walk back, menus: a run of the stage takes this many times its running time
local function newData(): any
	return { coins = 0, speed = 0, stage = 1, upgrades = {}, rebirths = 0, passes = {}, boostUntil = 0, stats = { orbs = 0, smashes = 0, falls = 0, runs = 0 } }
end

-- buys the cheapest thing it can, again and again
local function shop(data: any)
	while true do
		local best, bestCost = nil, math.huge
		for _, u in Economy.UPGRADES do
			local level = data.upgrades[u.key] or 0
			if level < u.max then
				local cost = Economy.upgradeCost(u, level)
				if cost < bestCost then
					best, bestCost = u.key, cost
				end
			end
		end
		if not best or bestCost > data.coins then
			return
		end
		Progress.buy(data, best)
	end
end

-- one run of the furthest stage: returns the seconds it took
local function run(data: any): number
	local k = math.min(data.stage, Economy.STAGES)
	local walk = Speed.walk(Progress.stat(data))
	local share = math.min(0.95, 0.7 + 0.025 * (data.upgrades.magnet or 0))
	for _ = 1, math.floor(Economy.orbsIn(k) * share) do
		Progress.pickup(data, 0, k)
	end
	if data.stage <= Economy.STAGES and Progress.canSmash(data, k) then
		Progress.smash(data, k, 0)
	else
		Progress.finish(data, k, 0)
	end
	shop(data)
	return Economy.stageLength(k) / walk * OVERHEAD + 6
end

local function play(label: string, data: any, untilFn: (any) -> boolean, log: boolean): number
	local t, runs = 0, 0
	local lastStage = data.stage
	local runsAt = 0
	while not untilFn(data) and t < 20 * 3600 do
		t += run(data)
		runs += 1
		runsAt += 1
		if log and data.stage ~= lastStage then
			print(string.format("  %s: stage %2d smashed after %2d runs, at %5.1f min  (speed %6d, orb x%d, coins %d)", label, lastStage, runsAt, t / 60, Progress.stat(data), Progress.orbValue(data), data.coins))
			lastStage, runsAt = data.stage, 0
		end
	end
	return t
end

print("first time through the course:")
local data = newData()
local runsPerStage = {}
do
	local t, lastStage, runsAt = 0, 1, 0
	while data.stage <= Economy.STAGES and t < 20 * 3600 do
		t += run(data)
		runsAt += 1
		if data.stage ~= lastStage then
			runsPerStage[lastStage] = runsAt
			print(string.format("  stage %2d smashed after %2d runs, at %5.1f min  (speed %6d, orb +%d, coins left %d)", lastStage, runsAt, t / 60, Progress.stat(data), Progress.orbValue(data), data.coins))
			lastStage, runsAt = data.stage, 0
		end
	end
	local minutes = t / 60
	check("the first time through takes 40 to 80 minutes", minutes >= 40 and minutes <= 80, ("%.1f"):format(minutes))
	check("stage 1 smashes on the first run", runsPerStage[1] == 1, tostring(runsPerStage[1]))
	local grind = 0
	for k = 3, Economy.STAGES do
		if runsPerStage[k] >= 2 and runsPerStage[k] <= 9 then
			grind += 1
		end
	end
	check("later stages need a few runs each, never a long grind", grind >= 7, tostring(grind))
	local toRebirth = play("rebirth", data, function(d)
		return select(1, Progress.canRebirth(d))
	end, false)
	print(string.format("  then %.1f more minutes for the first rebirth", toRebirth / 60))
	check("the first rebirth comes 10 to 40 minutes after the course", toRebirth / 60 >= 10 and toRebirth / 60 <= 40, ("%.1f"):format(toRebirth / 60))
	local before = (t + toRebirth) / 60
	Progress.rebirth(data)
	local second = play("again", data, function(d)
		return d.stage > Economy.STAGES
	end, false) / 60
	print(string.format("  after rebirth 1, the course again takes %.1f min (first time %.1f)", second, minutes))
	check("each rebirth makes the course quicker", second < minutes * 0.85 and second > minutes * 0.3, ("%.1f vs %.1f"):format(second, minutes))
	local _ = before
end

-- 2x Orbs (the gamepass) is a convenience: quicker, not a different game
do
	local d = newData()
	d.passes.Orbs2 = true
	local t = play("2x", d, function(x)
		return x.stage > Economy.STAGES
	end, false) / 60
	print(string.format("with 2x Orbs the course takes %.1f min", t))
	check("2x Orbs saves time but the course is still a course", t >= 20, ("%.1f"):format(t))
end

print(("%d passed, %d failed"):format(passed, failed))
process.exit(if failed > 0 then 1 else 0)
