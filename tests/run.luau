-- Unit tests for the pure game logic. Run from the repo root:  lune run tests/run.luau

local process = require("@lune/process")
local Loader = require("./loader")

local Shared = Loader.root("roblox/shared", "Shared")
local R = Loader.require

local Constants = R(Shared.Config.Constants)
local Upgrades = R(Shared.Config.Upgrades)
local World1 = R(Shared.Config.World1)
local Variants = R(Shared.Config.Variants)
local Format = R(Shared.Logic.Format)
local Effects = R(Shared.Logic.Effects)
local PetMath = R(Shared.Logic.PetMath)
local EggRoll = R(Shared.Logic.EggRoll)
local Inventory = R(Shared.Logic.Inventory)
local TradeLogic = R(Shared.Logic.TradeLogic)
local Combo = R(Shared.Logic.Combo)

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

local function near(actual: number, expected: number, tolerance: number, label: string?)
	if math.abs(actual - expected) > tolerance then
		error(("%s: expected %s ± %s, got %s"):format(label or "value", expected, tolerance, actual), 2)
	end
end

-- Deterministic random numbers for repeatable rolls.
local function makeRng(seed: number): () -> number
	math.randomseed(seed)
	return function()
		return math.random()
	end
end

local function idGen(): () -> string
	local n = 0
	return function()
		n += 1
		return "p" .. n
	end
end

-- Format ---------------------------------------------------------------------------------------------------

test("Format.abbrev", function()
	eq(Format.abbrev(0), "0")
	eq(Format.abbrev(999), "999")
	eq(Format.abbrev(1000), "1K")
	eq(Format.abbrev(1500), "1.5K")
	eq(Format.abbrev(25300000), "25.3M")
	eq(Format.abbrev(999999), "999K")
	eq(Format.abbrev(1e12), "1T")
	eq(Format.abbrev(-2500), "-2.5K")
	eq(Format.abbrev(1e40), "1.00e40")
end)

test("Format.chance", function()
	eq(Format.chance(0.6), "60%")
	eq(Format.chance(0.09), "9%")
	eq(Format.chance(1 / 50000), "1 in 50K")
end)

-- Config ---------------------------------------------------------------------------------------------------

test("World 1 has 10 zones + hub and 40 species", function()
	eq(#World1.zones, 11, "zones")
	eq(#World1.speciesOrder, 40, "species")
end)

test("Every egg's chances add up to 100%", function()
	for _, zone in World1.zones do
		if #zone.species > 0 then
			local total = 0
			for _, speciesId in zone.species do
				total += World1.species[speciesId].chance
			end
			near(total, 1, 1e-9, zone.name)
		end
	end
end)

test("Zone links are symmetric", function()
	for _, zone in World1.zones do
		for _, other in zone.links do
			local back = World1.zonesById[other]
			assert(back, "missing zone " .. other)
			assert(table.find(back.links, zone.id), ("%d -> %d has no way back"):format(zone.id, other))
		end
	end
end)

test("Every species has Big and Titan skill text", function()
	for _, speciesId in World1.speciesOrder do
		local species = World1.species[speciesId]
		assert(#species.big.text > 0, speciesId .. " big")
		assert(#species.titan.text > 0, speciesId .. " titan")
		assert(species.titan.passive or species.titan.periodic, speciesId .. " titan has no effect")
	end
end)

test("Upgrades.nextCost", function()
	eq(Upgrades.nextCost("TeamSlots", 0), 1e3)
	eq(Upgrades.nextCost("TeamSlots", 6), nil)
	eq(Upgrades.maxLevel("Hatch8"), 1)
	eq(Upgrades.byId.Hatch8.requires, "Hatch3")
end)

-- PetMath / Effects ----------------------------------------------------------------------------------------

test("Power = species x variant x size", function()
	eq(PetMath.basePower({ s = "Kitty", v = "Normal", z = "Normal" }), 2)
	eq(PetMath.basePower({ s = "Kitty", v = "Pixel", z = "Normal" }), 20)
	eq(PetMath.basePower({ s = "Kitty", v = "Pixel", z = "Big" }), 60)
	eq(PetMath.basePower({ s = "Kitty", v = "Pixel", z = "Titan" }), 200)
end)

test("Big Uni hits twice", function()
	eq(PetMath.basePower({ s = "Uni", v = "Normal", z = "Big" }), 12 * 3 * 2)
end)

test("Element bonus: Lava is x2 in Ice zones only", function()
	local pets = { a = { s = "Cubby", v = "Lava", z = "Normal" } }
	local none = Effects.empty()
	eq((PetMath.teamPower(pets, { "a" }, "Ice", none)), 8)
	eq((PetMath.teamPower(pets, { "a" }, "Fire", none)), 4)
end)

test("Titan Glowworm raises the element bonus to x4", function()
	local pets = {
		a = { s = "Cubby", v = "Lava", z = "Normal" },
		g = { s = "Glowworm", v = "Normal", z = "Titan" },
	}
	local effects = Effects.collect(pets, { "a", "g" })
	-- Cubby Lava 4 x4 = 16, Titan Glowworm 200 (no element bonus) = 216
	eq((PetMath.teamPower(pets, { "a", "g" }, "Ice", effects)), 216)
end)

test("Same skill doesn't stack: two Titan Bears give x2, not x4", function()
	local pets = {
		a = { s = "Bear", v = "Normal", z = "Titan" },
		b = { s = "Bear", v = "Normal", z = "Titan" },
	}
	local effects = Effects.collect(pets, { "a", "b" })
	eq(Effects.get(effects, "TeamPower"), 2)
	eq((PetMath.teamPower(pets, { "a", "b" }, "Neutral", effects)), (50 + 50) * 2)
end)

test("Different skills multiply: Titan Bear x2 and Titan King x5 -> x5 (max of same type)", function()
	local pets = {
		a = { s = "Bear", v = "Normal", z = "Titan" },
		k = { s = "King", v = "Normal", z = "Titan" },
	}
	local effects = Effects.collect(pets, { "a", "k" })
	eq(Effects.get(effects, "TeamPower"), 5)
end)

test("Titan Phoenix gives every creature the strongest power", function()
	local pets = {
		p = { s = "Phoenix", v = "Normal", z = "Titan" }, -- 1900
		c = { s = "Cubby", v = "Normal", z = "Normal" }, -- 1
	}
	local effects = Effects.collect(pets, { "p", "c" })
	eq((PetMath.teamPower(pets, { "p", "c" }, "Neutral", effects)), 3800)
end)

test("Effects collects periodic skills with unique keys", function()
	local pets = { i = { s = "Imp", v = "Normal", z = "Titan" } }
	local effects = Effects.collect(pets, { "i" })
	eq(#effects.periodic, 2)
	eq(effects.periodic[1].key, "i:1")
	eq(effects.periodic[2].spec.kind, "Wave")
end)

-- EggRoll --------------------------------------------------------------------------------------------------

test("Species frequencies follow the egg chances", function()
	local rng = makeRng(42)
	local counts = {}
	local n = 200000
	for _ = 1, n do
		local roll = EggRoll.roll(1, { luck = 1 }, rng)
		counts[roll.s] = (counts[roll.s] or 0) + 1
	end
	near(counts.Cubby / n, 0.6, 0.01, "Cubby")
	near(counts.Kitty / n, 0.3, 0.01, "Kitty")
	near(counts.Bunny / n, 0.09, 0.005, "Bunny")
	near(counts.Bear / n, 0.01, 0.002, "Bear")
end)

test("Golden shows up about 1 in 50", function()
	local rng = makeRng(7)
	local golden, n = 0, 200000
	for _ = 1, n do
		if EggRoll.roll(1, { luck = 1 }, rng).v == "Golden" then
			golden += 1
		end
	end
	near(golden / n, 1 / 50, 0.002, "Golden rate")
end)

test("Luck raises rare variant chances", function()
	eq(EggRoll.variantChance("Pixel", { luck = 1 }), 1 / 50000)
	eq(EggRoll.variantChance("Pixel", { luck = 10 }), 10 / 50000)
	eq(EggRoll.variantChance("Pixel", { luck = 10, variantChance = { Pixel = 5 } }), 50 / 50000)
end)

test("forceGolden and minVariant", function()
	local rng = makeRng(1)
	for _ = 1, 200 do
		local roll = EggRoll.roll(1, { luck = 1, forceGolden = true }, rng)
		assert(Variants.byId[roll.v].order >= 2, "expected Golden or better")
		local roll2 = EggRoll.roll(1, { luck = 1, minVariant = "Crystal" }, rng)
		assert(Variants.byId[roll2.v].order >= 3, "expected Crystal or better")
	end
end)

test("Rolls always return valid ids", function()
	local rng = makeRng(99)
	for zoneId = 1, 10 do
		for _ = 1, 500 do
			local roll = EggRoll.roll(zoneId, { luck = 1e6 }, rng)
			assert(World1.species[roll.s], "species")
			assert(World1.species[roll.s].zone == zoneId, "species from another zone")
			assert(Variants.byId[roll.v], "variant")
		end
	end
end)

-- Inventory ------------------------------------------------------------------------------------------------

test("Equip respects the slot limit", function()
	local holder = { pets = {}, equipped = {} }
	local gen = idGen()
	for _ = 1, 3 do
		Inventory.add(holder, { s = "Cubby", v = "Normal", z = "Normal" }, gen)
	end
	assert(Inventory.equip(holder, "p1", 2))
	assert(Inventory.equip(holder, "p2", 2))
	local ok = Inventory.equip(holder, "p3", 2)
	eq(ok, false, "third equip")
end)

test("equipBest picks the strongest", function()
	local holder = { pets = {}, equipped = {} }
	local gen = idGen()
	Inventory.add(holder, { s = "Cubby", v = "Normal", z = "Normal" }, gen) -- 1
	Inventory.add(holder, { s = "Bear", v = "Normal", z = "Normal" }, gen) -- 5
	Inventory.add(holder, { s = "Kitty", v = "Golden", z = "Normal" }, gen) -- 3
	Inventory.equipBest(holder, 2)
	eq(holder.equipped[1], "p2")
	eq(holder.equipped[2], "p3")
end)

test("Removing a creature unequips it", function()
	local holder = { pets = {}, equipped = {} }
	local id = Inventory.add(holder, { s = "Cubby", v = "Normal", z = "Normal" }, idGen())
	Inventory.equip(holder, id, 6)
	Inventory.remove(holder, id)
	eq(#holder.equipped, 0)
	eq(holder.pets[id], nil)
end)

test("Fusion: 5 Normal -> 1 Golden, skips locked, uses team last", function()
	local holder = { pets = {}, equipped = {} }
	local gen = idGen()
	for _ = 1, 6 do
		Inventory.add(holder, { s = "Kitty", v = "Normal", z = "Normal" }, gen)
	end
	Inventory.setLocked(holder, "p1", true)
	Inventory.equip(holder, "p2", 6)
	local newId, err = Inventory.fuse(holder, "Kitty", "Normal", Constants.FUSION_COST, gen)
	assert(newId, err)
	eq(holder.pets[newId].v, "Golden")
	assert(holder.pets.p1, "locked creature must stay")
	eq(Inventory.count(holder), 2)
	-- Only one unlocked Normal is left, so a second fusion fails
	local again = Inventory.fuse(holder, "Kitty", "Normal", Constants.FUSION_COST, gen)
	eq(again, nil)
end)

test("Pixel can't be fused further", function()
	local holder = { pets = {}, equipped = {} }
	local _, err = Inventory.fuse(holder, "Kitty", "Pixel", 5, idGen())
	assert(err, "expected an error")
end)

-- Trading --------------------------------------------------------------------------------------------------

local function tradeSetup()
	local gen = idGen()
	local a = { pets = {}, equipped = {}, capacity = 100 }
	local b = { pets = {}, equipped = {}, capacity = 100 }
	local a1 = Inventory.add(a, { s = "Bear", v = "Golden", z = "Normal" }, gen)
	local b1 = Inventory.add(b, { s = "Uni", v = "Normal", z = "Big" }, gen)
	Inventory.equip(a, a1, 6)
	return a, b, a1, b1
end

test("Trade: ready is locked for 3 seconds after any change", function()
	local _, _, a1, b1 = tradeSetup()
	local s = TradeLogic.new(1, 2, 0)
	assert(TradeLogic.setOffer(s, 1, { a1 }, 10))
	assert(TradeLogic.setOffer(s, 2, { b1 }, 10))
	local ok = TradeLogic.setReady(s, 1, 11)
	eq(ok, false, "ready during lock")
	assert(TradeLogic.setReady(s, 1, 13))
	assert(TradeLogic.setReady(s, 2, 13))
	eq(s.stage, "Confirm")
end)

test("Trade: changing an offer resets both players", function()
	local _, _, a1, b1 = tradeSetup()
	local s = TradeLogic.new(1, 2, 0)
	TradeLogic.setOffer(s, 1, { a1 }, 0)
	TradeLogic.setOffer(s, 2, { b1 }, 0)
	TradeLogic.setReady(s, 1, 5)
	TradeLogic.setReady(s, 2, 5)
	eq(s.stage, "Confirm")
	TradeLogic.setOffer(s, 2, {}, 6)
	eq(s.stage, "Offer")
	eq(s.ready[1], false)
	local done = TradeLogic.confirm(s, 1)
	eq(done, false)
end)

test("Trade: full swap moves creatures and unequips them", function()
	local a, b, a1, b1 = tradeSetup()
	local s = TradeLogic.new(1, 2, 0)
	TradeLogic.setOffer(s, 1, { a1 }, 0)
	TradeLogic.setOffer(s, 2, { b1 }, 0)
	TradeLogic.setReady(s, 1, 5)
	TradeLogic.setReady(s, 2, 5)
	eq((TradeLogic.confirm(s, 1)), false)
	eq((TradeLogic.confirm(s, 2)), true)
	assert(TradeLogic.validate(s, a, b))
	TradeLogic.execute(s, a, b)
	eq(a.pets[b1].s, "Uni")
	eq(b.pets[a1].s, "Bear")
	eq(a.pets[a1], nil)
	eq(#a.equipped, 0)
	eq(s.stage, "Done")
end)

test("Trade: locked creatures and full storage are rejected", function()
	local a, b, a1, b1 = tradeSetup()
	local s = TradeLogic.new(1, 2, 0)
	TradeLogic.setOffer(s, 1, { a1 }, 0)
	Inventory.setLocked(a, a1, true)
	local ok, err = TradeLogic.validate(s, a, b)
	eq(ok, false)
	eq(err, "Locked creatures can't be traded")
	Inventory.setLocked(a, a1, false)
	b.capacity = 1 -- b already has 1 creature
	ok = TradeLogic.validate(s, a, b)
	eq(ok, false, "storage")
end)

test("Trade: offer size limit and duplicates", function()
	local s = TradeLogic.new(1, 2, 0)
	local many = {}
	for i = 1, Constants.TRADE_MAX_PETS + 1 do
		many[i] = "x" .. i
	end
	eq((TradeLogic.setOffer(s, 1, many, 0)), false)
	TradeLogic.setOffer(s, 1, { "a", "a", "b" }, 0)
	eq(#s.offers[1], 2)
	eq((TradeLogic.setOffer(s, 3, {}, 0)), false, "outsider")
end)

-- Combo ----------------------------------------------------------------------------------------------------

test("Combo multiplier steps", function()
	eq(Combo.multiplier(0), 1)
	eq(Combo.multiplier(5), 1.5)
	eq(Combo.multiplier(19), 2)
	eq(Combo.multiplier(20), 3)
	eq(Combo.multiplier(500), 5)
end)

-- PetModel (builds real Roblox instances through Lune, so wrong property names fail here) -----------------

test("Every creature model builds: 40 species x 6 variants x 3 sizes", function()
	local PetModel = R(Shared.PetModel)
	local Sizes = R(Shared.Config.Sizes)
	local built = 0
	for _, speciesId in World1.speciesOrder do
		for _, variant in Variants.list do
			for _, size in Sizes.list do
				local result = PetModel.build({ s = speciesId, v = variant.id, z = size.id })
				assert(#result.parts == #result.offsets, "parts and offsets differ")
				assert(result.model.PrimaryPart == result.body, "missing primary part")
				built += 1
			end
		end
	end
	eq(built, 40 * 6 * 3)
end)

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	process.exit(1)
end
