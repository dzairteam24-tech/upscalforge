-- Gem Dig's pure logic: the gems, the mine's generator, the layout, the backpack. Run from the repo root:
--   lune run tests/gemdig.luau

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./loader")
local Vector3 = roblox.Vector3

local Shared = Loader.root("gemdig/shared", "Shared")

local Gem = Loader.require(Shared.Logic.Gem)
local Gems = Loader.require(Shared.Config.Gems)
local MineGen = Loader.require(Shared.Logic.MineGen)
local MineConfig = Loader.require(Shared.Config.Mine)
local Layout = Loader.require(Shared.Logic.Layout)
local Backpack = Loader.require(Shared.Logic.Backpack)
local Snapshot = Loader.require(Shared.Logic.Snapshot)
local Gear = Loader.require(Shared.Config.Gear)
local Game = Loader.require(Shared.Config.Game)
local Multiplier = Loader.require(Shared.Logic.Multiplier)
local Rebirth = Loader.require(Shared.Logic.Rebirth)
local RebirthConfig = Loader.require(Shared.Config.Rebirth)
local Daily = Loader.require(Shared.Logic.Daily)
local DailyConfig = Loader.require(Shared.Config.Daily)
local Offline = Loader.require(Shared.Logic.Offline)
local OfflineConfig = Loader.require(Shared.Config.Offline)
local Depth = Loader.require(Shared.Logic.Depth)
local Economy = Loader.require(Shared.Logic.Economy)
local Passes = Loader.require(Shared.Config.Passes)

local passed, failed = 0, 0
local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (if detail then " (" .. detail .. ")" else ""))
	end
end

-- a seeded stand-in for Random
local function rng(seed: number)
	local state = seed
	return {
		NextNumber = function(_self: any): number
			state = (state * 1103515245 + 12345) % 2147483648
			return state / 2147483648
		end,
	}
end

-- Config: sane
do
	local total = 0
	for _, size in Gem.SIZES do
		total += size.chance
	end
	check("size chances add up to 1", math.abs(total - 1) < 1e-9, tostring(total))
	for i = 2, #Gems.LIST do
		check("gems get more valuable down the list: " .. Gems.LIST[i].id, Gems.LIST[i].value > Gems.LIST[i - 1].value)
	end
	for i = 2, #Gear.SHOVELS do
		check("shovels get better", Gear.SHOVELS[i].power > Gear.SHOVELS[i - 1].power and Gear.SHOVELS[i].price > Gear.SHOVELS[i - 1].price)
	end
	for i = 2, #Gear.PACKS do
		check("packs get bigger", Gear.PACKS[i].slots > Gear.PACKS[i - 1].slots and Gear.PACKS[i].price > Gear.PACKS[i - 1].price)
	end
	check("the first shovel and pack are free", Gear.SHOVELS[1].price == 0 and Gear.PACKS[1].price == 0)
end

-- Gem: picking by depth, rolling, value
do
	local random = rng(7)
	for layer = 1, MineConfig.MAX_LAYER do
		local kind = Gem.pick(layer, random)
		check("a gem for layer " .. layer, kind ~= nil)
		local gem = Gems.byId[kind or ""]
		check("it belongs at layer " .. layer, gem ~= nil and layer >= gem.from and layer <= gem.to)
	end
	check("no gem Void at the surface", (function()
		for _ = 1, 500 do
			if Gem.pick(2, random) == "Void" then
				return false
			end
		end
		return true
	end)())
	-- the rolled sizes and mutations come out roughly as often as they should
	local sizes, golden, count = { Small = 0, Normal = 0, Big = 0, Huge = 0 }, 0, 20000
	for _ = 1, count do
		local item = Gem.roll("Quartz", random)
		sizes[item.s] += 1
		if item.m == "Golden" then
			golden += 1
		end
	end
	check("about two thirds are Normal", math.abs(sizes.Normal / count - 0.66) < 0.02, tostring(sizes.Normal / count))
	check("Huge ones are rare", sizes.Huge / count < 0.04 and sizes.Huge > 0)
	check("some are Golden, not many", golden > 0 and golden / count < 0.06, tostring(golden / count))
	local plain: Gem.Item = { g = "Ruby", s = "Normal" }
	check("Ruby value", Gem.value(plain) == 40)
	check("Big Golden Ruby", Gem.value({ g = "Ruby", s = "Big", m = "Golden" }) == 40 * 2.5 * 3)
	check("Small is less", Gem.value({ g = "Ruby", s = "Small" }) < Gem.value(plain))
	check("name", Gem.name({ g = "Ruby", s = "Big", m = "Golden" }) == "Golden Big Ruby" and Gem.name(plain) == "Ruby")
	check("slots", Gem.slots({ g = "Ruby", s = "Huge" }) == 4 and Gem.slots(plain) == 1)
	local parsed = Gem.parseKey(Gem.key({ g = "Ruby", s = "Big", m = "Neon" }))
	check("key round trip", parsed.g == "Ruby" and parsed.s == "Big" and parsed.m == "Neon")
	check("key round trip, no mutation", Gem.parseKey(Gem.key(plain)).m == nil)
end

-- MineGen: steady, and the right amount of gems
do
	local first = {}
	for x = 1, MineConfig.WIDTH do
		for l = 1, 12 do
			for z = 1, MineConfig.WIDTH do
				first[#first + 1] = MineGen.gemAt(123, x, l, z) or "-"
			end
		end
	end
	local again = {}
	for x = 1, MineConfig.WIDTH do
		for l = 1, 12 do
			for z = 1, MineConfig.WIDTH do
				again[#again + 1] = MineGen.gemAt(123, x, l, z) or "-"
			end
		end
	end
	check("the same seed gives the same mine", table.concat(first) == table.concat(again))
	local other = {}
	for x = 1, MineConfig.WIDTH do
		for l = 1, 12 do
			for z = 1, MineConfig.WIDTH do
				other[#other + 1] = MineGen.gemAt(456, x, l, z) or "-"
			end
		end
	end
	check("another seed gives another", table.concat(first) ~= table.concat(other))
	local gems, cells = 0, 0
	for x = 1, MineConfig.WIDTH do
		for l = 1, MineConfig.MAX_LAYER do
			for z = 1, MineConfig.WIDTH do
				cells += 1
				local kind = MineGen.gemAt(99, x, l, z)
				if kind then
					gems += 1
					local gem = Gems.byId[kind]
					check("a mine gem belongs at its layer", gem ~= nil and l >= gem.from and l <= gem.to, kind .. " at " .. l)
				end
			end
		end
	end
	check("gems in about the share set", math.abs(gems / cells - MineConfig.GEM_CHANCE) < 0.03, tostring(gems / cells))
	check("zones", MineGen.zone(1).name == "Dirt" and MineGen.zone(9).name == "Stone" and MineGen.zone(17).name == "Deep" and MineGen.zone(30).name == "Abyss" and MineGen.zone(40).name == "Core")
	check("each zone needs the next shovel", MineGen.needs(1) == 1 and MineGen.needs(9) == 2 and MineGen.needs(17) == 3 and MineGen.needs(25) == 4 and MineGen.needs(33) == 5)
	check("a shovel's reach is its zones", MineGen.reach(1) == 8 and MineGen.reach(2) == 16 and MineGen.reach(3) == 24 and MineGen.reach(4) == 32 and MineGen.reach(5) == 40)
	check("the tutorial cube is always a gem", MineGen.gemAt(1, 3, 2, 3) == "Quartz" and MineGen.gemAt(999, 3, 2, 3) == "Quartz" and not MineGen.geodeAt(5, 3, 2, 3))
	local geodes, gemCells = 0, 0
	for sd = 1, 6 do
		for x = 1, MineConfig.WIDTH do
			for l = 1, MineConfig.MAX_LAYER do
				for z = 1, MineConfig.WIDTH do
					if MineGen.geodeAt(sd, x, l, z) then
						geodes += 1
						check("a geode is never also a gem cube", MineGen.gemAt(sd, x, l, z) == nil or (x == 3 and l == 2 and z == 3))
					end
					gemCells += 1
				end
			end
		end
	end
	check("geodes in about the share set", math.abs(geodes / gemCells - MineConfig.GEODE_CHANCE) < 0.01, tostring(geodes / gemCells))
	check("deeper is harder", MineGen.hp(1) < MineGen.hp(9) and MineGen.hp(9) < MineGen.hp(25) and MineGen.hp(25) < MineGen.hp(40))
	local shade = MineGen.shade(5, 1, 1, 1)
	check("shade in 0..1", shade >= 0 and shade < 1)
end

-- Layout
do
	local seen = {}
	for i = 1, Game.MAX_PLAYERS do
		local center = Layout.plotCenter(i)
		check("plot on the ground", center.Y == 0)
		for j = 1, i - 1 do
			check("plots apart", (center - Layout.plotCenter(j)).Magnitude > Layout.PLOT + 4)
		end
		check("plot far from the town", center.Magnitude > Layout.HUB / 2 + Layout.PLOT / 2)
		local spawn = Layout.plotSpawn(i)
		check("spawn beside the mine, not over it", spawn.Y > 0 and select(1, Layout.cellAt(i, Vector3.new(spawn.X, -2, spawn.Z))) == nil)
		-- every cube's middle is in that cube
		for _, c in { { 1, 1, 1 }, { 3, 5, 2 }, { 5, 40, 5 }, { 2, 9, 4 } } do
			local x, l, z = Layout.cellAt(i, Layout.cellCenter(i, c[1], c[2], c[3]))
			check("cellAt inverts cellCenter", x == c[1] and l == c[2] and z == c[3])
		end
	end
	check("above ground is no cube", select(2, Layout.cellAt(1, Layout.plotCenter(1) + Vector3.new(0, 3, 0))) == nil)
	check("layer 1 is just under the ground", Layout.cellCenter(1, 3, 1, 3).Y == -MineConfig.CELL / 2)
end

-- Backpack
do
	local function holder(): any
		return { items = {}, nextId = 1, pack = 1, shovel = 1, coins = 0, found = {}, stats = { dug = 0, sold = 0, earned = 0 }, deepest = 0, rebirths = 0, passes = {}, boostUntil = 0, daily = { last = 0, streak = 0 }, checkpoint = 0 }
	end
	local data = holder()
	check("capacity of the first pack", Backpack.capacity(data) == Gear.PACKS[1].slots)
	for _ = 1, Backpack.capacity(data) do
		check("added", Backpack.add(data, { g = "Quartz", s = "Normal" }))
	end
	check("full", not Backpack.add(data, { g = "Quartz", s = "Normal" }) and Backpack.used(data) == Backpack.capacity(data))
	check("found recorded", data.found.Quartz == true)
	local count, coins = Backpack.sellAll(data)
	check("sold all", count == Gear.PACKS[1].slots and coins == 5 * count and data.coins == coins and Backpack.used(data) == 0)
	check("stats", data.stats.sold == count and data.stats.earned == coins)
	-- a Huge gem takes 4 slots
	local d2 = holder()
	for _ = 1, Backpack.capacity(d2) - 3 do
		Backpack.add(d2, { g = "Quartz", s = "Normal" })
	end
	check("a Huge gem doesn't fit in 3 slots", not Backpack.add(d2, { g = "Quartz", s = "Huge" }))
	check("a Big one does", Backpack.add(d2, { g = "Quartz", s = "Big" }))
	-- ids stay unique
	local d3 = holder()
	Backpack.add(d3, { g = "Ruby", s = "Normal" })
	Backpack.sellAll(d3)
	Backpack.add(d3, { g = "Amber", s = "Normal" })
	local ids = 0
	for id in d3.items do
		ids += 1
		check("a new gem gets a new id", id == "2")
	end
	check("one gem", ids == 1)
	-- groups
	local d4 = holder()
	Backpack.add(d4, { g = "Quartz", s = "Normal" })
	Backpack.add(d4, { g = "Quartz", s = "Normal" })
	Backpack.add(d4, { g = "Ruby", s = "Normal", m = "Golden" })
	local groups = Backpack.groups(d4)
	check("grouped, the dearest first", #groups == 2 and groups[1].key == "Ruby|Normal|Golden" and groups[2].count == 2)
	local snap = Snapshot.of(d4, 1000)
	check("snapshot", snap.used == 3 and snap.capacity == Gear.PACKS[1].slots and #snap.groups == 2 and snap.coins == 0)
end

-- Sell multiplier: rebirths, passes and boosts add up
do
	local function player(): any
		return { rebirths = 0, passes = {}, boostUntil = 0 }
	end
	local p = player()
	check("x1 to start", Multiplier.sell(p, 100) == 1)
	p.rebirths = 2
	check("each rebirth adds its bonus", Multiplier.sell(p, 100) == 1 + 2 * RebirthConfig.BONUS)
	p.passes.Coins2 = true
	check("2x Coins adds 1", Multiplier.sell(p, 100) == 2 + 2 * RebirthConfig.BONUS)
	p.passes.Vip = true
	check("VIP adds a quarter", Multiplier.sell(p, 100) == 2.25 + 2 * RebirthConfig.BONUS)
	p.boostUntil = 200
	check("a boost adds 1 while it lasts", Multiplier.sell(p, 100) == 3.25 + 2 * RebirthConfig.BONUS and Multiplier.sell(p, 300) == 2.25 + 2 * RebirthConfig.BONUS)
	-- selling uses it
	local data: any = { items = { ["1"] = { g = "Ruby", s = "Normal" } }, nextId = 2, pack = 1, coins = 0, found = {}, stats = { dug = 0, sold = 0, earned = 0 } }
	local count, coins = Backpack.sellAll(data, 2.5)
	check("sellAll applies the multiplier", count == 1 and coins == 100 and data.coins == 100)
end

-- Rebirth
do
	local data: any = { coins = 0, shovel = 4, pack = 3, items = { ["1"] = {} }, deepest = 20, rebirths = 0, checkpoint = 15 }
	check("too shallow", select(1, Rebirth.can(data)) == false and select(2, Rebirth.can(data)) ~= nil)
	data.deepest = RebirthConfig.LAYER
	check("too poor", select(1, Rebirth.can(data)) == false)
	data.coins = Rebirth.cost(0)
	check("deep enough and rich enough", select(1, Rebirth.can(data)) == true)
	check("each costs more", Rebirth.cost(1) == Rebirth.cost(0) * RebirthConfig.GROWTH and Rebirth.cost(2) > Rebirth.cost(1))
	data.coins -= Rebirth.cost(0)
	Rebirth.apply(data)
	check("rebirth starts over and keeps the count", data.coins == 0 and data.shovel == 1 and data.pack == 1 and next(data.items) == nil and data.deepest == 0 and data.checkpoint == 0 and data.rebirths == 1)
	check("and the mine's first rebirth is reachable with the Steel Shovel", MineGen.reach(4) >= RebirthConfig.LAYER and MineGen.reach(3) < RebirthConfig.LAYER)
end

-- Daily reward
do
	local day = 20000
	local now = day * 86400 + 3600
	local data: any = { daily = { last = 0, streak = 0 } }
	local ready, index = Daily.status(data, now)
	check("a new player has day 1 waiting", ready and index == 1)
	local coins, boost = Daily.claim(data, now, 10)
	check("day 1 pays at least its minimum", coins == math.max(DailyConfig.REWARDS[1].min, DailyConfig.REWARDS[1].income * 10) and boost == 0)
	check("not twice in a day", select(1, Daily.status(data, now + 5000)) == false and (Daily.claim(data, now + 5000, 10)) == 0)
	check("the next day is day 2", select(2, Daily.status(data, now + 86400)) == 2 and select(1, Daily.status(data, now + 86400)))
	-- skipping days pauses the streak: still day 2 (never reset)
	check("missed days don't reset it", select(2, Daily.status(data, now + 86400 * 9)) == 2)
	-- the whole cycle, then round again
	for i = 2, #DailyConfig.REWARDS do
		Daily.claim(data, (day + i) * 86400, 10)
	end
	check("after the last day, day 1 again", select(2, Daily.status(data, (day + 20) * 86400)) == 1)
	check("rewards grow", DailyConfig.REWARDS[7].income > DailyConfig.REWARDS[1].income)
	local _, b = Daily.claim({ daily = { last = 0, streak = 3 } }, now, 10)
	check("day 4 has a boost", b == DailyConfig.REWARDS[4].boost)
end

-- The drone while away
do
	check("short absences earn nothing", Offline.coins(OfflineConfig.MIN_AWAY - 1, false, 100, 1) == 0)
	check("an hour away", Offline.coins(3600, false, 100, 1) == math.floor(60 * 100 * OfflineConfig.RATE))
	check("capped at the free hours", Offline.counted(100 * 3600, false) == OfflineConfig.FREE_HOURS * 3600)
	check("the pass raises the cap", Offline.counted(100 * 3600, true) == OfflineConfig.PASS_HOURS * 3600 and Offline.counted(5 * 3600, true) == 5 * 3600)
	check("the multiplier applies", Offline.coins(3600, false, 100, 2) == 2 * Offline.coins(3600, false, 100, 1))
	check("a long absence pays no more than the cap", Offline.coins(1000 * 3600, false, 100, 1) == Offline.coins(OfflineConfig.FREE_HOURS * 3600, false, 100, 1))
end

-- The elevator's steps
do
	check("no depth, no elevator", Depth.checkpoint(0) == 0 and Depth.checkpoint(1) == 0)
	check("steps of 5", Depth.checkpoint(5) == 0 and Depth.checkpoint(6) == 5 and Depth.checkpoint(11) == 10 and Depth.checkpoint(40) == 35)
end

-- The economy: pacing of a player who always buys the cheapest next upgrade (a model, balanced to these targets)
do
	check("gems are worth more deeper", Economy.gemValue(1) < Economy.gemValue(10) and Economy.gemValue(10) < Economy.gemValue(20) and Economy.gemValue(20) < Economy.gemValue(30) and Economy.gemValue(30) < Economy.gemValue(40))
	check("a better shovel digs faster", Economy.blockSeconds(2, 10) < Economy.blockSeconds(1, 10))
	check("a bigger pack earns more per minute", Economy.perMinute(1, 2, 5) > Economy.perMinute(1, 1, 5))
	local shovel, pack, coins, t, deepest = 1, 1, 0, 0, 1
	local bought = {}
	local rebirthAt: number? = nil
	while t < 4 * 3600 do
		local layer, rate = Economy.best(shovel, pack, MineConfig.MAX_LAYER)
		deepest = math.max(deepest, layer)
		coins += rate / 60 * 5
		t += 5
		local ns, np = Gear.SHOVELS[shovel + 1], Gear.PACKS[pack + 1]
		local buyShovel = ns ~= nil and (np == nil or ns.price <= np.price)
		if buyShovel and coins >= ns.price then
			coins -= ns.price
			shovel += 1
			table.insert(bought, { kind = "shovel", minutes = t / 60 })
		elseif np ~= nil and not buyShovel and coins >= np.price then
			coins -= np.price
			pack += 1
			table.insert(bought, { kind = "pack", minutes = t / 60 })
		end
		if not rebirthAt and deepest >= RebirthConfig.LAYER and coins >= Rebirth.cost(0) then
			rebirthAt = t / 60
		end
	end
	print("")
	print("economy model: when a player who always buys the cheapest next upgrade gets each (minutes)")
	for _, b in bought do
		print(string.format("  %-6s at %6.1f", b.kind, b.minutes))
	end
	print(string.format("  first rebirth possible at %.1f minutes", rebirthAt or -1))
	check("the first upgrade comes within 3 minutes", bought[1] ~= nil and bought[1].minutes <= 3)
	check("the second within 6", bought[2] ~= nil and bought[2].minutes <= 6)
	check("all ten upgrades are bought", #bought == #Gear.SHOVELS - 1 + #Gear.PACKS - 1)
	check("they take a while: the last is after an hour", bought[#bought].minutes > 60)
	check("the first rebirth takes 1.5 to 4 hours of free play", rebirthAt ~= nil and rebirthAt >= 90 and rebirthAt <= 240)
	-- the first sale: a full first pack takes under 3 minutes by hand
	local gemsPerBlock = MineConfig.GEM_CHANCE + MineConfig.GEODE_CHANCE * MineConfig.GEODE_GEMS
	local blocks = Gear.PACKS[1].slots / Economy.SLOTS_PER_GEM / gemsPerBlock
	check("the first backpack fills in under 3 minutes", blocks * Economy.blockSeconds(1, 1) < 180, tostring(blocks * Economy.blockSeconds(1, 1)))
	-- the Robux packs: an hour of income shouldn't skip the game
	check("every product and pass is set up with a name and a price", (function()
		for _, pass in Passes.PASSES do
			if pass.name == "" or pass.price <= 0 or pass.key == "" then
				return false
			end
		end
		for _, product in Passes.PRODUCTS do
			if product.name == "" or product.price <= 0 or not (product.boostMinutes or product.incomeMinutes) then
				return false
			end
		end
		return true
	end)())
end

-- Backpack: all-or-nothing for several gems
do
	local d: any = { items = {}, nextId = 1, pack = 1, coins = 0, found = {}, stats = { dug = 0, sold = 0, earned = 0 } }
	for _ = 1, Gear.PACKS[1].slots - 3 do
		Backpack.add(d, { g = "Quartz", s = "Normal" })
	end
	check("three Normal gems fit in 3 slots", Backpack.fitsAll(d, { { g = "Quartz", s = "Normal" }, { g = "Quartz", s = "Normal" }, { g = "Quartz", s = "Normal" } }))
	check("a Big and two Normal ones don't", not Backpack.fitsAll(d, { { g = "Quartz", s = "Big" }, { g = "Quartz", s = "Normal" }, { g = "Quartz", s = "Normal" } }))
end

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	process.exit(1)
end
