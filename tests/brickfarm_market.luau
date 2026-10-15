-- Brick Farm's neighbours: the town's orders, farm stands, and trades between two farmers.
-- Run from the repo root:  lune run tests/brickfarm_market.luau

local process = require("@lune/process")
local Loader = require("./loader")

local Shared = Loader.root("brickfarm/shared", "Shared")
local Crops = Loader.require(Shared.Config.Crops)
local Level = Loader.require(Shared.Logic.Level)
local Orders = Loader.require(Shared.Logic.Orders)
local Stand = Loader.require(Shared.Logic.Stand)
local Trade = Loader.require(Shared.Logic.Trade)
local Rng = { seed = 12345 }

local passed, failed = 0, 0
local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (if detail then " (" .. detail .. ")" else ""))
	end
end
local function rand(a: number, b: number): number
	Rng.seed = (Rng.seed * 16807) % 2147483647
	return a + Rng.seed % (b - a + 1)
end
local function newData(level: number?): any
	return { coins = 0, xp = Level.total(level or 1), barn = {}, stand = {}, orders = {}, swapAt = 0, stats = {} }
end

-- orders
do
	local d = newData(4)
	Orders.fill(d, rand)
	check("three orders", #d.orders == 3)
	local sane, ahead, locked = true, true, 0
	for _ = 1, 400 do
		local o = Orders.make(4, rand)
		local crop = Crops.byKey[o.c]
		if crop.level > 4 + Orders.AHEAD then
			ahead = false
		end
		if crop.level > 4 then
			locked += 1
			if o.coins < o.n * crop.sell * 2 then
				sane = false
			end
		elseif o.coins < o.n * crop.sell * 1.4 then
			sane = false
		end
		if o.n % crop.yield ~= 0 or o.xp < 1 then
			sane = false
		end
	end
	check("orders pay more than the barn would", sane)
	check("never far above their level", ahead)
	check("some ask for crops they can't grow yet (a reason to buy from neighbours)", locked > 40 and locked < 250, tostring(locked))
	local o = d.orders[1]
	check("can't deliver without the crops", Orders.deliver(d, 1, rand) == nil and #d.orders == 3)
	d.barn[o.c] = o.n + 2
	local coins, xp = Orders.deliver(d, 1, rand)
	check("deliver: paid, crops taken, XP", coins == o.coins and xp == o.xp and d.coins == o.coins and d.barn[o.c] == 2 and d.xp == Level.total(4) + o.xp)
	check("a new order takes its place", #d.orders == 3 and d.stats.orders == 1)
	check("nonsense order", Orders.deliver(d, 9, rand) == nil and Orders.deliver(d, "x", rand) == nil)
	check("swap one for free", Orders.swap(d, 2, 1000, rand) and #d.orders == 3 and d.swapAt == 1000 + Orders.SWAP_EVERY)
	check("not again straight away", select(2, Orders.swap(d, 2, 1001, rand)) == "wait")
end

-- the stand
do
	local farmer, visitor = newData(), newData()
	farmer.barn.corn = 10
	local low, high = Stand.priceRange("corn")
	check("a price range around the barn's price", low < Crops.byKey.corn.sell and high > Crops.byKey.corn.sell)
	check("not outside it", select(2, Stand.put(farmer, "corn", 3, high + 1)) == "price" and select(2, Stand.put(farmer, "corn", 3, low - 1)) == "price")
	check("not more than in the barn", select(2, Stand.put(farmer, "corn", 11, 50)) == "barn")
	check("nonsense", not Stand.put(farmer, "banana", 1, 5) and not Stand.put(farmer, "corn", 1.5, 50) and not Stand.put(farmer, "corn", 0, 50))
	check("put 6 corn out at 60", Stand.put(farmer, "corn", 6, 60) and farmer.stand.corn.n == 6 and farmer.barn.corn == 4)
	check("more of it, at a new price", Stand.put(farmer, "corn", 2, 70) and farmer.stand.corn.n == 8 and farmer.stand.corn.p == 70 and farmer.barn.corn == 2)
	check("a visitor without coins can't buy", select(2, Stand.buy(farmer, visitor, "corn", 1)) == "coins")
	visitor.coins = 500
	local cost = Stand.buy(farmer, visitor, "corn", 3)
	check("a visitor buys: coins to the farmer, corn to their barn", cost == 210 and visitor.coins == 290 and farmer.coins == 210 and visitor.barn.corn == 3 and farmer.stand.corn.n == 5)
	check("not more than there is", select(2, Stand.buy(farmer, visitor, "corn", 6)) == "stock")
	check("not from their own stand", select(2, Stand.buy(farmer, farmer, "corn", 1)) == "self")
	check("take it back to the barn", Stand.take(farmer, "corn") and farmer.stand.corn == nil and farmer.barn.corn == 7)
	check("the stand counts what it sold", farmer.stats.standSold == 3 and farmer.stats.standEarned == 210)
	local full = newData()
	for i = 1, Stand.KINDS + 1 do
		full.barn[Crops.LIST[i].key] = 1
	end
	for i = 1, Stand.KINDS do
		Stand.put(full, Crops.LIST[i].key, 1, Stand.priceRange(Crops.LIST[i].key))
	end
	check("a stand holds a few kinds at most", select(2, Stand.put(full, Crops.LIST[Stand.KINDS + 1].key, 1, Stand.priceRange(Crops.LIST[Stand.KINDS + 1].key))) == "full")
end

-- trades
do
	local a, b = newData(), newData()
	a.barn.pumpkin = 3
	a.coins = 100
	b.barn.corn = 9
	b.coins = 50
	local s = Trade.new("A", "B")
	check("an offer of what they have", Trade.offer(s, "A", { pumpkin = 2 }, 20, a))
	check("not what they don't have", select(2, Trade.offer(s, "B", { corn = 10 }, 0, b)) == "short" and select(2, Trade.offer(s, "B", {}, 60, b)) == "short")
	check("nonsense", not Trade.offer(s, "B", { banana = 1 }, 0, b) and not Trade.offer(s, "B", { corn = 1.5 }, 0, b) and not Trade.offer(s, "C", {}, 0, b) and not Trade.offer(s, "B", {}, -5, b))
	check("B offers corn", Trade.offer(s, "B", { corn = 6 }, 0, b))
	Trade.setReady(s, "A", true)
	check("one ready isn't a trade", not Trade.complete(s, a, b))
	Trade.setReady(s, "B", true)
	check("a change takes the readies away", Trade.offer(s, "B", { corn = 5 }, 0, b) and not Trade.bothReady(s))
	Trade.setReady(s, "A", true)
	Trade.setReady(s, "B", true)
	b.barn.corn = 2 -- (sold some meanwhile)
	check("can't complete if one can't give it any more", select(2, Trade.complete(s, a, b)) == "short" and not Trade.bothReady(s))
	b.barn.corn = 9
	Trade.setReady(s, "A", true)
	Trade.setReady(s, "B", true)
	check("both ready: everything changes hands", Trade.complete(s, a, b))
	check("A got the corn and gave pumpkins and coins", a.barn.corn == 5 and a.barn.pumpkin == 1 and a.coins == 80)
	check("B got the pumpkins and coins", b.barn.pumpkin == 2 and b.barn.corn == 4 and b.coins == 70 and a.stats.trades == 1 and b.stats.trades == 1)
end

print(("%d passed, %d failed"):format(passed, failed))
process.exit(if failed > 0 then 1 else 0)
