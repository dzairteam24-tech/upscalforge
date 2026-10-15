-- Brick Farm's rules: levels, land, growth, planting and harvesting, seeds, the barn, the village's layout and the
-- crops' brick models. Run from the repo root:  lune run tests/brickfarm.luau

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./loader")
local Vector3 = roblox.Vector3

local Shared = Loader.root("brickfarm/shared", "Shared")
local Crops = Loader.require(Shared.Config.Crops)
local FarmConfig = Loader.require(Shared.Config.Farm)
local Level = Loader.require(Shared.Logic.Level)
local Land = Loader.require(Shared.Logic.Land)
local Growth = Loader.require(Shared.Logic.Growth)
local Farm = Loader.require(Shared.Logic.Farm)
local Layout = Loader.require(Shared.Logic.Layout)
local CropModel = Loader.require(Shared.Logic.CropModel)
local Format = Loader.require(Shared.Logic.Format)

local passed, failed = 0, 0
local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (if detail then " (" .. detail .. ")" else ""))
	end
end

-- crops
do
	local previousLevel, previousRate = 0, 0
	local sorted, rising, keys = true, true, {}
	for _, crop in Crops.LIST do
		keys[crop.key] = true
		if crop.level < previousLevel then
			sorted = false
		end
		previousLevel = crop.level
		local rate = (crop.sell * crop.yield - crop.seed) / (crop.grow / 60)
		if rate <= previousRate then
			rising = false
		end
		previousRate = rate
		check(crop.name .. " makes a profit", crop.sell * crop.yield > crop.seed)
		check(crop.name .. " is in byKey", Crops.byKey[crop.key] == crop)
	end
	check("crops unlock in order of level", sorted)
	check("each crop pays more a minute than the one before", rising)
	local first, last = Crops.LIST[1], Crops.LIST[#Crops.LIST]
	check("quick crops give the most XP a minute", first.xp / first.grow > last.xp / last.grow * 5)
	check("the first crop is ready in under a minute", first.grow <= 60 and first.level == 1)
end

-- levels
do
	check("level 1 at 0 XP", Level.of(0) == 1)
	check("level 2 at exactly its XP", Level.of(Level.toNext(1)) == 2 and Level.of(Level.toNext(1) - 1) == 1)
	local level, share = Level.of(Level.total(5) + Level.toNext(5) / 2)
	check("halfway through level 5", level == 5 and math.abs(share - 0.5) < 0.01, level .. " " .. share)
	check("total and of agree", Level.of(Level.total(17)) == 17)
	check("never past the top", Level.of(1e15) == Level.MAX)
	check("each level needs more", Level.toNext(10) > Level.toNext(9))
end

-- land
do
	check("starts with the configured land", Land.START == FarmConfig.START_TILES and Land.MAX == 36)
	check("more land costs more", Land.cost(20) > Land.cost(10) and Land.cost(Land.START + 1) > 0)
	check("and needs a higher level", Land.level(Land.MAX) > Land.level(Land.START + 1) and Land.level(Land.START + 1) == 1)
	check("can't buy without coins", not Land.canExpand(6, 0, 1))
	check("can buy with them", Land.canExpand(6, 1e6, 1))
	check("not past the top", not Land.canExpand(Land.MAX, 1e9, 99))
	check("not before its level", not Land.canExpand(20, 1e9, 1))
end

-- growth
do
	check("just planted: a sprout", Growth.stage(100, 60, 100) == 1 and Growth.progress(100, 60, 100) == 0)
	check("halfway: young", Growth.stage(100, 60, 130) == 2)
	check("most of the way: stage 3", Growth.stage(100, 60, 145) == 3)
	check("ready on time", Growth.ready(100, 60, 160) and Growth.stage(100, 60, 160) == 4 and not Growth.ready(100, 60, 159))
	check("keeps being ready (grows while away)", Growth.ready(100, 60, 1e9) and Growth.progress(100, 60, 1e9) == 1)
	check("seconds left", Growth.left(100, 60, 130) == 30 and Growth.left(100, 60, 500) == 0)
end

-- the farm's rules
local function newData(): any
	return { coins = 0, xp = 0, tiles = 6, plots = {}, seeds = {}, barn = {}, stats = { planted = 0, harvested = 0, sold = 0, earned = 0 } }
end
do
	local d = newData()
	check("no seeds, no planting", select(2, Farm.plant(d, 1, "carrot", 0)) == "seeds")
	d.coins = 100
	check("buy carrot seeds", Farm.buySeeds(d, "carrot", 5) and d.seeds.carrot == 5 and d.coins == 100 - 5 * Crops.byKey.carrot.seed)
	check("not a locked crop", select(2, Farm.buySeeds(d, "goldcorn", 1)) == "level")
	check("not a silly amount", not Farm.buySeeds(d, "carrot", 0) and not Farm.buySeeds(d, "carrot", 1.5) and not Farm.buySeeds(d, "carrot", 1000) and not Farm.buySeeds(d, "carrot", "x"))
	check("not more than they can pay", select(2, Farm.buySeeds(d, "carrot", 99)) == "coins")
	check("plant", Farm.plant(d, 1, "carrot", 1000) and d.seeds.carrot == 4 and d.plots["1"].c == "carrot" and d.stats.planted == 1)
	check("not on a planted tile", select(2, Farm.plant(d, 1, "carrot", 1000)) == "taken")
	check("not on land they don't have", select(2, Farm.plant(d, 7, "carrot", 1000)) == "tile" and not Farm.plant(d, 0, "carrot", 0) and not Farm.plant(d, 2.5, "carrot", 0))
	check("not a crop that isn't", select(2, Farm.plant(d, 2, "banana", 1000)) == "crop")
	check("not ready, no harvest", Farm.harvest(d, 1, 1010) == nil and d.plots["1"] ~= nil)
	check("nothing to harvest on an empty tile", Farm.harvest(d, 2, 5000) == nil)
	local crop, amount, xp = Farm.harvest(d, 1, 1000 + Crops.byKey.carrot.grow)
	check("ready: harvested into the barn", crop ~= nil and crop.key == "carrot" and amount == crop.yield and d.barn.carrot == crop.yield and d.plots["1"] == nil)
	check("with XP", xp == Crops.byKey.carrot.xp and d.xp == xp)
	local coins = d.coins
	local got = Farm.sell(d, "all")
	check("sell everything", got == Crops.byKey.carrot.sell * Crops.byKey.carrot.yield and d.coins == coins + got and next(d.barn) == nil and d.stats.earned == got)
	check("selling an empty barn gives nothing", Farm.sell(d, "all") == 0)
	d.barn = { carrot = 3, radish = 2 }
	check("sell one kind", Farm.sell(d, "radish") == Crops.byKey.radish.sell * 2 and d.barn.carrot == 3 and d.barn.radish == nil)
	-- the last seed
	d.seeds = { carrot = 1 }
	Farm.plant(d, 3, "carrot", 0)
	check("the last seed used leaves none", d.seeds.carrot == nil)
	-- a level up
	local e = newData()
	e.xp = Level.toNext(1) - 1
	e.plots["1"] = { c = "carrot", t = 0 }
	local _, _, _, up = Farm.harvest(e, 1, 1e6)
	check("a harvest can level them up", up and Farm.level(e) == 2)
	check("and unlock the next crop", Farm.unlocked(e, "radish") and not Farm.unlocked(e, "tomato"))
	-- land
	local f = newData()
	f.coins = Land.cost(7)
	check("buy land", Farm.expand(f) and f.tiles == 7 and f.coins == 0)
	check("now they can plant there", select(2, Farm.plant(f, 7, "carrot", 0)) == "seeds")
	check("can't buy land without coins", not Farm.expand(f))
	f.plots = { ["1"] = { c = "carrot", t = 0 }, ["2"] = { c = "carrot", t = 100 }, ["3"] = { c = "corn", t = 0 } }
	check("counts the ready tiles", Farm.readyCount(f, 120) == 1)
end

-- the village
do
	local apart = true
	for a = 1, FarmConfig.FARMS do
		for b = a + 1, FarmConfig.FARMS do
			if (Layout.farm(a).Position - Layout.farm(b).Position).Magnitude < FarmConfig.COLUMNS * Layout.STEP + 20 then
				apart = false
			end
		end
	end
	check("farms don't overlap", apart)
	local f = Layout.farm(3)
	check("each farm faces the square", (f.Position + f.LookVector * FarmConfig.RING).Magnitude < 0.01)
	local back = true
	for farm = 1, FarmConfig.FARMS do
		for tile = 1, Land.MAX do
			local a, b = Layout.tileAt(Layout.tile(farm, tile).Position + Vector3.new(0.5, 0, -0.3))
			if a ~= farm or b ~= tile then
				back = false
			end
		end
	end
	check("a point on a tile maps back to it", back)
	check("nothing between the farms", Layout.tileAt(Vector3.new(0, 0, 0)) == nil)
	local front = (Layout.tile(1, 1).Position - Vector3.zero).Magnitude < (Layout.tile(1, 31).Position - Vector3.zero).Magnitude
	check("the first tiles are at the front (near the square)", front)
	check("the spawn is in front of the farm, outside the tiles", Layout.tileAt(Layout.spawn(2).Position) == nil and (Layout.spawn(2).Position - Vector3.zero).Magnitude < FarmConfig.RING)
	check("the barn is beside the tiles", Layout.tileAt(Layout.barn(4).Position) == nil and (Layout.barn(4).Position - Layout.farm(4).Position).Magnitude < 50)
end

-- brick models
do
	local all = true
	for _, crop in Crops.LIST do
		local previous = 0
		for stage = 1, 4 do
			local bricks = CropModel.bricks(crop.key, stage)
			if #bricks == 0 then
				all = false
			end
			local top, wide, fruit = 0, 0, false
			for _, b in bricks do
				top = math.max(top, b.at.Y + b.size.Y / 2)
				wide = math.max(wide, math.abs(b.at.X) + b.size.X / 2, math.abs(b.at.Z) + b.size.Z / 2)
				if b.at.Y - b.size.Y / 2 < -0.01 then
					all = false
				end
				fruit = fruit or (b.fruit and b.color == crop.fruit)
			end
			check(crop.name .. " stage " .. stage .. " fits its tile", wide <= FarmConfig.TILE / 2 + 1 and top <= 10, wide .. " " .. top)
			if stage == 4 then
				check(crop.name .. " shows its fruit when ready", fruit)
			end
			local size = math.max(top, wide)
			if stage >= 2 then
				check(crop.name .. " grows (stage " .. stage .. " is bigger)", size >= previous - 0.01, size .. " vs " .. previous)
			end
			previous = size
		end
	end
	check("every brick is above the soil and every stage has bricks", all)
	check("an unknown crop has no bricks", #CropModel.bricks("nothing", 2) == 0)
end

check("numbers read well", Format.short(950) == "950" and Format.short(12400) == "12.4K" and Format.short(3400000) == "3.4M" and Format.comma(12450) == "12,450")

print(("%d passed, %d failed"):format(passed, failed))
process.exit(if failed > 0 then 1 else 0)
