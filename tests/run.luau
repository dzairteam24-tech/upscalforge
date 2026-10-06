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
	eq(Format.abbrev(100000), "100K", "whole-number zeros stay")
	eq(Format.abbrev(150000), "150K")
	eq(Format.abbrev(250000000), "250M")
	eq(Format.abbrev(10000), "10K")
	eq(Format.abbrev(20000), "20K")
	eq(Format.abbrev(1280000), "1.28M")
end)

test("Format.chance", function()
	eq(Format.chance(0.6), "60%")
	eq(Format.chance(0.09), "9%")
	eq(Format.chance(1 / 50000), "1 in 50K")
end)

-- Config ---------------------------------------------------------------------------------------------------

test("World 1 has 10 zones + hub and 50 species (with 10 Legendaries)", function()
	eq(#World1.zones, 11, "zones")
	eq(#World1.speciesOrder, 50, "species")
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
	eq(PetMath.basePower({ s = "Uni", v = "Normal", z = "Big" }), World1.species.Uni.power * 3 * 2)
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
	-- Cubby Lava 4 x4 = 16, Titan Glowworm (no element bonus)
	eq((PetMath.teamPower(pets, { "a", "g" }, "Ice", effects)), 16 + World1.species.Glowworm.power * 10)
end)

test("Same skill doesn't stack: two Titan Bears give x2, not x4", function()
	local pets = {
		a = { s = "Bear", v = "Normal", z = "Titan" },
		b = { s = "Bear", v = "Normal", z = "Titan" },
	}
	local effects = Effects.collect(pets, { "a", "b" })
	eq(Effects.get(effects, "TeamPower"), 2)
	local titanBear = World1.species.Bear.power * 10
	eq((PetMath.teamPower(pets, { "a", "b" }, "Neutral", effects)), (titanBear + titanBear) * 2)
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
		p = { s = "Phoenix", v = "Normal", z = "Titan" },
		c = { s = "Cubby", v = "Normal", z = "Normal" },
	}
	local effects = Effects.collect(pets, { "p", "c" })
	eq((PetMath.teamPower(pets, { "p", "c" }, "Neutral", effects)), World1.species.Phoenix.power * 10 * 2)
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
	eq(kinds.Key, 4, "keys (Zone, Rift, Golden, Titan)")
	eq(kinds.KeyHalf, 4, "halves")
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

test("Gear: loadouts swap cards and report missing ones", function()
	local items: { [string]: number } = { Cart_Lucky_2 = 1 }
	local equipped = { "Cart_Coins_2", "Cart_Jackpot_3" }
	local missing = Gear.applyLoadout(items, equipped, { "Cart_Lucky_2", "Cart_Coins_2", "Cart_Combo_4" }, 2)
	eq(#equipped, 2, "two slots")
	eq(equipped[1], "Cart_Lucky_2")
	eq(equipped[2], "Cart_Coins_2")
	eq(items.Cart_Jackpot_3, 1, "old card back in the bag")
	eq(items.Cart_Coins_2 or 0, 0, "re-equipped card left the bag")
	eq(items.Cart_Lucky_2 or 0, 0, "lucky equipped")
	eq(#missing, 1, "combo didn't fit or wasn't there")
	eq(missing[1], "Cart_Combo_4")
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

-- Lucky Spin, tickets, rides --------------------------------------------------------------------------------

local Wheel = R(Shared.Logic.Wheel)
local WheelConfig = R(Shared.Config.Wheel)

test("Lucky Spin: chances add up to 100% and rolls follow them", function()
	local total = 0
	for index in WheelConfig.slices do
		total += Wheel.chance(index)
	end
	near(total, 1, 1e-9, "chances")
	local rng = makeRng(8)
	local counts = {}
	local n = 50000
	for _ = 1, n do
		local index = Wheel.spin(rng)
		counts[index] = (counts[index] or 0) + 1
	end
	for index in WheelConfig.slices do
		near((counts[index] or 0) / n, Wheel.chance(index), 0.01, WheelConfig.slices[index].id)
	end
	eq(Wheel.freeReady(10, 10), false)
	eq(Wheel.freeReady(9, 10), true)
	assert(Cosmetics.rideById[WheelConfig.JACKPOT_RIDE], "jackpot ride exists")
end)

test("Tickets come from trips and quests; rides come from Rank and the pass", function()
	local trip = { kind = "Long", pets = {}, started = 0, ends = 0, power = 1, element = true }
	local reward = Expedition.rewards(trip, 1, makeRng(2))
	eq(reward.tickets, 12, "8 tickets x1.5 same element")
	assert((Progression.DAILY_QUEST_REWARD.tickets or 0) > 0, "daily quests give tickets")
	local perks = AchievementLogic.perks(7)
	eq(perks.rides[1], "Skateboard")
	for _, perk in AchievementConfig.rankPerks do
		if perk.ride then
			assert(Cosmetics.rideById[perk.ride], "missing ride " .. perk.ride)
		end
	end
	for level = 1, Progression.PASS_LEVELS do
		local premium = Progression.passReward(level, true)
		if premium and premium.ride then
			assert(Cosmetics.rideById[premium.ride], "missing pass ride " .. premium.ride)
		end
	end
end)

-- Monetization rules ----------------------------------------------------------------------------------------

local Products = R(Shared.Config.Products)

test("Robux never buys eggs, luck, creatures or random prizes", function()
	local forbiddenRewards = { Spin = true, Elixir = true } -- random prizes / elixirs include luck
	for _, product in Products.devProducts do
		if product.adOnly then
			assert(Products.adByKey[product.key], "ad product without an ad reward: " .. product.key)
			continue
		end
		if product.boost then
			assert(product.boost.stat ~= "Luck" and product.boost.stat ~= "Pixel", "luck sold: " .. product.key)
		end
		assert(not (product.reward and forbiddenRewards[product.reward]), "random or luck reward sold: " .. product.key)
		assert(product.price > 0, "missing display price: " .. product.key)
	end
	for _, reward in Products.adRewards do
		local product = Products.productByKey[reward.key]
		assert(product and product.adOnly, "ad reward needs an adOnly product: " .. reward.key)
	end
	-- Every reward that needs a service and has a Robux version also has a video version
	local adHandlers = {}
	for _, reward in Products.adRewards do
		if reward.reward then
			adHandlers[reward.reward] = true
		end
	end
	for _, key in { "TripSkip", "TripDouble", "QuestSwap" } do
		assert(adHandlers[key], "no video version for " .. key)
		assert(Products.productByKey[key].reward == key, "no Robux version for " .. key)
	end
	-- The streak save leads to Luck elixirs (day 7), so it is ad-only
	assert(adHandlers.StreakSave, "no video version for StreakSave")
	eq(Products.productByKey.StreakSave, nil, "no Robux streak save")
end)

test("A trip Robux helped with brings back coins and gems only", function()
	local trip = { kind = Expeditions.list[#Expeditions.list].id, pets = {}, started = 0, ends = 0, power = 100, element = false }
	local free = Expedition.rewards(trip, 10, function() return 0 end)
	trip.paid = true
	local paid = Expedition.rewards(trip, 10, function() return 0 end)
	eq(paid.coins, free.coins)
	eq(paid.gems, free.gems)
	eq(paid.tickets, 0)
	eq(#paid.items, 0)
	assert(#free.items > 0, "a free trip brings items")
end)

test("Trip slots from the pass stack with Rank and Reloads", function()
	local data = awardData()
	eq(Expedition.slotsFor(data), 2)
	eq(Expedition.slotsFor(data, Products.PASS_TRIP_SLOTS), 3)
	data.expeditions = { {}, {}, {} } :: any
	eq((Expedition.validate(data, "Short", { "x", "y", "z" }, 0)), false, "full without extras")
end)

-- Review fixes: unlocks and pity -----------------------------------------------------------------------------

local UnlockLogic = R(Shared.Logic.Unlocks)
local Pity = R(Shared.Logic.Pity)
local Hunt = R(Shared.Config.Hunt)

test("Unlocks: systems open by best zone and stay open after a Reload", function()
	local data = { stats = {}, unlockedZones = { ["0"] = true, ["1"] = true } }
	eq(UnlockLogic.has(data, "Trips"), false)
	eq(UnlockLogic.has(data, "Daily"), true, "features without an unlock are always open")
	data.unlockedZones["3"] = true
	eq(UnlockLogic.has(data, "Trips"), true, "zone 3 is past zone 2")
	eq(UnlockLogic.has(data, "Cartridges"), true)
	eq(UnlockLogic.has(data, "Stickers"), false)
	-- After a Reload the gates close, but the lifetime best zone keeps systems open
	data.unlockedZones = { ["0"] = true, ["1"] = true }
	data.stats.bestZone = 4
	eq(UnlockLogic.has(data, "Stickers"), true)
	eq(#UnlockLogic.openedAt(3), 3, "Boost Cards, Spin and Clans")
end)

test("Pity: Big is sure on the 10th try, Titan chance grows and is sure on the 100th", function()
	eq(Pity.chance(0.1, 0, Hunt.BIG_PITY, 0), 0.1)
	eq(Pity.chance(0.1, Hunt.BIG_PITY - 1, Hunt.BIG_PITY, 0), 1)
	eq(Pity.left(3, Hunt.BIG_PITY), 7)
	near(Pity.chance(Hunt.GUARDIAN_TAME_CHANCE, 10, Hunt.TITAN_PITY, Hunt.TITAN_PITY_STEP), 0.025, 1e-9)
	eq(Pity.chance(Hunt.GUARDIAN_TAME_CHANCE, Hunt.TITAN_PITY - 1, Hunt.TITAN_PITY, Hunt.TITAN_PITY_STEP), 1)
	-- Simulate: no player ever needs more than 10 Bigs
	local rng = makeRng(4)
	for _ = 1, 2000 do
		local misses = 0
		while rng() >= Pity.chance(0.1, misses, Hunt.BIG_PITY, 0) do
			misses += 1
		end
		assert(misses < Hunt.BIG_PITY, "pity cap")
	end
end)

-- Gem shop -------------------------------------------------------------------------------------------------

local GemShopLogic = R(Shared.Logic.GemShop)
local GemShopConfig = R(Shared.Config.GemShop)

local function shopper(gems: number)
	return { gems = gems, gemShop = { day = -1, deals = {}, storage = 0 }, stats = {}, unlockedZones = { ["0"] = true, ["1"] = true } }
end

test("Gem shop: every offer is a real item or an upgrade, never random", function()
	for _, offer in GemShopConfig.offers do
		if offer.itemId then
			assert(Items.byId[offer.itemId], "unknown item " .. offer.itemId)
		else
			eq(offer.upgrade, "Storage")
		end
		assert(offer.price > 0, offer.id)
	end
end)

test("Gem shop: buying, locked items, and Storage getting dearer", function()
	local holder = shopper(1000)
	eq((GemShopLogic.canBuy(holder, "CoinsCard", false, 10)), false, "Boost Cards open at zone 3")
	assert(GemShopLogic.canBuy(holder, "CoinElixir2", false, 10))
	GemShopLogic.buy(holder, "CoinElixir2", false, 10)
	eq(holder.gems, 1000 - 30)
	eq(GemShopLogic.price(holder, "Storage", false), 200)
	GemShopLogic.buy(holder, "Storage", false, 10)
	eq(holder.gemShop.storage, 1)
	eq(GemShopLogic.price(holder, "Storage", false), 300, "dearer each time")
	eq(GemShopLogic.storageBonus(holder.gemShop), 50)
	holder.gems = 10
	eq((GemShopLogic.canBuy(holder, "LuckElixir2", false, 10)), false, "not enough gems")
end)

test("Gem shop: 3 daily deals, same for everyone, 40% off, once each per day", function()
	local deals = GemShopLogic.deals(20000)
	eq(#deals, GemShopConfig.DEALS_PER_DAY)
	eq(table.concat(deals, ","), table.concat(GemShopLogic.deals(20000), ","), "same every call")
	local seen = {}
	for _, id in deals do
		assert(not seen[id], "deals are different items")
		seen[id] = true
	end
	-- Find a day whose deals include an item that's always open
	local day, id = 20000, nil
	while not id do
		for _, dealId in GemShopLogic.deals(day) do
			if GemShopConfig.byId[dealId].feature == nil then
				id = dealId
			end
		end
		if not id then
			day += 1
		end
	end
	local holder = shopper(1000)
	local full = GemShopLogic.price(holder, id, false)
	eq(GemShopLogic.price(holder, id, true), math.floor(full * 0.6 + 0.5))
	assert(GemShopLogic.canBuy(holder, id, true, day))
	GemShopLogic.buy(holder, id, true, day)
	eq((GemShopLogic.canBuy(holder, id, true, day)), false, "once a day")
	assert(GemShopLogic.canBuy(holder, id, true, day + 1) or not GemShopLogic.isDeal(id, day + 1), "new day resets")
end)

-- Clans ------------------------------------------------------------------------------------------------------

local ClanLogic = R(Shared.Logic.Clans)
local ClanConfig = R(Shared.Config.Clans)

test("Clans: names and tags are checked", function()
	assert(ClanLogic.checkName("Cube Kings"))
	eq((ClanLogic.checkName("ab")), false, "too short")
	eq((ClanLogic.checkName("Bad<Name>")), false, "symbols")
	assert(ClanLogic.checkTag("CUBE"))
	eq((ClanLogic.checkTag("TOOLONG")), false)
	eq((ClanLogic.checkTag("A!")), false)
end)

test("Clans: members, full clans, owner hand-over and empty clans", function()
	local clan = ClanLogic.new("ABC123", "Cube Kings", "ck", 1, "Owner", 1700000000)
	eq(clan.tag, "CK")
	for i = 2, ClanConfig.MAX_MEMBERS do
		assert(ClanLogic.addMember(clan, i, "P" .. i))
	end
	eq((ClanLogic.addMember(clan, 999, "Late")), false, "full")
	clan.members["5"].points = 50
	assert(ClanLogic.removeMember(clan, 1))
	eq(clan.owner, 5, "the member with most points takes over")
	for i = 2, ClanConfig.MAX_MEMBERS do
		ClanLogic.removeMember(clan, i)
	end
	eq(ClanLogic.count(clan), 0)
	local solo = ClanLogic.new("X", "Solo Team", "SO", 7, "Solo", 0)
	eq(ClanLogic.removeMember(solo, 7), false, "empty clan")
end)

test("Clans: weekly points reset on a new week; rewards by rank", function()
	local now = 1700000000
	local clan = ClanLogic.new("ABC", "Cube Kings", "CK", 1, "A", now)
	ClanLogic.addMember(clan, 2, "B")
	ClanLogic.addPoints(clan, { ["1"] = 10, ["2"] = 5, ["99"] = 1000 }, now)
	eq(clan.points, 15, "outsiders don't count")
	ClanLogic.addPoints(clan, { ["1"] = 1 }, now + 7 * 86400)
	eq(clan.points, 1, "new week")
	eq(clan.members["2"].points, 0)
	eq(ClanLogic.week(now + 7 * 86400), ClanLogic.week(now) + 1)
	eq(ClanLogic.pointsFor("Guardian", 2), 100)
	eq(ClanLogic.pointsFor("Coins", 1000), 0)
	eq(ClanLogic.rewardFor(1), 500)
	eq(ClanLogic.rewardFor(3), 300)
	eq(ClanLogic.rewardFor(10), 150)
	eq(ClanLogic.rewardFor(11), 0)
end)

test("Clans: the owner removes one member a day; they can't rejoin that week", function()
	local now = 1700000000
	local clan = ClanLogic.new("ABC", "Cube Kings", "CK", 1, "A", now)
	ClanLogic.addMember(clan, 2, "B")
	ClanLogic.addMember(clan, 3, "C")
	ClanLogic.addPoints(clan, { ["2"] = 40 }, now)
	eq((ClanLogic.kick(clan, 2, 3, now)), false, "only the owner")
	eq((ClanLogic.kick(clan, 1, 1, now)), false, "not yourself")
	assert(ClanLogic.kick(clan, 1, 2, now))
	eq(clan.members["2"], nil)
	eq(clan.points, 40, "points stay")
	eq((ClanLogic.kick(clan, 1, 3, now + 60)), false, "one a day")
	eq((ClanLogic.addMember(clan, 2, "B", now)), false, "can't rejoin this week")
	assert(ClanLogic.kick(clan, 1, 3, now + 86400))
	assert(ClanLogic.addMember(clan, 2, "B", now + 7 * 86400))
end)

test("Live Event: admins, the chat command and caps", function()
	local Live = R(Shared.Logic.LiveEvent)
	eq(Live.isAdmin(5, true, false), true, "owner")
	eq(Live.isAdmin(6, false, false), false)
	eq(Live.isAdmin(6, false, true), true, "Studio")
	local cmd = Live.parse("/live LUCK 3 20")
	eq(cmd.stat, "Luck")
	eq(cmd.mult, 3)
	eq(cmd.minutes, 20)
	eq(Live.parse("/live coins 100").mult, 5, "capped")
	eq(Live.parse("/live gem 2").minutes, 30, "default minutes")
	eq(Live.parse("/live luck 3 999").minutes, 60, "capped minutes")
	eq(Live.parse("/live stop").stop, true)
	eq((Live.parse("/live power 3")), nil)
	eq((Live.parse("/live luck 1")), nil)
	local live = { stat = "Luck", mult = 3, ends = 1000 }
	eq(Live.bonus(live, "Luck", 999), 3)
	eq(Live.bonus(live, "Coins", 999), 1)
	eq(Live.bonus(live, "Luck", 1000), 1, "over")
	eq(Live.bonus(nil, "Luck", 0), 1)
	eq(Live.valid(live), true)
	eq(Live.valid({ stat = "Luck", mult = 50, ends = 1 }), false, "over the cap")
	eq(Live.valid("x"), false)
end)

test("First clears: once per guardian and boss, bonuses last", function()
	local FC = R(Shared.Logic.FirstClear)
	local clears = {}
	eq(FC.mark(clears, FC.guardianKey(3)), true)
	eq(FC.mark(clears, FC.guardianKey(3)), false, "only once")
	FC.mark(clears, FC.guardianKey(10))
	eq(FC.guardians(clears), 2)
	near(FC.coinMult(clears), 1.1, 1e-9)
	eq(FC.luckMult(clears), 1)
	FC.mark(clears, "Boss")
	near(FC.luckMult(clears), 1.1, 1e-9)
	eq(FC.guardians(clears), 2, "the boss isn't a guardian")
end)

test("Fishing: rolls, Perfect luck, timing and the Fish Index", function()
	local Fish = R(Shared.Logic.Fishing)
	local FishCfg = R(Shared.Config.Fishing)
	local total = 0
	for _, rarity in FishCfg.rarities do
		total += rarity.weight
	end
	near(total, 100, 1e-9, "weights add up to 100")
	for _, f in FishCfg.fish do
		assert(FishCfg.raritiesById[f.rarity], f.id)
	end
	eq(Fish.roll(false, function() return 0 end).rarity, "Common")
	eq(Fish.roll(false, function() return 0.999 end).rarity, "Legendary")
	local w, p = Fish.weights(false), Fish.weights(true)
	eq(p.Common, w.Common)
	eq(p.Legendary, w.Legendary * FishCfg.PERFECT_LUCK)
	eq(Fish.isPerfect(Fish.marker(0.5 / FishCfg.MARKER_SPEED)), true, "middle of the bar")
	eq(Fish.isPerfect(Fish.marker(0)), false)
	eq(Fish.inTime(-0.1), false)
	eq(Fish.inTime(1), true)
	eq(Fish.inTime(FishCfg.REEL_WINDOW + FishCfg.LATENCY + 0.1), false)
	assert(Fish.biteDelay(0.5, true) > Fish.biteDelay(0.5, false), "auto is slower")
	local reward = Fish.reward(FishCfg.fishById.Cubefish, 1000, false, function() return 0 end)
	eq(reward.coins, 30000)
	eq(Fish.reward(FishCfg.fishById.Cubefish, 1000, true, function() return 0 end).tickets, 0, "no tickets on auto")
	eq(Fish.perfectPlausible(0.5 / FishCfg.MARKER_SPEED), true)
	eq(Fish.perfectPlausible(0.05), false, "marker far from the green")
	eq(reward.gems, 25)
	assert(reward.elixir)
	local data = { caught = {}, total = 0 }
	local isNew, complete = Fish.record(data, "Minnow")
	eq(isNew, true)
	eq(complete, false)
	eq((Fish.record(data, "Minnow")), false)
	for _, f in FishCfg.fish do
		if f.id ~= "Cubefish" then
			Fish.record(data, f.id)
		end
	end
	local _, done = Fish.record(data, "Cubefish")
	eq(done, true, "index complete")
	eq(Fish.kinds(data), 10)
end)

-- Events -----------------------------------------------------------------------------------------------------

local EventLogic = R(Shared.Logic.Events)
local EventConfig = R(Shared.Config.Events)

test("Events: UTC dates, the running event, tokens, bonus and the shop", function()
	eq(EventConfig.utc(1970, 1, 1), 0)
	eq(EventConfig.utc(2026, 10, 4), 20730 * 86400, "same day as the Battle Pass start")
	local spooky = EventConfig.byId.Spooky26
	eq(EventLogic.active(spooky.starts - 1), nil)
	eq(EventLogic.active(spooky.starts).id, "Spooky26")
	eq(EventLogic.active(spooky.ends), nil, "ends are exclusive")
	eq(EventLogic.active(0, "Snow26").id, "Snow26", "forced for Studio tests")
	eq(EventLogic.bonus(spooky, "Gem"), 2)
	eq(EventLogic.bonus(spooky, "Coins"), 1)
	eq(EventLogic.bonus(nil, "Gem"), 1)
	local rng = makeRng(6)
	eq(EventLogic.tokensFor(spooky, "Vault", rng), 5)
	local piles = 0
	for _ = 1, 10000 do
		piles += EventLogic.tokensFor(spooky, "Pile", rng)
	end
	near(piles / 10000, 0.15, 0.02, "fractional tokens are a chance")

	local state = { tokens = 400, bought = {} }
	assert(EventLogic.canBuy(spooky, state, "Title"))
	EventLogic.buy(spooky, state, "Title")
	eq(state.tokens, 100)
	eq((EventLogic.canBuy(spooky, state, "Title")), false, "once")
	eq((EventLogic.canBuy(spooky, state, "Ride")), false, "not enough")
	for _, event in EventConfig.list do
		assert(event.ends > event.starts, event.id)
		for _, offer in event.shop do
			if offer.title then
				assert(Cosmetics.titleById[offer.title], offer.title)
			elseif offer.trail then
				assert(Cosmetics.trailById[offer.trail], offer.trail)
			elseif offer.ride then
				assert(Cosmetics.rideById[offer.ride], offer.ride)
			else
				assert(offer.itemId and Items.byId[offer.itemId], "event item " .. tostring(offer.itemId))
			end
		end
	end
end)

test("Every creature model builds: 50 species x 6 variants x 3 sizes", function()
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
	eq(built, 50 * 6 * 3)
	-- Stickers add two parts on the back
	local plain = PetModel.build({ s = "Kitty", v = "Normal", z = "Normal" })
	local stickered = PetModel.build({ s = "Kitty", v = "Normal", z = "Normal", st = "Sticker_Star_3" })
	eq(#stickered.parts, #plain.parts + 2)
	assert(stickered.model:FindFirstChild("Sticker"), "sticker part")
end)

test("Every aura and hatch effect is sold once, cosmetic only", function()
	local Cosmetics = R(Shared.Config.Cosmetics)
	local Products = R(Shared.Config.Products)
	local sold: { [string]: number } = {}
	for _, product in Products.devProducts do
		local cosmetic = product.cosmetic
		if cosmetic then
			assert(cosmetic.kind == "aura" or cosmetic.kind == "hatchFx", "kind " .. product.key)
			local known = if cosmetic.kind == "aura" then Cosmetics.auraById[cosmetic.id] else Cosmetics.hatchFxById[cosmetic.id]
			assert(known, "unknown cosmetic " .. product.key)
			assert(not product.boost and not product.reward and not product.adOnly, "cosmetic only " .. product.key)
			local key = cosmetic.kind .. "|" .. cosmetic.id
			sold[key] = (sold[key] or 0) + 1
		end
	end
	for _, aura in Cosmetics.auras do
		eq(sold["aura|" .. aura.id], 1, aura.id)
	end
	for _, fx in Cosmetics.hatchFx do
		eq(sold["hatchFx|" .. fx.id], 1, fx.id)
	end
end)

test("Trade worth: counts rares and warns on lopsided trades", function()
	local titan = { s = "Kitty", v = "Normal", z = "Titan" }
	local pixel = { s = "Kitty", v = "Pixel", z = "Normal" }
	local normal = { s = "Kitty", v = "Normal", z = "Normal" }
	local give = TradeLogic.worth({ titan, pixel })
	eq(give.count, 2)
	eq(give.titans, 1)
	eq(give.rare, 1, "pixel is rare")
	local get = TradeLogic.worth({ normal, normal, normal })
	assert(TradeLogic.lopsided(give, get), "titan for normals is lopsided")
	assert(not TradeLogic.lopsided(get, give), "getting more is fine")
	assert(not TradeLogic.lopsided(TradeLogic.worth({ normal }), TradeLogic.worth({})), "tiny gifts don't warn")
end)

test("Codes: upper case, real items, no creatures", function()
	local Codes = R(Shared.Config.Codes)
	local Items = R(Shared.Config.Items)
	eq(Codes.normalize("  rel ease "), "RELEASE")
	for _, entry in Codes.list do
		eq(entry.code, Codes.normalize(entry.code), "normalized " .. entry.code)
		assert(#entry.code <= Codes.MAX_LENGTH, "length " .. entry.code)
		for _, item in entry.reward.items or {} do
			assert(Items.byId[item.id], "unknown item " .. item.id)
		end
		assert(not entry.reward.freeEggs, "codes don't give eggs " .. entry.code)
	end
end)

test("World Boss: schedule, health and fair rewards", function()
	local Boss = R(Shared.Logic.Boss)
	local BossConfig = R(Shared.Config.Boss)
	-- Every hour at :30
	eq(Boss.nextSpawn(0), 1800)
	eq(Boss.nextSpawn(1799), 1800)
	eq(Boss.nextSpawn(1800), 1800 + 3600, "strictly after")
	eq(Boss.nextSpawn(5000), 5400)
	eq(Boss.health(0), BossConfig.MIN_HEALTH)
	eq(Boss.health(1000), 1000 * BossConfig.HEALTH_SECONDS)
	-- Fighting time is measured against your own power
	eq(Boss.tier(15 * 10, 10), "full")
	eq(Boss.tier(15 * 1e6, 1e6), "full", "strong players need the same time")
	eq(Boss.tier(5 * 10, 10), "small")
	eq(Boss.tier(1, 10), nil)
	eq(Boss.tier(50, 0), "full", "a player with no team who taps still counts")
	local full = Boss.reward("full", 4, true)
	eq(full.gems, BossConfig.GEMS_BASE + 4 * BossConfig.GEMS_PER_ZONE)
	eq(full.tickets, BossConfig.TICKETS)
	assert(Boss.reward("small", 4, true).gems < full.gems, "small is less")
	eq(Boss.reward("full", 4, false).tickets, 0, "escaped gives no tickets")
end)

test("3D models: parts are cloned, scaled, face forward and get their colors", function()
	local roblox = require("@lune/roblox")
	local Instance, Vector3, CFrame, Color3, Enum = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
	local PetModel = R(Shared.PetModel)
	local folder = Instance.new("Folder")
	folder.Name = "CreatureModels"
	-- Like the imported .glb: front is +Z, the body is 2 wide
	local function part(name: string, size: Vector3, position: Vector3)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = CFrame.new(position)
		p.Parent = folder
	end
	part("Kitty__body", Vector3.new(2, 1.9, 2), Vector3.new(10, 1.19, 0))
	part("Kitty__eye", Vector3.new(0.38, 0.48, 0.14), Vector3.new(10.47, 1.29, 1.0))
	part("Kitty__eye", Vector3.new(0.38, 0.48, 0.14), Vector3.new(9.53, 1.29, 1.0))
	part("Kitty__legs", Vector3.new(0.46, 0.54, 0.46), Vector3.new(10.62, 0.27, 0.62))
	PetModel.useModels(folder)
	local built = PetModel.build({ s = "Kitty", v = "Normal", z = "Normal" })
	eq(#built.parts, 4, "cloned every part")
	eq(built.body.Name, "body")
	near(built.body.Size.X, 2.2, 1e-4, "body scaled to the creature size")
	eq(built.body.Color, Color3.fromRGB(245, 166, 91), "normal color from CreatureLooks")
	for i, p in built.parts do
		if p.Name == "eye" then
			assert(built.offsets[i].Position.Z < 0, "eyes face -Z (front)")
		end
	end
	near(built.height, (1.19 + 0.95 - 0) * 1.1, 0.05, "height is the whole model")
	local golden = PetModel.build({ s = "Kitty", v = "Golden", z = "Big" })
	eq(golden.body.Material, Enum.Material.Foil, "golden body")
	assert(golden.body.Size.X > 3.5, "big is bigger")
	-- Species without a model still get the block version
	local blocks = PetModel.build({ s = "Bee", v = "Normal", z = "Normal" })
	eq(blocks.body.Name, "Body")
	PetModel.useModels(nil)
end)

test("Legendary Egg: in the last zone, near-impossible odds that luck can't change", function()
	local egg = World1.eggs[World1.LEGENDARY_EGG]
	eq(egg.zone, 10)
	local total = 0
	for _, chance in egg.chances do
		total += chance
	end
	near(total, 1, 1e-9, "odds add up to 100%")
	local plain = EggRoll.speciesWeights(World1.LEGENDARY_EGG, 1)
	local lucky = EggRoll.speciesWeights(World1.LEGENDARY_EGG, 1000)
	for i, entry in plain do
		near(lucky[i].weight, entry.weight, 1e-12, "luck doesn't change " .. entry.id)
	end
	local legendaries = 0
	for _, speciesId in egg.species do
		local species = World1.species[speciesId]
		if species.legendary then
			legendaries += 1
			assert(species.chance <= 1 / 200000, speciesId .. " is near impossible")
			eq(species.egg, World1.LEGENDARY_EGG)
		end
	end
	eq(legendaries, 10)
	-- Every Legendary beats every creature of the zone its egg stands in, and they get stronger with rarity
	local lastZone = World1.zonesById[egg.zone]
	local strongestThere = 0
	for _, speciesId in lastZone.species do
		strongestThere = math.max(strongestThere, World1.species[speciesId].power)
	end
	local previous = 0
	for _, speciesId in egg.species do
		local species = World1.species[speciesId]
		if species.legendary then
			assert(species.power > strongestThere, speciesId .. " beats the zone's best")
			assert(species.power > previous, speciesId .. " is stronger than the more common Legendary")
			previous = species.power
		end
	end
	-- Zone eggs never give a Legendary
	for _, zone in World1.zones do
		for _, speciesId in zone.species do
			assert(not World1.species[speciesId].legendary, speciesId .. " is not in a zone egg")
		end
	end
end)

test("Daily Bounty: 3 targets from reached zones, same all day, rarer variants count", function()
	local Bounty = R(Shared.Logic.Bounty)
	local a = Bounty.forDay(20000, { 1, 2, 3 }, 42)
	local b = Bounty.forDay(20000, { 1, 2, 3 }, 42)
	eq(#a, 3)
	for i = 1, 3 do
		eq(a[i].species, b[i].species, "same day, same pick")
		eq(a[i].tier, i)
		local species = World1.species[a[i].species]
		assert(species and species.zone <= 3, "only reached zones")
		assert(not species.legendary, "never a Legendary")
	end
	eq(World1.species[Bounty.forDay(20000, { 1 }, 7)[3].species].zone, 1, "a new player only gets zone 1")
	-- Picks vary across days (both kinds of medium and hard bounties show up)
	local goldenMedium, normalMedium = 0, 0
	for day = 20000, 20200 do
		local t = Bounty.forDay(day, { 1, 2, 3, 4 }, 5)
		if t[2].variant == "Golden" then
			goldenMedium += 1
		else
			normalMedium += 1
		end
	end
	assert(goldenMedium > 30 and normalMedium > 30, ("medium mix %d/%d"):format(goldenMedium, normalMedium))
	local target = { tier = 2, species = "Fox", variant = "Golden" }
	assert(Bounty.matches(target, "Fox", "Golden"), "exact")
	assert(Bounty.matches(target, "Fox", "Neon"), "rarer variant counts")
	assert(not Bounty.matches(target, "Fox", "Normal"), "plainer doesn't")
	assert(not Bounty.matches(target, "Owl", "Golden"), "other species doesn't")
end)

test("Journey: steps count their event, max steps use the best value, rewards are real", function()
	local Journey = R(Shared.Logic.Journey)
	local JourneyConfig = R(Shared.Config.Journey)
	local Items = R(Shared.Config.Items)
	local Cosmetics = R(Shared.Config.Cosmetics)
	local state = { step = 1, progress = 0 }
	assert(not Journey.onEvent(state, "Hatch", 5), "wrong event does nothing")
	eq(state.progress, 0)
	assert(not Journey.onEvent(state, "Break", 10))
	assert(Journey.onEvent(state, "Break", 15), "20 breaks done")
	assert(Journey.isDone(state))
	Journey.advance(state, { Zone = 1 })
	eq(state.step, 2)
	Journey.advance(state, { Zone = 4 })
	eq(state.step, 3)
	assert(Journey.isDone(state), "zone step starts done when already past it")
	for _, step in JourneyConfig.steps do
		for _, item in step.reward.items or {} do
			assert(Items.byId[item.id], "unknown item " .. item.id)
		end
		if step.reward.title then
			assert(Cosmetics.titleById[step.reward.title], "unknown title " .. step.reward.title)
		end
	end
	eq(#JourneyConfig.steps, 30)
end)

test("Cube Stack: overlap rule, cheat checks, capped rewards", function()
	local Minigame = R(Shared.Logic.Minigame)
	local MinigameConfig = R(Shared.Config.Minigame)
	local left, width = Minigame.place(100, 50, 120, 50)
	eq(left, 120)
	eq(width, 30, "only the overlap stays")
	local _, missed = Minigame.place(100, 50, 200, 50)
	eq(missed, 0, "a full miss ends the game")
	assert(Minigame.plausible(20, 20 * MinigameConfig.SECONDS_PER_CUBE + 1), "a real game")
	assert(not Minigame.plausible(20, 2), "too fast")
	assert(not Minigame.plausible(MinigameConfig.MAX_SCORE + 1, 1e6), "too high")
	assert(not Minigame.plausible(3.5, 100), "not a whole number")
	local big = Minigame.reward(1000)
	eq(big.gems, MinigameConfig.MAX_GEMS)
	eq(big.tickets, MinigameConfig.MAX_TICKETS)
	eq(Minigame.reward(4).tickets, 0)
end)

test("Power follows the zone's coin scale (same time to break a source in every zone)", function()
	for _, zone in World1.zones do
		if #zone.species == 4 then
			local common = World1.species[zone.species[1]].power
			eq(common, zone.scale, zone.name .. ": common power = zone scale")
			eq(World1.species[zone.species[4]].power, zone.scale * 8, zone.name .. ": the 1% one is 8x")
		end
	end
end)

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	process.exit(1)
end
