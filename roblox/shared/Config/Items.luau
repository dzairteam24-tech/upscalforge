--!strict
-- Items the player can hold. Earned in game only, never sold.
--   Elixir     timed boost. 3 of a tier merge into the next tier; the Mixer makes double elixirs.
--   Cartridge  equipped in a slot for a permanent bonus. 3 of a tier merge into the next tier.
--              3 cartridges of the same set give a set bonus.
--   KeyHalf    2 halves make a Key.
--   Key        opens something (treasure, golden eggs, an early guardian).
--   Sticker    stuck on one creature (it shows on its back). Normal -> Shiny -> Holo, 3 merge into 1.
--   Gadget     used once in a zone: bomb, coin rain, totems, time skip.

export type BoostStat = string -- "Coins" | "Power" | "Luck" | "Speed" | "Pixel" | "Gem" | "Hunter"

export type GearEffect = { stat: string, value: number }

-- Sticker effect. "pet" applies to the creature it's on; "team" adds up over the equipped team.
export type StickerEffect = { stat: string, value: number, scope: string, additive: boolean? }

export type Item = {
	id: string,
	name: string,
	kind: string, -- "Elixir" | "Cartridge" | "KeyHalf" | "Key" | "Sticker" | "Gadget"
	tier: number,
	family: string,
	boosts: { { stat: BoostStat, mult: number } }, -- elixirs
	duration: number, -- elixirs, seconds
	gear: { GearEffect }, -- cartridges
	set: string?, -- cartridges
	mergeInto: string?,
	mergeCost: number,
	color: Color3,
	description: string,
	icon: string?, -- stickers and gadgets
	sticker: StickerEffect?,
}

local ROMAN = { "I", "II", "III", "IV", "V" }
local MAX_TIER = #ROMAN

local byId: { [string]: Item } = {}
local list: { Item } = {}

local function add(item: Item)
	byId[item.id] = item
	table.insert(list, item)
end

---------------------------------------------------------------------------------------------------------------
-- Elixirs

type ElixirFamily = {
	id: string,
	label: string,
	stats: { BoostStat },
	mults: { { number } }, -- per stat, per tier
	duration: number,
	color: Color3,
}

local ELIXIRS: { ElixirFamily } = {
	{ id = "Coins", label = "Coin Elixir", stats = { "Coins" }, mults = { { 1.5, 1.75, 2, 2.5, 3 } }, duration = 600, color = Color3.fromRGB(245, 197, 66) },
	{ id = "Power", label = "Power Elixir", stats = { "Power" }, mults = { { 1.5, 1.75, 2, 2.5, 3 } }, duration = 600, color = Color3.fromRGB(229, 83, 75) },
	{ id = "Luck", label = "Luck Elixir", stats = { "Luck" }, mults = { { 1.5, 1.75, 2, 2.5, 3 } }, duration = 600, color = Color3.fromRGB(80, 200, 120) },
	{ id = "Speed", label = "Speed Elixir", stats = { "Speed" }, mults = { { 1.25, 1.4, 1.55, 1.75, 2 } }, duration = 600, color = Color3.fromRGB(91, 184, 245) },
	{ id = "Pixel", label = "Pixel Elixir", stats = { "Pixel" }, mults = { { 2, 2.75, 3.5, 4.25, 5 } }, duration = 300, color = Color3.fromRGB(142, 91, 217) },
	{ id = "Gem", label = "Gem Elixir", stats = { "Gem" }, mults = { { 2, 2.5, 3, 3.5, 4 } }, duration = 600, color = Color3.fromRGB(120, 220, 255) },
	{ id = "Hunter", label = "Hunter Elixir", stats = { "Hunter" }, mults = { { 2, 2.5, 3, 3.5, 4 } }, duration = 600, color = Color3.fromRGB(240, 138, 45) },
}

local MIXES = {
	{ id = "Fortune", label = "Fortune Elixir", a = "Coins", b = "Luck", color = Color3.fromRGB(200, 220, 90) },
	{ id = "Rush", label = "Rush Elixir", a = "Power", b = "Speed", color = Color3.fromRGB(240, 120, 200) },
	{ id = "Rainbow", label = "Rainbow Elixir", a = "Luck", b = "Pixel", color = Color3.fromRGB(255, 140, 220) },
}

local function elixirId(family: string, tier: number): string
	return ("Elixir_%s_%d"):format(family, tier)
end

local elixirFamilies: { [string]: ElixirFamily } = {}

local function registerElixir(family: ElixirFamily)
	elixirFamilies[family.id] = family
	for tier = 1, MAX_TIER do
		local boosts = {}
		local parts = {}
		for i, stat in family.stats do
			local mult = family.mults[i][tier]
			table.insert(boosts, { stat = stat, mult = mult })
			table.insert(parts, ("x%g %s"):format(mult, stat))
		end
		add({
			id = elixirId(family.id, tier),
			name = ("%s %s"):format(family.label, ROMAN[tier]),
			kind = "Elixir",
			tier = tier,
			family = family.id,
			boosts = boosts,
			duration = family.duration,
			gear = {},
			mergeInto = if tier < MAX_TIER then elixirId(family.id, tier + 1) else nil,
			mergeCost = 3,
			color = family.color,
			description = ("%s for %d min"):format(table.concat(parts, " + "), family.duration // 60),
		})
	end
end

for _, family in ELIXIRS do
	registerElixir(family)
end
for _, mix in MIXES do
	local a, b = elixirFamilies[mix.a], elixirFamilies[mix.b]
	registerElixir({
		id = mix.id,
		label = mix.label,
		stats = { a.stats[1], b.stats[1] },
		mults = { a.mults[1], b.mults[1] },
		duration = math.min(a.duration, b.duration),
		color = mix.color,
	})
end

---------------------------------------------------------------------------------------------------------------
-- Cartridges (the "books"): 8-bit game cartridges with a permanent bonus while equipped

type CartridgeFamily = {
	id: string,
	label: string,
	stat: string,
	values: { number }, -- one per tier (rare cartridges have a single tier)
	set: string?,
	text: string, -- "%s" is replaced with the formatted value
	percent: boolean?, -- format the value as a percentage bonus (1.25 -> +25%)
	color: Color3,
	rare: boolean?,
}

local CARTRIDGES: { CartridgeFamily } = {
	-- Rich set
	{ id = "Coins", label = "Coins", stat = "Coins", values = { 1.1, 1.25, 1.5, 1.75, 2 }, set = "Rich", text = "%s coins", percent = true, color = Color3.fromRGB(245, 197, 66) },
	{ id = "Jackpot", label = "Jackpot", stat = "Jackpot", values = { 0.01, 0.02, 0.03, 0.04, 0.05 }, set = "Rich", text = "+%s jackpot chance", color = Color3.fromRGB(255, 90, 200) },
	{ id = "ChestBreaker", label = "Chest Breaker", stat = "Chest", values = { 1.25, 1.5, 2, 2.5, 3 }, set = "Rich", text = "%s from chests, safes and vaults", percent = true, color = Color3.fromRGB(161, 107, 59) },
	-- Hatcher set
	{ id = "Lucky", label = "Lucky", stat = "Luck", values = { 1.1, 1.25, 1.5, 1.75, 2 }, set = "Hatcher", text = "%s hatch luck", percent = true, color = Color3.fromRGB(80, 200, 120) },
	-- Fighter set
	{ id = "Power", label = "Power", stat = "Power", values = { 1.1, 1.25, 1.5, 1.75, 2 }, set = "Fighter", text = "%s team power", percent = true, color = Color3.fromRGB(229, 83, 75) },
	{ id = "Combo", label = "Combo", stat = "ComboHold", values = { 1, 2, 3, 4, 5 }, set = "Fighter", text = "combo lasts +%ss", color = Color3.fromRGB(255, 140, 60) },
	{ id = "Speed", label = "Speed", stat = "Speed", values = { 1.1, 1.2, 1.3, 1.4, 1.5 }, set = "Fighter", text = "%s walk speed", percent = true, color = Color3.fromRGB(91, 184, 245) },
	-- Idle set
	{ id = "Offline", label = "Offline", stat = "Offline", values = { 1.2, 1.5, 2, 2.5, 3 }, set = "Idle", text = "%s offline earnings", percent = true, color = Color3.fromRGB(150, 160, 230) },
	{ id = "Gems", label = "Gems", stat = "Gem", values = { 1.1, 1.25, 1.5, 1.75, 2 }, set = "Idle", text = "%s gem drops", percent = true, color = Color3.fromRGB(120, 220, 255) },
	{ id = "Tap", label = "Tap", stat = "Tap", values = { 1.5, 2, 3, 4, 5 }, set = "Idle", text = "%s tap power", percent = true, color = Color3.fromRGB(240, 240, 240) },
	-- Rare (single tier, can't be merged)
	{ id = "GoldenTouch", label = "Golden Touch", stat = "GoldenSources", values = { 0.01 }, text = "%s of sources turn gold (x10)", color = Color3.fromRGB(255, 215, 80), rare = true },
	{ id = "BigHunter", label = "Big Hunter", stat = "BigSpawn", values = { 2 }, text = "Big appears x%s more often", color = Color3.fromRGB(240, 138, 45), rare = true },
	{ id = "PixelSeeker", label = "Pixel Seeker", stat = "Pixel", values = { 2 }, set = "Hatcher", text = "Pixel chance x%s", color = Color3.fromRGB(142, 91, 217), rare = true },
	{ id = "AutoTap", label = "Auto Tap", stat = "AutoTap", values = { 1 }, text = "you tap by yourself, even in Auto mode", color = Color3.fromRGB(200, 200, 210), rare = true },
	{ id = "DoubleHatch", label = "Double Hatch", stat = "EggExtraChance", values = { 0.1 }, set = "Hatcher", text = "%s chance an egg gives 2", color = Color3.fromRGB(180, 255, 140), rare = true },
}

-- Set bonuses: equip all three cartridges of a set.
export type SetDef = { label: string, members: { string }, text: string }

local SETS: { [string]: SetDef } = {
	Rich = { label = "Rich", members = { "Coins", "Jackpot", "ChestBreaker" }, text = "All coins +25%" },
	Hatcher = { label = "Hatcher", members = { "Lucky", "PixelSeeker", "DoubleHatch" }, text = "Hatch twice as fast" },
	Fighter = { label = "Fighter", members = { "Power", "Combo", "Speed" }, text = "Every 20s: power x2 for 5s" },
	Idle = { label = "Idle", members = { "Offline", "Gems", "Tap" }, text = "+4 hours of offline earnings" },
}

local function cartridgeId(family: string, tier: number): string
	return ("Cart_%s_%d"):format(family, tier)
end

local function formatValue(family: CartridgeFamily, value: number): string
	if family.percent then
		return ("+%d%%"):format(math.floor((value - 1) * 100 + 0.5))
	elseif value < 1 then
		return ("%g%%"):format(value * 100)
	end
	return ("%g"):format(value)
end

local cartridgeFamilies: { [string]: CartridgeFamily } = {}
for _, family in CARTRIDGES do
	cartridgeFamilies[family.id] = family
	for tier, value in family.values do
		local multi = #family.values > 1
		add({
			id = cartridgeId(family.id, tier),
			name = if multi then ("%s Card %s"):format(family.label, ROMAN[tier]) else family.label .. " Card",
			kind = "Cartridge",
			tier = tier,
			family = family.id,
			boosts = {},
			duration = 0,
			gear = { { stat = family.stat, value = value } },
			set = family.set,
			mergeInto = if tier < #family.values then cartridgeId(family.id, tier + 1) else nil,
			mergeCost = 3,
			color = family.color,
			description = (family.text:format(formatValue(family, value))):gsub("^%l", string.upper),
		})
	end
end

---------------------------------------------------------------------------------------------------------------
-- Keys

local KEYS = {
	{
		id = "Zone",
		label = "Zone Key",
		color = Color3.fromRGB(91, 184, 245),
		text = "Opens the treasure vault of the zone you're in: 5 vaults of coins and 2 elixirs",
	},
	{
		id = "Rift",
		label = "Rift Key",
		color = Color3.fromRGB(185, 140, 255),
		text = "Opens a Pixel Rift in the zone you're in for 3 minutes, for everyone there",
	},
	{
		id = "Golden",
		label = "Golden Key",
		color = Color3.fromRGB(255, 205, 60),
		text = "Opens a golden chest: 3 eggs from your zone, all Golden or better",
	},
	{
		id = "Titan",
		label = "Titan Key",
		color = Color3.fromRGB(255, 120, 200),
		text = "Calls the guardian of a restored zone right now, skipping its 4h wait",
	},
}

for _, key in KEYS do
	add({
		id = "Key_" .. key.id,
		name = key.label,
		kind = "Key",
		tier = 1,
		family = key.id,
		boosts = {},
		duration = 0,
		gear = {},
		mergeCost = 0,
		color = key.color,
		description = key.text,
	})
	add({
		id = "KeyHalf_" .. key.id,
		name = key.label .. " (half)",
		kind = "KeyHalf",
		tier = 1,
		family = key.id,
		boosts = {},
		duration = 0,
		gear = {},
		mergeInto = "Key_" .. key.id,
		mergeCost = 2,
		color = key.color,
		description = "Join 2 halves to make a " .. key.label,
	})
end

---------------------------------------------------------------------------------------------------------------
-- Stickers: one per creature, visible on its back. Team stickers add up over the equipped team.

type StickerFamily = {
	id: string,
	label: string,
	icon: string,
	stat: string,
	scope: string,
	additive: boolean?,
	values: { number }, -- Normal, Shiny, Holo
	text: string,
	percent: boolean?,
	color: Color3,
}

local STICKER_TIERS = { "", "Shiny ", "Holo " }

local STICKERS: { StickerFamily } = {
	{ id = "Star", label = "Star", icon = "⭐", stat = "Power", scope = "pet", values = { 1.25, 1.375, 1.5 }, text = "this creature's power %s", percent = true, color = Color3.fromRGB(255, 215, 80) },
	{ id = "Bolt", label = "Bolt", icon = "⚡", stat = "ComboHold", scope = "team", additive = true, values = { 0.3, 0.5, 0.7 }, text = "team combo lasts +%ss", color = Color3.fromRGB(255, 160, 60) },
	{ id = "Clover", label = "Clover", icon = "🍀", stat = "Luck", scope = "team", values = { 1.05, 1.075, 1.1 }, text = "team hatch luck %s", percent = true, color = Color3.fromRGB(80, 200, 120) },
	{ id = "Coin", label = "Coin", icon = "🪙", stat = "Coins", scope = "team", values = { 1.05, 1.075, 1.1 }, text = "team coins %s", percent = true, color = Color3.fromRGB(245, 197, 66) },
	{ id = "Gem", label = "Gem", icon = "💎", stat = "GemMult", scope = "team", values = { 1.1, 1.15, 1.2 }, text = "team gem drops %s", percent = true, color = Color3.fromRGB(120, 220, 255) },
	{ id = "Pixel", label = "Pixel", icon = "🟪", stat = "PixelChance", scope = "team", values = { 1.1, 1.15, 1.2 }, text = "Pixel hatch chance %s", percent = true, color = Color3.fromRGB(142, 91, 217) },
	{ id = "Wings", label = "Wings", icon = "🪽", stat = "Speed", scope = "team", values = { 1.05, 1.075, 1.1 }, text = "walk speed %s", percent = true, color = Color3.fromRGB(230, 240, 255) },
}

local function stickerId(family: string, tier: number): string
	return ("Sticker_%s_%d"):format(family, tier)
end

local stickerFamilies: { [string]: StickerFamily } = {}
for _, family in STICKERS do
	stickerFamilies[family.id] = family
	for tier, value in family.values do
		local shown = if family.percent
			then ("+%g%%"):format(math.floor((value - 1) * 1000 + 0.5) / 10)
			else ("%g"):format(value)
		add({
			id = stickerId(family.id, tier),
			name = ("%s%s Sticker"):format(STICKER_TIERS[tier], family.label),
			kind = "Sticker",
			tier = tier,
			family = family.id,
			boosts = {},
			duration = 0,
			gear = {},
			mergeInto = if tier < #family.values then stickerId(family.id, tier + 1) else nil,
			mergeCost = 3,
			color = family.color,
			description = (family.text:format(shown)):gsub("^%l", string.upper),
			icon = family.icon,
			sticker = { stat = family.stat, value = value, scope = family.scope, additive = family.additive },
		})
	end
end

---------------------------------------------------------------------------------------------------------------
-- Gadgets: one use, in a zone

local GADGETS = {
	{ id = "Bomb", label = "Pixel Bomb", icon = "💣", color = Color3.fromRGB(229, 83, 75), text = "Breaks every coin source around you" },
	{ id = "RainCloud", label = "Rain Cloud", icon = "🌧️", color = Color3.fromRGB(150, 190, 240), text = "Rains coins on you for 20 seconds" },
	{ id = "CoinTotem", label = "Coin Totem", icon = "🗿", color = Color3.fromRGB(245, 197, 66), text = "Coins +50% for everyone in this zone for 5 minutes" },
	{ id = "LuckTotem", label = "Luck Totem", icon = "🍀", color = Color3.fromRGB(80, 200, 120), text = "Hatch luck +50% for everyone in this zone for 5 minutes" },
	{ id = "TimeSkip", label = "Time Skip", icon = "⏰", color = Color3.fromRGB(190, 160, 255), text = "Every broken source in this zone comes back now" },
}

for _, gadget in GADGETS do
	add({
		id = "Gadget_" .. gadget.id,
		name = gadget.label,
		kind = "Gadget",
		tier = 1,
		family = gadget.id,
		boosts = {},
		duration = 0,
		gear = {},
		mergeCost = 0,
		color = gadget.color,
		description = gadget.text,
		icon = gadget.icon,
	})
end

---------------------------------------------------------------------------------------------------------------

local Items = {
	list = list,
	byId = byId,
	MAX_TIER = MAX_TIER,
	BOOST_CAP_SECONDS = 4 * 3600,
	-- Most keys opened in one tap (Golden: 3 eggs each, so fewer)
	BULK_OPEN = { Key_Zone = 25, Key_Golden = 10 } :: { [string]: number },
	cartridgeFamilies = CARTRIDGES,
	sets = SETS,
	ROMAN = ROMAN,
	stickerFamilies = STICKERS,
	gadgets = GADGETS,
}

function Items.stickerId(family: string, tier: number): string
	return stickerId(family, tier)
end

function Items.elixirId(family: string, tier: number): string
	return elixirId(family, tier)
end

function Items.cartridgeId(family: string, tier: number): string
	return cartridgeId(family, tier)
end

function Items.cartridgeFamily(id: string): CartridgeFamily?
	return cartridgeFamilies[id]
end

-- What 'Merge' turns this item into, or nil.
function Items.nextTier(id: string): string?
	local item = byId[id]
	return if item then item.mergeInto else nil
end

-- Mixer result for two elixir ids (order doesn't matter), or nil.
function Items.mixResult(a: string, b: string): string?
	local ia, ib = byId[a], byId[b]
	if not ia or not ib or ia.kind ~= "Elixir" or ib.kind ~= "Elixir" or ia.tier ~= ib.tier then
		return nil
	end
	for _, mix in MIXES do
		if (ia.family == mix.a and ib.family == mix.b) or (ia.family == mix.b and ib.family == mix.a) then
			return elixirId(mix.id, ia.tier)
		end
	end
	return nil
end

return Items
