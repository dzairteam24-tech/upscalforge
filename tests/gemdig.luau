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
	check("zones", MineGen.zone(1).name == "Dirt" and MineGen.zone(9).name == "Stone" and MineGen.zone(30).name == "Deep")
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
		return { items = {}, nextId = 1, pack = 1, coins = 0, found = {}, stats = { dug = 0, sold = 0, earned = 0 } }
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
	local snap = Snapshot.of(d4)
	check("snapshot", snap.used == 3 and snap.capacity == Gear.PACKS[1].slots and #snap.groups == 2 and snap.coins == 0)
end

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	process.exit(1)
end
