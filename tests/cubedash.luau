-- Cubedash's pure logic: the course (stages, obstacles, orbs), speed, the economy and progression, and bots that
-- run the stages to measure how hard each one is. Run from the repo root:  lune run tests/cubedash.luau

local process = require("@lune/process")
local Loader = require("./loader")

local Shared = Loader.root("cubedash/shared", "Shared")
local Rng = Loader.require(Shared.Logic.Rng)
local Obstacles = Loader.require(Shared.Logic.Obstacles)
local Stage = Loader.require(Shared.Logic.Stage)
local Layout = Loader.require(Shared.Logic.Layout)
local Speed = Loader.require(Shared.Logic.Speed)
local SpeedConfig = Loader.require(Shared.Config.Speed)
local Economy = Loader.require(Shared.Logic.Economy)
local Progress = Loader.require(Shared.Logic.Progress)
local CourseConfig = Loader.require(Shared.Config.Course)

local passed, failed = 0, 0
local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (if detail then " (" .. detail .. ")" else ""))
	end
end

-- Rng
do
	local a, b = Rng.new(5), Rng.new(5)
	local same = true
	for _ = 1, 100 do
		if Rng.float(a) ~= Rng.float(b) then
			same = false
		end
	end
	check("the same seed gives the same numbers", same)
	local r = Rng.new(99)
	local inRange, ints = true, { [1] = 0, [2] = 0, [3] = 0 }
	for _ = 1, 3000 do
		local f = Rng.float(r)
		if f < 0 or f >= 1 then
			inRange = false
		end
		ints[Rng.int(r, 1, 3)] += 1
	end
	check("floats are in [0, 1)", inRange)
	check("ints cover their range evenly", ints[1] > 800 and ints[2] > 800 and ints[3] > 800)
	check("another seed another numbers", Rng.float(Rng.new(1)) ~= Rng.float(Rng.new(2)))
end

-- Speed
do
	check("the base stat walks at the minimum", math.abs(Speed.walk(Speed.stat(0)) - SpeedConfig.WALK_MIN) < 1e-9)
	check("faster stat, faster walking", Speed.walk(100) < Speed.walk(200) and Speed.walk(200) < Speed.walk(1000))
	check("but never past the ceiling", Speed.walk(1e9) <= SpeedConfig.WALK_MAX + 1e-9 and Speed.walk(1e9) > SpeedConfig.WALK_MAX - 1)
	check("the view widens with speed, within its limits", Speed.fov(SpeedConfig.BASE) == SpeedConfig.FOV_MIN and Speed.fov(1e9) <= SpeedConfig.FOV_MAX and Speed.fov(300) > Speed.fov(50))
	check("how fast it feels is 0..1", Speed.feel(SpeedConfig.BASE) == 0 and Speed.feel(1e9) <= 1 and Speed.feel(300) > 0.2)
end

-- Obstacles: each kind, hit and miss at known moments
do
	local sweeper: any = { kind = "sweeper", d = 100, w = 20, amp = 12, omega = 1, phase = 0 }
	check("sweeper: starts in the middle", math.abs(Obstacles.sweeperX(sweeper, 0)) < 1e-9)
	check("sweeper: hits a runner in its path", Obstacles.hit(sweeper, 0, 0, 0, 100, 2))
	check("sweeper: misses one past its edge", not Obstacles.hit(sweeper, 0, 15, 0, 100, 2))
	check("sweeper: misses one before or after it", not Obstacles.hit(sweeper, 0, 0, 0, 90, 2) and not Obstacles.hit(sweeper, 0, 0, 0, 110, 2))
	local spinner: any = { kind = "spinner", d = 100, x = 0, R = 10, omega = 1, phase = 0 }
	check("spinner: the arm lies along x at t=0", Obstacles.hit(spinner, 0, 8, 0, 100, 2) and not Obstacles.hit(spinner, 0, 0, 0, 108, 2))
	check("spinner: a jump clears it", not Obstacles.hit(spinner, 0, 8, 3.5, 100, 2))
	check("spinner: it turns", Obstacles.hit(spinner, math.pi / 2, 0, 0, 108, 2) and not Obstacles.hit(spinner, math.pi / 2, 8, 0, 100, 2))
	check("spinner: well outside, nothing", not Obstacles.hit(spinner, 0, 20, 0, 100, 2))
	local laser: any = { kind = "laser", d = 100, period = 2, on = 0.5, omega = 0, phase = 0, h = 2.3 }
	check("laser: on for the first half", Obstacles.laserOn(laser, 0.5) and not Obstacles.laserOn(laser, 1.5))
	check("laser: burns when on", Obstacles.hit(laser, 0.5, 5, 0, 100, 2) and not Obstacles.hit(laser, 1.5, 5, 0, 100, 2))
	check("laser: a jump clears it", not Obstacles.hit(laser, 0.5, 5, 3, 100, 2))
	local falling: any = { kind = "falling", d = 100, x = 0, size = 8, period = 2, omega = 0, phase = 0 }
	check("falling cube: solid in the middle of its cycle", Obstacles.hit(falling, 1.0, 0, 0, 100, 2) and not Obstacles.hit(falling, 0.2, 0, 0, 100, 2) and not Obstacles.hit(falling, 1.8, 0, 0, 100, 2))
	check("falling cube: not beside it", not Obstacles.hit(falling, 1.0, 12, 0, 100, 2))
	local pendulum: any = { kind = "pendulum", d = 100, x = 0, len = 12, amp = 1, omega = 1, phase = 0 }
	local bx, by = Obstacles.pendulumBob(pendulum, 0)
	check("pendulum: hangs straight down at t=0", math.abs(bx) < 1e-9 and math.abs(by - (Obstacles.PENDULUM_PIVOT - 12)) < 1e-9)
	check("pendulum: hits at the bottom of its swing", Obstacles.hit(pendulum, 0, 0, 0, 100, 2))
	check("pendulum: a jump over the ball is high enough", not Obstacles.hit(pendulum, 0, 0, 9, 100, 2))
	check("pendulum: misses far from its arc", not Obstacles.hit(pendulum, 0, 14, 0, 100, 2))
	check("anyHit looks through a list", Obstacles.anyHit({ spinner, laser }, 0.5, 5, 0, 100, 2) and not Obstacles.anyHit({ spinner }, 0, 30, 0, 100, 2))
end

-- Stages
do
	local previousLength, previousNeeds = 0, 0
	for k = 1, CourseConfig.STAGES do
		local s = Stage.generate(k)
		check("stage " .. k .. " is the same each time", Stage.generate(k) == s)
		check("stage " .. k .. ": longer and harder to smash than the one before", s.length > previousLength and s.needs > previousNeeds)
		previousLength, previousNeeds = s.length, s.needs
		check("stage " .. k .. ": the wall is at its end", s.length == Economy.stageLength(k))
		check("stage " .. k .. ": its theme", s.theme == (k - 1) % #CourseConfig.THEMES + 1)
		check("stage " .. k .. ": the orb count", #s.orbs == Economy.orbsIn(k))
		local inside, apart, sorted = true, true, true
		for i, o in s.obstacles do
			if o.d < CourseConfig.START_PAD - 1 or o.d > s.length - CourseConfig.END_PAD + 1 then
				inside = false
			end
			if i > 1 and o.d < s.obstacles[i - 1].d then
				sorted = false
			end
		end
		check("stage " .. k .. ": every obstacle is inside the run-up and the end stretch", inside)
		check("stage " .. k .. ": obstacles in order", sorted)
		local clean = true
		for _, orb in s.orbs do
			if math.abs(orb.x) > CourseConfig.WIDTH / 2 - 2 or orb.d < 0 or orb.d > s.length - 10 then
				clean = false
			end
			for _, o in s.obstacles do
				if math.abs(orb.d - o.d) < 4 then
					clean = false
				end
			end
		end
		check("stage " .. k .. ": orbs are in the lane and clear of obstacles", clean)
		if k == 1 then
			local kinds = {}
			for _, o in s.obstacles do
				kinds[o.kind] = true
			end
			check("stage 1 has only the gentle obstacles", kinds.sweeper and kinds.laser and not kinds.spinner and not kinds.falling and not kinds.pendulum)
		end
	end
	local kinds10 = {}
	for _, o in Stage.generate(10).obstacles do
		kinds10[o.kind] = true
	end
	check("stage 10 uses every kind", kinds10.sweeper and kinds10.laser and kinds10.spinner and kinds10.falling and kinds10.pendulum)
	-- falling cubes always leave a column free
	local freeColumn = true
	for k = 3, CourseConfig.STAGES do
		local byD: { [number]: number } = {}
		for _, o in Stage.generate(k).obstacles do
			if o.kind == "falling" then
				byD[o.d] = (byD[o.d] or 0) + 1
			end
		end
		for _, n in byD do
			if n >= 3 then
				freeColumn = false
			end
		end
	end
	check("a row of falling cubes always leaves a column free", freeColumn)
	-- the obstacles get quicker and closer, in time
	local function gapTime(k: number): number
		local list = Stage.generate(k).obstacles
		return (list[#list].d - list[1].d) / #list / Speed.walk(Economy.needs(k))
	end
	check("obstacles come closer together in time as stages go on", gapTime(10) < gapTime(1) - 0.5, gapTime(1) .. " -> " .. gapTime(10))
end

-- Layout
do
	check("stage 1 starts at z = 0", Layout.startZ(1) == 0)
	check("stages go down the course", Layout.startZ(2) < Layout.startZ(1) and Layout.startZ(3) < Layout.startZ(2))
	check("a stage's end is before the next start", Layout.startZ(1) - Stage.generate(1).length - CourseConfig.WALL_THICK > Layout.startZ(2))
	local w = Layout.toWorld(3, 5, 40)
	local k, d = Layout.fromZ(w.Z)
	check("the world position maps back", k == 3 and math.abs(d - 40) < 1e-6 and w.X == 5)
	check("spawn is in the stage, a little way in", select(1, Layout.fromZ(Layout.spawn(2).Z)) == 2 and select(2, Layout.fromZ(Layout.spawn(2).Z)) == 6)
end

-- Progress
do
	local function newData(): any
		return { coins = 0, speed = 0, stage = 1, upgrades = {}, rebirths = 0, passes = {}, boostUntil = 0, stats = { orbs = 0, smashes = 0, falls = 0, runs = 0 } }
	end
	local d = newData()
	local gain, coins = Progress.pickup(d, 100)
	check("an orb gives speed and coins", gain == 1 and coins >= 1 and d.speed == 1 and d.coins == coins and d.stats.orbs == 1)
	d.upgrades.orb = 4
	check("Orb Power raises an orb's worth", Progress.orbValue(d) == 5)
	d.rebirths = 2
	check("rebirths raise it more", Progress.orbValue(d) == math.floor(5 * (1 + 2 * Economy.REBIRTH_BONUS)))
	d.passes.Orbs2 = true
	check("2x Orbs doubles it", Progress.orbValue(d) == math.floor(5 * 1.5 * 2))
	local c = newData()
	check("can't smash a wall without the speed", not Progress.canSmash(c, 1) and Progress.smash(c, 1, 0) == nil and c.stage == 1)
	c.speed = Stage.generate(1).needs
	check("with the speed, stage 1's wall smashes", Progress.canSmash(c, 1))
	check("a later stage's wall can't be smashed first", not Progress.canSmash(c, 2))
	local paid = Progress.smash(c, 1, 0)
	check("smashing opens the next stage and pays", paid ~= nil and paid >= Economy.wallCoins(1) and c.stage == 2 and c.coins == paid and c.stats.smashes == 1)
	check("a smashed wall can't be smashed again", Progress.smash(c, 1, 0) == nil and c.stage == 2)
	check("finishing a stage run pays a bonus", Progress.finish(c, 1, 0) >= Economy.finishCoins(1) and c.stats.runs == 1)
	-- coin multiplier adds up
	local m = newData()
	check("x1 to start", Progress.coinMultiplier(m, 0) == 1)
	m.upgrades.coin = 4
	m.rebirths = 1
	m.passes.Coins2 = true
	m.passes.Vip = true
	m.boostUntil = 100
	check("upgrades, rebirths, passes and boosts add", Progress.coinMultiplier(m, 50) == 1 + 1 + 0.25 + 1 + 0.25 + 1 and Progress.coinMultiplier(m, 150) == 1 + 1 + 0.25 + 1 + 0.25)
	-- upgrades
	local u = newData()
	u.coins = 1000
	local level = Progress.buy(u, "orb")
	check("buying Orb Power", level == 1 and u.upgrades.orb == 1 and u.coins == 1000 - Economy.upgradeCost(Economy.upgrade("orb"), 0))
	local _, why = Progress.buy(newData(), "orb")
	check("can't afford it", why == "coins")
	check("an unknown upgrade", select(2, Progress.buy(u, "wings")) == "unknown")
	local maxed = newData()
	maxed.coins = 1e12
	maxed.upgrades.orb = Economy.upgrade("orb").max
	check("a maxed upgrade", select(2, Progress.buy(maxed, "orb")) == "max")
	local prices = {}
	for lv = 0, 10 do
		table.insert(prices, Economy.upgradeCost(Economy.upgrade("orb"), lv))
	end
	local rising = true
	for i = 2, #prices do
		if prices[i] <= prices[i - 1] then
			rising = false
		end
	end
	check("each level costs more", rising)
	-- rebirth
	local r = newData()
	check("rebirth needs the whole course", select(1, Progress.canRebirth(r)) == false)
	r.stage = Economy.STAGES + 1
	check("and the coins", select(1, Progress.canRebirth(r)) == false)
	r.coins = Economy.rebirthCost(0)
	check("then it's allowed", select(1, Progress.canRebirth(r)) == true)
	r.speed, r.upgrades.orb = 500, 7
	Progress.rebirth(r)
	check("rebirth starts over for a lasting bonus", r.rebirths == 1 and r.speed == 0 and r.stage == 1 and r.coins == 0 and next(r.upgrades) == nil)
	check("each rebirth costs more", Economy.rebirthCost(1) == Economy.rebirthCost(0) * Economy.REBIRTH_GROWTH)
end

print(("%d passed, %d failed"):format(passed, failed))
process.exit(if failed > 0 then 1 else 0)
