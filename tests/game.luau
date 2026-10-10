-- Unit tests for the new game's logic (game/shared). Run from the repo root:  lune run tests/game.luau

local process = require("@lune/process")
local Loader = require("./loader")

local Shared = Loader.root("game/shared", "Shared")
local R = Loader.require

local Creatures = R(Shared.Config.Creatures)
local Eggs = R(Shared.Config.Eggs)
local IslandConfig = R(Shared.Config.Island)
local Mutations = R(Shared.Config.Mutations)
local WeatherConfig = R(Shared.Config.Weather)
local HeistConfig = R(Shared.Config.Heist)
local Earn = R(Shared.Logic.Earn)
local Hatch = R(Shared.Logic.Hatch)
local Heist = R(Shared.Logic.Heist)
local Stock = R(Shared.Logic.Stock)
local Weather = R(Shared.Logic.Weather)
local Raid = R(Shared.Logic.Raid)
local RaidConfig = R(Shared.Config.Raid)
local FoodConfig = R(Shared.Config.Food)
local Food = R(Shared.Logic.Food)
local WildConfig = R(Shared.Config.Wild)
local Wild = R(Shared.Logic.Wild)
local ShopConfig = R(Shared.Config.Shop)
local MotherConfig = R(Shared.Config.Mother)
local Mother = R(Shared.Logic.Mother)
local SnapConfig = R(Shared.Config.Snap)
local Snap = R(Shared.Logic.Snap)
local DailyConfig = R(Shared.Config.Daily)
local Daily = R(Shared.Logic.Daily)

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL  " .. name .. "\n      " .. tostring(err))
	end
end
local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label or "value", tostring(expected), tostring(actual)), 2)
	end
end

test("every egg's creatures exist, its chances add up to 1, and later eggs cost more", function()
	local previous = 0
	for _, egg in Eggs do
		local total = 0
		for i, id in egg.creatures do
			assert(Creatures.byId[id], egg.name .. ": no creature " .. id)
			total += egg.chances[i]
		end
		assert(math.abs(total - 1) < 0.01, egg.name .. "'s chances add up to " .. total)
		assert(egg.price > previous, egg.name .. " costs more than the egg before")
		previous = egg.price
	end
	eq(#Eggs, 11, "ten tiers and the Legendary Egg")
end)

test("hatching: the chances come out about right, and the weather sets the least mutation", function()
	local state = 1
	local rng = {
		NextNumber = function(_self)
			state = (state * 16807) % 2147483647
			return state / 2147483647
		end,
	}
	local counts = {}
	for _ = 1, 20000 do
		local creature = Hatch.roll(1, function()
			return rng:NextNumber()
		end)
		counts[creature] = (counts[creature] or 0) + 1
	end
	assert(counts.Cubby > 11000 and counts.Cubby < 13000, "Cubby about 60%: " .. counts.Cubby)
	assert((counts.Bear or 0) > 100 and (counts.Bear or 0) < 320, "Bear about 1%: " .. tostring(counts.Bear))
	for _ = 1, 200 do
		local _, mutation = Hatch.roll(3, function()
			return rng:NextNumber()
		end, "Lava")
		assert(Mutations.byId[mutation].order >= Mutations.byId.Lava.order, "at least Lava in a Lava Storm")
	end
end)

test("later eggs incubate longer: a minute for the first, under an hour for the Legendary", function()
	eq(Hatch.seconds(1), IslandConfig.BASE_INCUBATE)
	for tier = 2, 11 do
		assert(Hatch.seconds(tier) > Hatch.seconds(tier - 1), "tier " .. tier)
	end
	assert(Hatch.seconds(11) <= 3600, "Legendary under an hour: " .. Hatch.seconds(11))
end)

test("earnings: mutations multiply, an island adds up, time away is capped", function()
	local cubby = { s = "Cubby", m = "Normal" }
	local golden = { s = "Cubby", m = "Golden" }
	eq(Earn.rate(cubby), Creatures.byId.Cubby.earn)
	eq(Earn.rate(golden), Creatures.byId.Cubby.earn * Mutations.byId.Golden.mult)
	eq(Earn.islandRate({ a = cubby, b = golden, c = cubby }, { "a", "b" }), Earn.rate(cubby) + Earn.rate(golden), "only the placed ones")
	eq(Earn.offline(10, 999999999), 10 * IslandConfig.OFFLINE_HOURS * 3600, "capped")
	eq(Earn.offline(10, -5), 0, "never negative")
	eq(Earn.nextPrice(IslandConfig.PEN_PRICES, IslandConfig.PENS, IslandConfig.PENS), IslandConfig.PEN_PRICES[1])
	eq(Earn.nextPrice(IslandConfig.PEN_PRICES, IslandConfig.PENS + #IslandConfig.PEN_PRICES, IslandConfig.PENS), nil, "no more")
end)

test("a Homesick creature sends a share home, and its owner keeps the rest", function()
	local stolen = { s = "Bear", m = "Normal", h = 42 }
	local rate = Earn.rate(stolen)
	eq(Earn.kept(stolen), rate * (1 - RaidConfig.HOME_SHARE))
	eq(Earn.islandRate({ a = stolen }, { "a" }), Earn.kept(stolen), "the island counts what's kept")
	local shares = Earn.homeShares({ a = stolen, b = { s = "Cubby", m = "Normal" }, c = stolen }, { "a", "b" })
	eq(shares[42], rate * RaidConfig.HOME_SHARE, "only the placed Homesick one")
	eq(Earn.kept(stolen) + shares[42], rate, "nothing made from nothing")
end)

test("guards: more and better creatures guard better, the special ones bring their tricks", function()
	local creatures = { a = { s = "Cubby", m = "Normal" }, b = { s = "Cubby", m = "Lava" }, c = { s = "Cubby", m = "Neon" } }
	local guards = Raid.guards(creatures, { "a", "b" })
	eq(guards.power, 1 + Mutations.byId.Lava.order)
	assert(guards.lava and not guards.crystal and not guards.neon, "only Lava")
	eq(Raid.guards(creatures, {}).power, 0, "an empty garden has no guards")
	eq(Raid.bumpChance(0), 0)
	assert(Raid.bumpChance(2) < Raid.bumpChance(6), "more power, more bumps")
	eq(Raid.bumpChance(1000), RaidConfig.GUARD_MAX_CHANCE, "capped")
end)

test("the Mother Cube: once an hour for two minutes, never during Raid Time, hungrier with more players", function()
	local visits = 0
	for t = 0, 3 * 86400, 10 do
		local on, start = Mother.at(t)
		if on then
			assert(not Raid.at(t), "not during Raid Time at " .. t)
		end
		if on and start == t then
			visits += 1
		end
		assert(Mother.nextVisit(t) > t, "the next visit is later")
		local studioOn = Mother.at(t, true)
		if studioOn then
			assert(not Raid.at(t), "studio visits not during Raid Time either at " .. t)
		end
	end
	eq(visits, 72, "once an hour for three days")
	eq(Mother.goal(1), MotherConfig.GOAL_MIN)
	eq(Mother.goal(6), 6 * MotherConfig.GOAL_PER_PLAYER)
	eq(Mother.snackPrice(0), MotherConfig.SNACK_MIN)
	eq(Mother.snackPrice(100), 100 * MotherConfig.SNACK_SECONDS)
	eq(Mother.legendaryChance(0), 0)
	eq(Mother.legendaryChance(1000), MotherConfig.LEGENDARY_MAX, "capped")
	for id in MotherConfig.FOOD_POINTS do
		assert(FoodConfig.byId[id], "a real food: " .. id)
	end
end)

test("Cube Snap: four matching make a Mega, four Megas a Rainbow, and they earn and guard more", function()
	local c = {
		a = { s = "Cubby", m = "Golden" },
		b = { s = "Cubby", m = "Golden" },
		c = { s = "Cubby", m = "Golden" },
		d = { s = "Cubby", m = "Normal" }, -- another mutation: no
		e = { s = "Cubby", m = "Golden", h = 7 }, -- Homesick: no
		f = { s = "Kitty", m = "Golden" }, -- another creature: no
	}
	eq(Snap.find(c, {}, "a"), nil, "only three match")
	c.g = { s = "Cubby", m = "Golden" }
	c.h2 = { s = "Cubby", m = "Golden" }
	local group, made = Snap.find(c, { "b" }, "a")
	assert(group and made, "four match")
	eq(#group, SnapConfig.NEED)
	eq(group[1], "a", "the chosen one first")
	assert(not table.find(group, "b"), "the ones in the garden last")
	eq(made.g, "Mega")
	eq(made.m, "Golden")
	eq(Snap.find(c, {}, "e"), nil, "a Homesick one can't snap")
	-- Megas of any mutation make a Rainbow with the best one
	local megas = {
		a = { s = "Bear", m = "Normal", g = "Mega" },
		b = { s = "Bear", m = "Lava", g = "Mega" },
		c = { s = "Bear", m = "Golden", g = "Mega" },
		d = { s = "Bear", m = "Normal", g = "Mega" },
	}
	local _, rainbow = Snap.find(megas, {}, "a")
	assert(rainbow, "four Megas")
	eq(rainbow.g, "Rainbow")
	eq(rainbow.m, "Lava", "the best mutation")
	eq(Snap.find({ a = { s = "Bear", m = "Normal", g = "Rainbow" } }, {}, "a"), nil, "Rainbow is the top")
	-- Earnings and guarding
	local plain = { s = "Cubby", m = "Golden" }
	local mega = { s = "Cubby", m = "Golden", g = "Mega" }
	eq(Earn.rate(mega), Earn.rate(plain) * SnapConfig.byId.Mega.mult)
	assert(Earn.rate(mega) > 4 * Earn.rate(plain), "a Mega beats the four it took")
	eq(Raid.guards({ a = mega }, { "a" }).power, Mutations.byId.Golden.order * SnapConfig.byId.Mega.guard)
	eq(Snap.name(mega), "Mega Golden Cubby")
	eq(Snap.name({ s = "Cubby", m = "Normal" }), "Cubby")
end)

test("daily tasks: three different ones a day, they change, a new day starts fresh", function()
	local seen = {}
	for day = 0, 60 do
		local tasks = Daily.tasks(day)
		eq(#tasks, DailyConfig.PER_DAY)
		for i, id in tasks do
			assert(DailyConfig.byId[id], "a real task")
			for j = i + 1, #tasks do
				assert(tasks[j] ~= id, "different tasks")
			end
			seen[id] = true
		end
		local again = Daily.tasks(day)
		eq(table.concat(again, ","), table.concat(tasks, ","), "the same everywhere")
	end
	for _, task in DailyConfig.LIST do
		assert(seen[task.id], task.id .. " comes up")
	end
	local state = { day = 5, progress = {}, claimed = false }
	eq(Daily.done(state), false)
	for _, id in Daily.tasks(5) do
		state.progress[id] = DailyConfig.byId[id].goal
	end
	eq(Daily.done(state), true)
	state.claimed = true
	Daily.today(state, 6)
	eq(state.claimed, false, "a new day")
	eq(next(state.progress), nil, "fresh progress")
	eq(Daily.day(86400 * 3 + 5), 3)
end)

test("an egg pays itself back: a tier's average creature earns its price in under 10 minutes", function()
	for _, egg in Eggs do
		local average = 0
		for i, id in egg.creatures do
			average += Creatures.byId[id].earn * egg.chances[i]
		end
		assert(egg.price / average < 600, ("%s pays back in %d s"):format(egg.name, egg.price / average))
	end
end)

test("the weather: steady through a window, every kind comes, clear sky most", function()
	local seen = {}
	for window = 0, 3000 do
		local t = window * WeatherConfig.SECONDS
		local a, ends = Weather.at(t)
		eq(Weather.at(t + WeatherConfig.SECONDS - 1).id, a.id, "steady")
		eq(ends, t + WeatherConfig.SECONDS)
		seen[a.id] = (seen[a.id] or 0) + 1
	end
	for _, weather in WeatherConfig.LIST do
		assert((seen[weather.id] or 0) > 0, weather.id .. " comes")
	end
	assert(seen.Clear > seen.Neon * 4, "clear much more often than neon")
end)

test("the shop: the first egg is always in, rare eggs seldom, and the count stays in bounds", function()
	local legendary = 0
	for window = 0, 2000 do
		assert(Stock.count(window, 1) >= 1, "Meadow Egg always in stock")
		for tier = 1, 11 do
			local count = Stock.count(window, tier)
			assert(count >= 0 and count <= 6, "count in bounds")
		end
		if Stock.count(window, 11) > 0 then
			legendary += 1
		end
	end
	assert(legendary > 20 and legendary < 250, "Legendary in stock about 5%: " .. legendary)
	eq(Stock.restockAt(301), 600)
end)

test("Heist: rounds only on weekends, on the clock", function()
	local saturday = 2 * 86400 -- 3 Jan 1970
	eq(Heist.weekday(saturday), 6)
	assert(Heist.round(saturday + 30), "a round at :00 on Saturday")
	assert(not Heist.round(saturday + HeistConfig.ROUND + 1), "over after ROUND seconds")
	assert(not Heist.round(saturday - 86400 + 30), "none on Friday")
	eq(Heist.nextRound(saturday - 3600), saturday)
end)

test("Raid Time: the gates open on the clock for OPEN seconds every EVERY", function()
	local t = 1000 * RaidConfig.EVERY
	local isOpen, changes = Raid.at(t)
	assert(isOpen and changes == t + RaidConfig.OPEN, "open at the start of a window")
	isOpen, changes = Raid.at(t + RaidConfig.OPEN)
	assert(not isOpen and changes == t + RaidConfig.EVERY, "shut after OPEN seconds until the next window")
	assert(RaidConfig.OPEN < RaidConfig.EVERY / 4, "open only a small part of the time")
end)

test("food always pays, adds up to a cap, and counts while away", function()
	for _, food in FoodConfig.LIST do
		for _, rate in { 0, 5, 1000, 1e6 } do
			local price = Food.price(food, rate)
			assert(price >= food.min, "at least its minimum")
			assert(rate == 0 or price < rate * (FoodConfig.BOOST - 1) * food.minutes * 60 or price == food.min, "cheaper than what it brings")
		end
	end
	local hay = FoodConfig.byId.Hay
	eq(Food.feed(0, 1000, hay), 1000 + hay.minutes * 60, "from now")
	eq(Food.feed(1100, 1000, hay), 1100 + hay.minutes * 60, "adds up")
	eq(Food.feed(1000 + FoodConfig.MAX_FED, 1000, hay), 1000 + FoodConfig.MAX_FED, "capped")
	assert(Food.fed(1001, 1000) and not Food.fed(1000, 1000), "fed until")
	eq(Food.offlineBonus(10, 1000, 1600, 5000), 10 * (FoodConfig.BOOST - 1) * 600, "only while fed")
	eq(Food.offlineBonus(10, 1000, 900, 5000), 0, "not fed")
	eq(Food.offlineBonus(10, 1000, 1e9, 1000 + 100), 10 * (FoodConfig.BOOST - 1) * 100, "only while away")
	eq(#IslandConfig.STORAGE_PRICES, #IslandConfig.STORAGE - 1, "a price per bigger barn")
end)

test("the Wild: biomes get harder, the treadmill trains speed, eggs 4-8 only come from the Wild", function()
	local previous = 0
	for i, biome in WildConfig.BIOMES do
		assert(biome.guardian > previous, "each biome's guardians are faster")
		previous = biome.guardian
		eq(biome.tier, i, "a biome per egg tier")
		assert(Hatch.egg(biome.tier), "its eggs exist")
		assert(Wild.outruns(Wild.needs(biome), biome) and not Wild.outruns(Wild.needs(biome) - 1, biome), "the speed it needs")
	end
	assert(Wild.outruns(WildConfig.START_SPEED, WildConfig.BIOMES[1]), "a new player outruns the first biome")
	assert(Wild.needs(WildConfig.BIOMES[#WildConfig.BIOMES]) <= WildConfig.MAX_SPEED, "the last biome can be escaped")
	assert(not Wild.outruns(WildConfig.START_SPEED, WildConfig.BIOMES[2]), "the second biome needs training")
	assert(Wild.train(16, 2, 10) > Wild.train(16, 1, 10), "a better treadmill trains faster")
	assert(Wild.trainRate(1, 40) < Wild.trainRate(1, 16), "harder when already fast")
	eq(Wild.train(WildConfig.MAX_SPEED, 5, 100), WildConfig.MAX_SPEED, "capped")
	eq(#WildConfig.TREADMILL_PRICES, #WildConfig.TREADMILL_GAINS - 1, "a price per level")
	for tier = 4, 8 do
		assert(ShopConfig.STOCK[tier] == nil, "not in the Egg Shop")
	end
end)

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	process.exit(1)
end
