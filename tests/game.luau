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

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	process.exit(1)
end
