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

-- Boosts, items and loot ------------------------------------------------------------------------------------

local Items = R(Shared.Config.Items)
local Boosts = R(Shared.Logic.Boosts)
local Bag = R(Shared.Logic.Bag)
local Loot = R(Shared.Logic.Loot)

test("Boosts: strongest counts, only it ticks, weaker time is kept", function()
	local b = {}
	Boosts.add(b, "Coins", 2, 100, 14400)
	Boosts.add(b, "Coins", 3, 10, 14400)
	eq(Boosts.active(b, "Coins"), 3)
	Boosts.tick(b, 10)
	eq(Boosts.active(b, "Coins"), 2, "falls back to x2")
	eq(b.Coins["2"], 100, "x2 time untouched while x3 ran")
	Boosts.tick(b, 100)
	eq(Boosts.active(b, "Coins"), 1)
	eq(b.Coins, nil, "cleaned up")
end)

test("Boosts: stacking time is capped at 4 hours", function()
	local b = {}
	for _ = 1, 30 do
		Boosts.add(b, "Luck", 2, 1800, Items.BOOST_CAP_SECONDS)
	end
	eq(b.Luck["2"], 4 * 3600)
end)

test("Items: elixirs, cartridges, keys, stickers (7 x 3) and gadgets", function()
	local kinds = {}
	for _, item in Items.list do
		kinds[item.kind] = (kinds[item.kind] or 0) + 1
	end
	eq(kinds.Elixir, 10 * 5, "elixirs")
	eq(kinds.Cartridge, 10 * 5 + 5, "cartridges")
	eq(kinds.Key, 3, "keys")
	eq(kinds.KeyHalf, 3, "halves")
	eq(kinds.Sticker, 7 * 3, "stickers")
	eq(kinds.Gadget, 5, "gadgets")
	eq(Items.nextTier("Elixir_Coins_4"), "Elixir_Coins_5")
	eq(Items.nextTier("Elixir_Coins_5"), nil)
	eq(Items.mixResult("Elixir_Luck_2", "Elixir_Coins_2"), "Elixir_Fortune_2")
	eq(Items.mixResult("Elixir_Luck_2", "Elixir_Coins_3"), nil, "different tiers")
	eq(Items.byId.Elixir_Fortune_2.boosts[2].stat, "Luck")
end)

test("Bag: merge 3 -> next tier, mix two -> double", function()
	local items = { Elixir_Coins_1 = 4, Elixir_Luck_1 = 1 }
	local merged = Bag.merge(items, "Elixir_Coins_1")
	eq(merged, "Elixir_Coins_2")
	eq(items.Elixir_Coins_1, 1)
	local mixed = Bag.mix(items, "Elixir_Coins_1", "Elixir_Luck_1")
	eq(mixed, "Elixir_Fortune_1")
	eq(items.Elixir_Coins_1, nil)
	eq(items.Elixir_Luck_1, nil)
	local none = Bag.merge(items, "Elixir_Coins_2")
	eq(none, nil, "only one left")
end)

test("Loot: vaults drop often, piles rarely, late zones drop higher tiers", function()
	local rng = makeRng(5)
	local vault, pile = 0, 0
	for _ = 1, 20000 do
		if Loot.roll("Vault", 1, rng) then
			vault += 1
		end
		if Loot.roll("Pile", 1, rng) then
			pile += 1
		end
	end
	near(vault / 20000, 0.4, 0.02, "vault")
	near(pile / 20000, 0.002, 0.002, "pile")
	for _ = 1, 200 do
		local id = Loot.roll("Guardian", 9, rng)
		assert(id and Items.byId[id], "guardian always drops a real item")
		assert(Items.byId[id].tier >= 5, "zone 9 guardian drops tier 5")
	end
end)

-- Cartridges, keys, trips, reload ----------------------------------------------------------------------------

local Gear = R(Shared.Logic.Gear)
local Expedition = R(Shared.Logic.Expedition)
local Expeditions = R(Shared.Config.Expeditions)
local Reload = R(Shared.Logic.Reload)

test("Gear: slots grow with Reloads up to 6", function()
	eq(Gear.slots(0), 2)
	eq(Gear.slots(3), 5)
	eq(Gear.slots(10), 6)
end)

test("Gear: multiplicative and additive stats, defaults", function()
	local gear = Gear.compute({ "Cart_Coins_2", "Cart_Jackpot_3", "Cart_Combo_4" })
	near(Gear.get(gear, "Coins"), 1.25, 1e-9, "coins")
	near(Gear.get(gear, "Jackpot"), 0.03, 1e-9, "jackpot")
	eq(Gear.get(gear, "ComboHold"), 4, "combo hold")
	eq(Gear.get(gear, "Luck"), 1, "missing multiplier")
	eq(Gear.get(gear, "GoldenSources"), 0, "missing additive")
	eq(#gear.sets, 0, "no set without Chest Breaker")
end)

test("Gear: completing a set adds its bonus", function()
	local rich = Gear.compute({ "Cart_Coins_1", "Cart_Jackpot_1", "Cart_ChestBreaker_1" })
	eq(rich.sets[1], "Rich")
	near(Gear.get(rich, "Coins"), 1.1 * 1.25, 1e-9, "Rich coins")
	local fighter = Gear.compute({ "Cart_Power_1", "Cart_Combo_1", "Cart_Speed_1" })
	eq(fighter.fighter, true)
	local idle = Gear.compute({ "Cart_Offline_1", "Cart_Gems_1", "Cart_Tap_1" })
	eq(Gear.get(idle, "OfflineHours"), 4)
	local hatcher = Gear.compute({ "Cart_Lucky_1", "Cart_PixelSeeker_1", "Cart_DoubleHatch_1" })
	eq(Gear.get(hatcher, "HatchSpeed"), 2)
end)

test("Gear: one cartridge per family and a slot limit", function()
	assert(Gear.canEquip({}, "Cart_Coins_1", 2))
	eq((Gear.canEquip({ "Cart_Coins_1" }, "Cart_Coins_3", 2)), false, "same family")
	eq((Gear.canEquip({ "Cart_Coins_1", "Cart_Power_1" }, "Cart_Lucky_1", 2)), false, "full")
	eq((Gear.canEquip({}, "Elixir_Coins_1", 2)), false, "not a cartridge")
end)

test("Bag: 2 key halves make a key, 3 cartridges merge, rare ones don't", function()
	local items = { KeyHalf_Titan = 3, Cart_Power_1 = 3, Cart_AutoTap_1 = 5 }
	eq(Bag.merge(items, "KeyHalf_Titan"), "Key_Titan")
	eq(items.KeyHalf_Titan, 1)
	eq(Bag.merge(items, "Cart_Power_1"), "Cart_Power_2")
	eq(items.Cart_Power_1, nil)
	eq(Bag.merge(items, "Cart_AutoTap_1"), nil, "rare")
	eq(items.Cart_AutoTap_1, 5)
end)

test("Loot: cartridges and key halves drop from the right sources", function()
	local rng = makeRng(11)
	local cartridges, halves, rare = 0, 0, 0
	for _ = 1, 10000 do
		for _, id in Loot.rollAll("Guardian", 3, rng) do
			local item = Items.byId[id]
			assert(item, "unknown drop " .. id)
			if item.kind == "Cartridge" then
				cartridges += 1
				if (Items.cartridgeFamily(item.family) :: any).rare then
					rare += 1
				end
			elseif item.kind == "KeyHalf" then
				halves += 1
			end
		end
	end
	near(cartridges / 10000, 0.6, 0.03, "guardian cartridges")
	near(halves / 10000, 0.5, 0.03, "guardian titan halves")
	near(rare / cartridges, 0.03, 0.01, "rare share")
	for _ = 1, 2000 do
		for _, id in Loot.rollAll("Pile", 1, rng) do
			eq(Items.byId[id].kind, "Elixir", "coin piles only drop elixirs")
		end
	end
end)

local function tripData()
	local data = {
		pets = {},
		equipped = {},
		expeditions = {},
		reloads = 0,
		coins = 500,
		unlockedZones = { ["0"] = true, ["1"] = true },
		zoneProgress = { ["1"] = 100 },
		items = { Elixir_Coins_1 = 2 },
		stats = {},
	}
	local gen = idGen()
	for _ = 1, 4 do
		Inventory.add(data, { s = "Bear", v = "Lava", z = "Normal" }, gen)
	end
	Inventory.add(data, { s = "Cubby", v = "Normal", z = "Normal" }, gen)
	Inventory.equip(data, "p5", 6)
	return data
end

test("Trips: validation", function()
	local data = tripData()
	eq((Expedition.validate(data, "Nope", { "p1" })), false, "unknown kind")
	eq((Expedition.validate(data, "Short", { "p1", "p2" })), false, "too few")
	eq((Expedition.validate(data, "Short", { "p1", "p1", "p2" })), false, "duplicate")
	eq((Expedition.validate(data, "Short", { "p1", "p2", "p5" })), false, "equipped")
	eq((Expedition.validate(data, "Short", { "p1", "p2", "zz" })), false, "missing")
	assert(Expedition.validate(data, "Short", { "p1", "p2", "p3" }))
end)

test("Trips: away creatures are locked out until the trip is claimed", function()
	local data = tripData()
	local trip = Expedition.start(data, "Short", { "p1", "p2", "p3" }, 1000)
	eq(trip.ends, 1000 + Expeditions.byId.Short.duration)
	eq(trip.element, true, "all Lava")
	near(trip.power, 3 * PetMath.basePower(data.pets.p1), 1e-9, "power")
	eq(data.pets.p1.ex, true)
	eq((Inventory.equip(data, "p1", 6)), false, "can't equip an away creature")
	eq((Expedition.validate(data, "Short", { "p1", "p4", "p2" })), false, "already away")

	eq((Expedition.claim(data, 1, trip.ends - 1)), nil, "too early")
	local claimed = Expedition.claim(data, 1, trip.ends)
	assert(claimed, "claim")
	eq(data.pets.p1.ex, nil)
	eq(#data.expeditions, 0)
end)

test("Trips: slots, element bonus and rewards", function()
	local data = tripData()
	eq(Expedition.slots(0), 2)
	eq(Expedition.slots(4), 4)
	eq(Expedition.slots(40), Expeditions.MAX_SLOTS)
	Expedition.start(data, "Short", { "p1", "p2", "p3" }, 0)
	data.expeditions[2] = { kind = "Short", pets = {}, started = 0, ends = 0, power = 0, element = false }
	eq((Expedition.validate(data, "Short", { "p4", "p4", "p4" })), false, "slots full")

	local mixed = { kind = "Short", pets = {}, started = 0, ends = 0, power = 10, element = false }
	local same = { kind = "Short", pets = {}, started = 0, ends = 0, power = 10, element = true }
	local rng = makeRng(3)
	local a = Expedition.rewards(mixed, 1, rng)
	local b = Expedition.rewards(same, 1, rng)
	near(a.coins, 10 * 1800 * 0.3, 1e-6, "coins")
	near(b.coins, a.coins * Expeditions.ELEMENT_BONUS, 1e-6, "element bonus")
	eq(#a.items, Expeditions.byId.Short.elixirs)
	eq(Expedition.sharedElement({ { s = "Cubby", v = "Normal", z = "Normal" } }), false, "Normal has no element")
	eq(Expedition.sharedElement({ { s = "Cubby", v = "Golden", z = "Normal" }, { s = "Bear", v = "Golden", z = "Big" } }), true)

	local long = { kind = "Long", pets = {}, started = 0, ends = 0, power = 10, element = false }
	local cartridges = 0
	for _ = 1, 4000 do
		for _, id in Expedition.rewards(long, 5, rng).items do
			assert(Items.byId[id], "unknown reward " .. id)
			if Items.byId[id].kind == "Cartridge" then
				cartridges += 1
			end
		end
	end
	near(cartridges / 4000, Expeditions.byId.Long.cartridgeChance, 0.03, "long trip cartridges")
end)

test("Trips: repair fixes creatures marked away without a trip", function()
	local data = tripData()
	data.pets.p1.ex = true
	data.expeditions = { { kind = "Short", pets = { "p2" }, started = 0, ends = 0, power = 0, element = false } }
	Expedition.repair(data)
	eq(data.pets.p1.ex, nil)
	eq(data.pets.p2.ex, true)
end)

test("Reload: needs the last zone, resets the run, keeps creatures and items", function()
	local data = tripData()
	eq((Reload.canReload(data)), false)
	data.unlockedZones[tostring(Constants.RELOAD_REQUIRED_ZONE)] = true
	assert(Reload.canReload(data))
	local preview = Reload.preview(data)
	eq(preview.reloads, 1)
	near(preview.coinMult, 1.5, 1e-9)
	eq(preview.cartridgeSlots, 3)
	Reload.apply(data)
	eq(data.reloads, 1)
	eq(data.coins, 0)
	eq(data.unlockedZones["10"], nil)
	eq(data.unlockedZones["1"], true)
	eq(next(data.zoneProgress), nil)
	eq(Inventory.count(data), 5, "creatures kept")
	eq(data.items.Elixir_Coins_1, 2, "items kept")
	near(Reload.coinMult(3), 3.375, 1e-9)
	assert(Reload.tint(0) ~= Reload.tint(1), "new palette")
end)

test("Format.mult", function()
	eq(Format.mult(1), "x1")
	eq(Format.mult(1.5), "x1.5")
	eq(Format.mult(3.375), "x3.38")
	eq(Format.mult(1500), "x1.5K")
end)

-- Daily, quests, pass, rift -----------------------------------------------------------------------------------

local Progress = R(Shared.Logic.Progress)
local Progression = R(Shared.Config.Progression)

test("Calendar: weeks start on Monday", function()
	-- 2026-10-04 is a Sunday, 2026-10-05 a Monday
	local sunday = 20730 * 86400 + 3600
	local monday = sunday + 86400
	eq(Progress.week(monday), Progress.week(sunday) + 1)
	eq(Progress.week(monday + 6 * 86400), Progress.week(monday))
end)

test("Daily: streak grows day by day, cycles after 7, resets after a missed day", function()
	local daily = { streak = 0, lastDay = -1 }
	for day = 1, 9 do
		local claimed = Progress.claimDaily(daily, 100 + day)
		eq(claimed, ((day - 1) % 7) + 1, "day " .. day)
		eq(Progress.claimDaily(daily, 100 + day), nil, "twice the same day")
	end
	eq(Progress.claimDaily(daily, 100 + 11), 1, "missed day 10")
end)

test("Quests: same player + day gives the same set; new day rerolls", function()
	local a = { day = -1, week = -1, daily = {}, weekly = {} }
	local b = { day = -1, week = -1, daily = {}, weekly = {} }
	local now = 20730 * 86400 + 500
	Progress.refreshQuests(a, now, 42, 1000)
	Progress.refreshQuests(b, now, 42, 1000)
	eq(#a.daily, Progression.DAILY_QUESTS)
	eq(#a.weekly, Progression.WEEKLY_QUESTS)
	for i = 1, #a.daily do
		eq(a.daily[i].id, b.daily[i].id)
	end
	eq(Progress.refreshQuests(a, now + 10, 42, 1000), false, "same day")
	eq(Progress.refreshQuests(a, now + 86400, 42, 1000), true, "next day")
end)

test("Quests: progress, max-type combo, claim once", function()
	local book = {
		day = 1,
		week = 1,
		daily = {
			{ id = "d_break", goal = 3, progress = 0, claimed = false },
			{ id = "d_combo", goal = 20, progress = 0, claimed = false },
		},
		weekly = {},
	}
	eq(Progress.claimQuest(book, "daily", 1), nil, "not done yet")
	Progress.addQuestProgress(book, "Break", 2)
	local done = Progress.addQuestProgress(book, "Break", 5)
	eq(#done, 1)
	eq(book.daily[1].progress, 3, "clamped to goal")
	Progress.addQuestProgress(book, "Combo", 12)
	Progress.addQuestProgress(book, "Combo", 4)
	eq(book.daily[2].progress, 12, "combo keeps the best")
	local reward = Progress.claimQuest(book, "daily", 1)
	assert(reward and reward.xp == 100, "daily reward")
	eq(Progress.claimQuest(book, "daily", 1), nil, "claimed once")
end)

test("Pass: levels, premium lock, cosmetics only on premium", function()
	local pass = { season = 0, xp = 0, premium = false, claimedFree = {}, claimedPremium = {} }
	local now = (20730 + 5) * 86400
	assert(Progress.refreshPass(pass, now), "first season set")
	eq(pass.season, 1)
	pass.xp = 5 * Progression.PASS_XP_PER_LEVEL
	eq(Progress.passLevel(pass.xp), 5)
	assert(Progress.claimPass(pass, 5, false), "free level 5")
	eq((Progress.claimPass(pass, 5, false)), nil, "claimed once")
	eq((Progress.claimPass(pass, 6, false)), nil, "level 6 not reached")
	eq((Progress.claimPass(pass, 5, true)), nil, "premium locked")
	pass.premium = true
	local premium = Progress.claimPass(pass, 5, true)
	assert(premium and premium.title, "premium gives a title")
	for level = 1, Progression.PASS_LEVELS do
		local reward = Progression.passReward(level, true)
		if reward then
			assert(not reward.coinsInEggs and not reward.gems and not reward.items and not reward.freeEggs, "premium is cosmetic only")
		end
	end
	assert(Progress.refreshPass(pass, now + 30 * 86400), "new season")
	eq(pass.season, 2)
	eq(pass.xp, 0)
	eq(pass.premium, false)
end)

test("Rift: one zone per day in range, same for everyone", function()
	local seen = {}
	for day = 20730, 20830 do
		local zone = Progress.riftZone(day, 10)
		assert(zone >= 1 and zone <= 10, "zone in range")
		seen[zone] = true
		eq(Progress.riftZone(day, 10), zone)
	end
	local distinct = 0
	for _ in seen do
		distinct += 1
	end
	assert(distinct >= 8, "rift moves around the map")
end)

-- PetModel (builds real Roblox instances through Lune, so wrong property names fail here) -----------------

-- Ads limits, streak save, quest swap, playtime gifts --------------------------------------------------------

local AdLimits = R(Shared.Logic.AdLimits)

test("Ads: daily limits reset each day, cooldowns block until they pass", function()
	local state = { day = 0, counts = {}, cooldowns = {} }
	for _ = 1, 3 do
		assert(AdLimits.canWatch(state, "AdReroll", 1000, 10))
		AdLimits.record(state, "AdReroll", 1000, 10)
	end
	eq((AdLimits.canWatch(state, "AdReroll", 1000, 10)), false, "4th reroll")
	eq(AdLimits.left(state, "AdReroll", 10), 0)
	eq(AdLimits.left(state, "AdReroll", 11), 3, "new day")
	AdLimits.refresh(state, 11)
	assert(AdLimits.canWatch(state, "AdReroll", 1000, 11))

	assert(AdLimits.canWatch(state, "AdElixir", 1000, 11))
	AdLimits.record(state, "AdElixir", 1000, 11)
	eq((AdLimits.canWatch(state, "AdElixir", 1000 + 3599, 11)), false, "cooldown")
	assert(AdLimits.canWatch(state, "AdElixir", 1000 + 3600, 11))
	eq(AdLimits.left(state, "AdCoins", 11), nil, "no limit")
end)

test("Daily: a broken streak can be saved by an ad for a few days", function()
	local daily = { streak = 5, lastDay = 100 }
	eq(Progress.streakSavable(daily, 101), false, "nothing missed")
	eq(Progress.streakSavable(daily, 102), true, "missed one day")
	eq(Progress.streakSavable(daily, 104), true, "missed three days")
	eq(Progress.streakSavable(daily, 105), false, "too late")
	eq(Progress.streakSavable({ streak = 1, lastDay = 100 }, 102), false, "nothing to save")
	assert(Progress.saveStreak(daily, 103))
	eq(Progress.claimDaily(daily, 103), 6, "streak continues")
	eq(daily.streak, 6)
end)

test("Quests: an unfinished daily quest can be swapped for a new one", function()
	local book = { day = -1, week = -1, daily = {}, weekly = {} }
	Progress.refreshQuests(book, 1700000000, 42, 100)
	local before = {}
	for _, quest in book.daily do
		before[quest.id] = true
	end
	local old = book.daily[1].id
	assert(Progress.rerollQuest(book, 1, 7, 100))
	assert(not before[book.daily[1].id], "new quest is one the player didn't have")
	assert(book.daily[1].id ~= old)
	eq(book.daily[1].progress, 0)
	book.daily[2].progress = book.daily[2].goal
	eq(Progress.rerollQuest(book, 2, 7, 100), false, "finished quests stay")
	eq(Progress.rerollQuest(book, 9, 7, 100), false, "missing index")
end)

test("Gifts: one every 15 minutes, opened in order, reset each day", function()
	local state = { day = 0, seconds = 0, claimed = 0 }
	Progress.refreshPlaytime(state, 5)
	eq(Progress.giftSecondsLeft(state), Progression.GIFT_SECONDS)
	eq((Progress.claimGift(state)), nil, "not yet")
	state.seconds = Progression.GIFT_SECONDS * 2
	local first = Progress.claimGift(state)
	local second = Progress.claimGift(state)
	eq(first, 1)
	eq(second, 2)
	eq((Progress.claimGift(state)), nil, "third isn't ready")
	state.seconds = Progression.GIFT_SECONDS * 100
	for _ = 3, #Progression.PLAYTIME_GIFTS do
		assert(Progress.claimGift(state))
	end
	eq(Progress.giftSecondsLeft(state), nil, "all opened")
	for _, reward in Progression.PLAYTIME_GIFTS do
		for _, entry in reward.items or {} do
			assert(Items.byId[entry.id], "unknown gift item " .. entry.id)
		end
	end
	Progress.refreshPlaytime(state, 6)
	eq(state.claimed, 0)
	eq(state.seconds, 0)
end)

-- Achievements and Rank -------------------------------------------------------------------------------------

local AchievementLogic = R(Shared.Logic.Achievements)
local AchievementConfig = R(Shared.Config.Achievements)
local Cosmetics = R(Shared.Config.Cosmetics)

local function awardData()
	return { stats = {}, achievements = {}, index = {}, reloads = 0, pets = {}, equipped = {}, expeditions = {} }
end

test("Achievements: tiers complete in order, several at once, only once", function()
	local data = awardData()
	data.stats.hatches = 600
	local done = AchievementLogic.check(data)
	eq(#done, 2, "50 and 500 hatches")
	eq(done[1].tier, 1)
	eq(done[2].tier, 2)
	eq(data.achievements.Hatcher, 2)
	eq(#AchievementLogic.check(data), 0, "nothing new")
	data.reloads = 1
	local reload = AchievementLogic.check(data)
	eq(reload[1].id, "Reload")
end)

test("Achievements: stars make Ranks, Ranks unlock perks", function()
	eq(AchievementLogic.rank(0), 1)
	eq(AchievementLogic.rank(2), 1)
	eq(AchievementLogic.rank(3), 2)
	local perks = AchievementLogic.perks(10)
	eq(perks.storage, 25 + 50 + 100)
	eq(perks.tripSlots, 2)
	eq(perks.cartridgeSlots, 1)
	eq(#perks.titles, 2, "Explorer and Veteran")
	eq(AchievementLogic.nextPerk(10).rank, 12)
	eq(AchievementLogic.nextPerk(99), nil)
	eq(AchievementLogic.stars({ Hatcher = 2, Reload = 1, Unknown = 5 }), 3)
end)

test("Achievements: every title exists and goals grow", function()
	for _, achievement in AchievementConfig.list do
		eq(#achievement.goals, #achievement.gems, achievement.id .. " gems per tier")
		for i = 2, #achievement.goals do
			assert(achievement.goals[i] > achievement.goals[i - 1], achievement.id .. " goals grow")
		end
		for _, titleId in achievement.titles or {} do
			assert(Cosmetics.titleById[titleId], "missing title " .. titleId)
		end
	end
	for _, perk in AchievementConfig.rankPerks do
		if perk.title then
			assert(Cosmetics.titleById[perk.title], "missing title " .. perk.title)
		end
	end
end)

test("Index: hatching and trading mark species x variant once", function()
	local data = awardData()
	local gen = idGen()
	Inventory.add(data, { s = "Kitty", v = "Normal", z = "Normal" }, gen)
	Inventory.add(data, { s = "Kitty", v = "Normal", z = "Big" }, gen)
	Inventory.add(data, { s = "Kitty", v = "Golden", z = "Normal" }, gen)
	eq(AchievementLogic.discovered(data.index), 2)
	eq(AchievementLogic.value(data, "discovered"), 2)

	local a = { pets = {}, equipped = {}, capacity = 50, index = {} }
	local b = { pets = {}, equipped = {}, capacity = 50, index = {} }
	local id = Inventory.add(a, { s = "Bear", v = "Lava", z = "Normal" }, gen)
	local session = TradeLogic.new(1, 2, 0)
	session.offers[1] = { id }
	TradeLogic.execute(session, a, b)
	assert(b.index["Bear|Lava"], "receiver discovers the traded creature")
end)

test("Rank perks add trip and cartridge slots", function()
	local data = awardData()
	eq(Expedition.slotsFor(data), 2)
	-- 24 stars = Rank 9: +2 trip slots (Rank 3 and 8), +1 cartridge slot (Rank 6)
	data.achievements = { Hatcher = 4, Coins = 4, Breaker = 3, Golden = 3, Pixel = 3, BigCatch = 3, Guardian = 3, Fusion = 1 }
	eq(AchievementLogic.stars(data.achievements), 24)
	eq(Expedition.slotsFor(data), 4)
	local _, perks = AchievementLogic.forData(data)
	eq(Gear.slots(0, perks.cartridgeSlots), 3)
end)

-- Stickers and gadgets --------------------------------------------------------------------------------------

test("Stickers: Star boosts its creature, team stickers add up", function()
	local plain = { s = "Bear", v = "Normal", z = "Normal" }
	local starred = { s = "Bear", v = "Normal", z = "Normal", st = "Sticker_Star_1" }
	near(PetMath.basePower(starred), PetMath.basePower(plain) * 1.25, 1e-9, "star")
	near(PetMath.basePower({ s = "Bear", v = "Normal", z = "Normal", st = "Sticker_Star_3" }), PetMath.basePower(plain) * 1.5, 1e-9, "holo star")

	local pets = {
		a = { s = "Cubby", v = "Normal", z = "Normal", st = "Sticker_Coin_1" },
		b = { s = "Cubby", v = "Normal", z = "Normal", st = "Sticker_Coin_3" },
		c = { s = "Cubby", v = "Normal", z = "Normal", st = "Sticker_Bolt_2" },
		d = { s = "Cubby", v = "Normal", z = "Normal", st = "Sticker_Pixel_1" },
		e = { s = "Cubby", v = "Normal", z = "Normal", st = "Sticker_Clover_1" },
	}
	local effects = Effects.collect(pets, { "a", "b", "c", "d", "e" })
	near(Effects.get(effects, "Coins"), 1 + 0.05 + 0.1, 1e-9, "coins add up")
	near(Effects.get(effects, "ComboHold"), 0.5, 1e-9, "bolt is additive")
	near(effects.variantChance.Pixel, 1.1, 1e-9, "pixel chance")
	near(Effects.get(effects, "Luck"), 1.05, 1e-9, "luck")
	local benched = Effects.collect(pets, {})
	eq(Effects.get(benched, "Coins"), 1, "only the equipped team counts")
end)

test("Stickers: 3 merge into Shiny then Holo; stickered creatures aren't fused", function()
	local items = { Sticker_Gem_1 = 3, Sticker_Gem_3 = 4 }
	eq(Bag.merge(items, "Sticker_Gem_1"), "Sticker_Gem_2")
	eq(Bag.merge(items, "Sticker_Gem_3"), nil, "Holo is the top")
	eq(Items.byId.Sticker_Gem_2.name, "Shiny Gem Sticker")
	eq(Items.byId.Sticker_Gem_3.name, "Holo Gem Sticker")

	local holder = { pets = {}, equipped = {} }
	local gen = idGen()
	for _ = 1, 5 do
		Inventory.add(holder, { s = "Kitty", v = "Normal", z = "Normal" }, gen)
	end
	holder.pets.p1.st = "Sticker_Star_1"
	eq(#Inventory.fusionMaterial(holder, "Kitty", "Normal"), 4)
end)

test("Loot: stickers and gadgets drop from Bigs and guardians, Holo is rare", function()
	local rng = makeRng(21)
	local stickers, gadgets, tiers = 0, 0, { 0, 0, 0 }
	for _ = 1, 20000 do
		for _, id in Loot.rollAll("Big", 2, rng) do
			local item = Items.byId[id]
			if item.kind == "Sticker" then
				stickers += 1
			elseif item.kind == "Gadget" then
				gadgets += 1
			end
		end
		local sticker = Loot.randomSticker(3, rng)
		local tier = Items.byId[sticker].tier
		tiers[tier] += 1
	end
	near(stickers / 20000, 0.05, 0.01, "Big stickers")
	near(gadgets / 20000, 0.15, 0.015, "Big gadgets")
	assert(tiers[1] > tiers[2] and tiers[2] > tiers[3] and tiers[3] > 0, "tier weights")
	for _ = 1, 500 do
		eq(Items.byId[Loot.randomGadget(rng)].kind, "Gadget")
	end
end)

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
	-- Stickers add two parts on the back
	local plain = PetModel.build({ s = "Kitty", v = "Normal", z = "Normal" })
	local stickered = PetModel.build({ s = "Kitty", v = "Normal", z = "Normal", st = "Sticker_Star_3" })
	eq(#stickered.parts, #plain.parts + 2)
	assert(stickered.model:FindFirstChild("Sticker"), "sticker part")
end)

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	process.exit(1)
end
