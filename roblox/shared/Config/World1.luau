--!strict
-- World 1 (Green Valley): zones, eggs, species and Big/Titan skills. Source: docs/world-1.md.
--
-- Skill effects
--   passive  = always-on modifier. Same `type` from several pets does not stack: the strongest counts.
--   periodic = runs every `every` seconds while the pet is equipped.
-- Passive types handled by Logic/Effects: TeamPower, Coins, Luck, Speed, Pile, Chest, Jackpot, ComboHold,
--   Gem, EggExtra, FreeHatch, DoubleHit, CopyStrongest, ElementBonus, DarkPower, VariantChance, Offline,
--   GoldenSources, InstantRespawn, Magnet, BigSpawn, FusionCost, Restore, RiftCoins.
-- Periodic kinds handled by the server: Strike, Wave, Smash, Area, Boost, Rain, GemRain, EggDrop, ComboAdd,
--   CloneArmy, Drain.

export type Passive = {
	type: string,
	value: number,
	variant: string?,
}

export type Periodic = {
	kind: string,
	every: number,
	count: number?,
	fraction: number?,
	radius: number?,
	damageMult: number?,
	stat: string?,
	mult: number?,
	duration: number?,
	chests: number?,
	amount: number?,
	luck: number?,
	minVariant: string?,
	onlyKind: string?,
}

export type Skill = {
	text: string,
	passive: Passive?,
	periodic: { Periodic }?,
}

export type Species = {
	id: string,
	zone: number,
	chance: number,
	power: number,
	color: Color3,
	top: string,
	face: string,
	big: Skill,
	titan: Skill,
	egg: number, -- the egg it hatches from
	legendary: boolean,
}

export type Egg = {
	id: number, -- zone eggs use the zone's id; special eggs come after the zones
	name: string,
	zone: number, -- where it stands, and the zone the player must unlock
	price: number,
	species: { string },
	chances: { number },
	fixedOdds: boolean, -- luck never changes the species odds (Legendary Egg)
}
export type Zone = {
	id: number,
	name: string,
	element: string,
	grid: Vector2, -- map layout cell (the zones wind along one path, each next to the one before it)
	color: Color3,
	eggPrice: number,
	gateCost: number, -- coins to unlock the zone (0 = open)
	scale: number, -- coin source multiplier
	restoreGoal: number, -- coins collected here to reach 100%
	links: { number },
	species: { string },
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function passive(t: string, value: number, variant: string?): Passive
	return { type = t, value = value, variant = variant }
end

-- Zone 0 is the Hub (spawn town with the shop, trading and machines). It has piles but no egg.
local zones: { Zone } = {
	{
		id = 0,
		name = "Hub",
		element = "Neutral",
		grid = Vector2.new(0, -1),
		color = rgb(176, 190, 210),
		eggPrice = 0,
		gateCost = 0,
		scale = 1,
		restoreGoal = 0,
		links = { 1 },
		species = {},
	},
	{
		id = 1,
		name = "Spawn Meadow",
		element = "Neutral",
		grid = Vector2.new(0, 0),
		color = rgb(123, 201, 111),
		eggPrice = 100,
		gateCost = 0,
		scale = 1,
		restoreGoal = 20000,
		links = { 0, 2 },
		species = { "Cubby", "Kitty", "Bunny", "Bear" },
	},
	{
		id = 2,
		name = "Flower Field",
		element = "Neutral",
		grid = Vector2.new(0, 1),
		color = rgb(243, 166, 200),
		eggPrice = 1000,
		gateCost = 5000,
		scale = 10,
		restoreGoal = 200000,
		links = { 1, 3 },
		species = { "Bee", "Ladybug", "Butterfly", "Uni" },
	},
	{
		id = 3,
		name = "Forest",
		element = "Neutral",
		grid = Vector2.new(1, 1),
		color = rgb(78, 154, 91),
		eggPrice = 2500,
		gateCost = 15000,
		scale = 22,
		restoreGoal = 450000,
		links = { 2, 4 },
		species = { "Fox", "Owl", "Deer", "Sprout" },
	},
	{
		id = 4,
		name = "Beach",
		element = "Neutral",
		grid = Vector2.new(1, 2),
		color = rgb(242, 213, 138),
		eggPrice = 5000,
		gateCost = 50000,
		scale = 50,
		restoreGoal = 1000000,
		links = { 3, 5 },
		species = { "Crab", "Turtle", "Dolphin", "Octopus" },
	},
	{
		id = 5,
		name = "Mushroom Cave",
		element = "Dark",
		grid = Vector2.new(1, 3),
		color = rgb(107, 78, 154),
		eggPrice = 11000,
		gateCost = 110000,
		scale = 110,
		restoreGoal = 2500000,
		links = { 4, 6 },
		species = { "Mushroom", "Bat", "Glowworm", "Shade" },
	},
	{
		id = 6,
		name = "Desert",
		element = "Fire",
		grid = Vector2.new(0, 3),
		color = rgb(232, 181, 98),
		eggPrice = 25000,
		gateCost = 250000,
		scale = 250,
		restoreGoal = 6000000,
		links = { 5, 7 },
		species = { "Camel", "Scorpion", "Cactus", "Sphinx" },
	},
	{
		id = 7,
		name = "Snow Peak",
		element = "Ice",
		grid = Vector2.new(-1, 3),
		color = rgb(221, 239, 252),
		eggPrice = 60000,
		gateCost = 600000,
		scale = 600,
		restoreGoal = 15000000,
		links = { 6, 8 },
		species = { "Penguin", "Seal", "Snowman", "Yeti" },
	},
	{
		id = 8,
		name = "Volcano",
		element = "Fire",
		grid = Vector2.new(-1, 4),
		color = rgb(201, 71, 46),
		eggPrice = 150000,
		gateCost = 1500000,
		scale = 1500,
		restoreGoal = 40000000,
		links = { 7, 9 },
		species = { "Imp", "Salamander", "Golem", "Phoenix" },
	},
	{
		id = 9,
		name = "Frozen Lake",
		element = "Ice",
		grid = Vector2.new(-1, 5),
		color = rgb(159, 216, 242),
		eggPrice = 400000,
		gateCost = 4000000,
		scale = 4000,
		restoreGoal = 100000000,
		links = { 8, 10 },
		species = { "Ice Fox", "Narwhal", "Frost Owl", "Ice Dragon" },
	},
	{
		id = 10,
		name = "Pixel Zone",
		element = "Pixel",
		grid = Vector2.new(0, 5),
		color = rgb(142, 91, 217),
		eggPrice = 1000000,
		gateCost = 10000000,
		scale = 10000,
		restoreGoal = 250000000,
		links = { 9 },
		species = { "Bot", "Byte", "Cursor", "King" },
	},
}

local CHANCES = { 0.6, 0.3, 0.09, 0.01 }

-- Species rows: id, power, color, top, face, big skill, titan skill.
-- Power follows the zone's coin scale (like the coin sources), so every zone feels the same to play and the
-- numbers grow big: 1, 2, 4, 8 x the zone scale (1, 10, 22, 50, 110, 250, 600, 1.5K, 4K, 10K).
-- Order inside each zone matches CHANCES (60% / 30% / 9% / 1%). Legendaries hatch only from the Legendary Egg.
local rows: { { any } } = {
	-- 1. Spawn Meadow
	{
		"Cubby", 1, rgb(91, 184, 245), "none", "round",
		{ text = "Team speed +25%", passive = passive("Speed", 1.25) },
		{
			text = "Hatch luck x3. Every 3 min: 3 free eggs.",
			passive = passive("Luck", 3),
			periodic = { { kind = "EggDrop", every = 180, count = 3, luck = 1 } :: Periodic },
		},
	},
	{
		"Kitty", 2, rgb(245, 166, 91), "cat", "happy",
		{ text = "Coin piles +25%", passive = passive("Pile", 1.25) },
		{
			text = "Jackpot chance x5. Lightning: every 30s breaks 3 sources.",
			passive = passive("Jackpot", 5),
			periodic = { { kind = "Strike", every = 30, count = 3 } :: Periodic },
		},
	},
	{
		"Bunny", 4, rgb(240, 240, 245), "bunny", "round",
		{ text = "Team speed +50%", passive = passive("Speed", 1.5) },
		{
			text = "All coins x2. Every minute: coin rain.",
			passive = passive("Coins", 2),
			periodic = { { kind = "Rain", every = 60, chests = 10 } :: Periodic },
		},
	},
	{
		"Bear", 8, rgb(168, 117, 79), "round", "round",
		{ text = "Chests +50%", passive = passive("Chest", 1.5) },
		{
			text = "Power of all creatures x2. Earthquake: every 20s the team stomps.",
			passive = passive("TeamPower", 2),
			periodic = { { kind = "Area", every = 20, radius = 40, damageMult = 10 } :: Periodic },
		},
	},
	-- 2. Flower Field
	{
		"Bee", 10, rgb(245, 210, 70), "antenna", "round",
		{ text = "Magnet (small)", passive = passive("Magnet", 1.25) },
		{
			text = "10% of sources turn gold (x10). Midas: every 2 min, coins x10 for 20s.",
			passive = passive("GoldenSources", 0.1),
			periodic = { { kind = "Boost", every = 120, stat = "Coins", mult = 10, duration = 20 } :: Periodic },
		},
	},
	{
		"Ladybug", 20, rgb(229, 83, 75), "antenna", "round",
		{ text = "Coin piles +50%", passive = passive("Pile", 1.5) },
		{
			text = "Golden chance x5. Every 2 min: a giant chest worth 50 chests.",
			passive = passive("VariantChance", 5, "Golden"),
			periodic = { { kind = "Rain", every = 120, chests = 50 } :: Periodic },
		},
	},
	{
		"Butterfly", 40, rgb(185, 166, 245), "antenna", "sparkle",
		{ text = "3% gem chance from every source", passive = passive("Gem", 0.03) },
		{
			text = "10% gem chance from every source. Every 2 min: gem rain.",
			passive = passive("Gem", 0.1),
			periodic = { { kind = "GemRain", every = 120, amount = 10 } :: Periodic },
		},
	},
	{
		"Uni", 80, rgb(247, 198, 224), "unihorn", "sparkle",
		{ text = "Hits twice", passive = passive("DoubleHit", 2) },
		{
			text = "Every egg gives 2 creatures. Every 5 min: 5 free eggs with luck x10.",
			passive = passive("EggExtra", 1),
			periodic = { { kind = "EggDrop", every = 300, count = 5, luck = 10 } :: Periodic },
		},
	},
	-- 3. Forest
	{
		"Fox", 22, rgb(235, 120, 60), "cat", "happy",
		{ text = "Team speed +50%", passive = passive("Speed", 1.5) },
		{
			text = "Big appears x5 more often. Every minute: coins x3 for 15s.",
			passive = passive("BigSpawn", 5),
			periodic = { { kind = "Boost", every = 60, stat = "Coins", mult = 3, duration = 15 } :: Periodic },
		},
	},
	{
		"Owl", 44, rgb(150, 120, 95), "cat", "round",
		{ text = "Chests +75%", passive = passive("Chest", 1.75) },
		{
			text = "Offline earnings x5. Time Warp: every minute, coins x5 for 10s.",
			passive = passive("Offline", 5),
			periodic = { { kind = "Boost", every = 60, stat = "Coins", mult = 5, duration = 10 } :: Periodic },
		},
	},
	{
		"Deer", 88, rgb(200, 150, 100), "horns", "round",
		{ text = "Magnet (medium)", passive = passive("Magnet", 1.5) },
		{
			text = "Fuse with 2 instead of 5. Every 2 min: coins x3 for 30s.",
			passive = passive("FusionCost", 2),
			periodic = { { kind = "Boost", every = 120, stat = "Coins", mult = 3, duration = 30 } :: Periodic },
		},
	},
	{
		"Sprout", 176, rgb(123, 211, 137), "leaf", "sleepy",
		{ text = "Stomp every 15s", periodic = { { kind = "Area", every = 15, radius = 25, damageMult = 5 } :: Periodic } },
		{
			text = "Sources respawn instantly. Tornado: every 45s collects every coin pile.",
			passive = passive("InstantRespawn", 1),
			periodic = { { kind = "Wave", every = 45, onlyKind = "Pile" } :: Periodic },
		},
	},
	-- 4. Beach
	{
		"Crab", 50, rgb(229, 90, 70), "round", "angry",
		{ text = "Safes +50%", passive = passive("Chest", 1.5) },
		{
			text = "All coins x2. Smash: breaks the biggest source every 20s.",
			passive = passive("Coins", 2),
			periodic = { { kind = "Smash", every = 20 } :: Periodic },
		},
	},
	{
		"Turtle", 100, rgb(110, 180, 110), "none", "sleepy",
		{ text = "Combo lasts +3s", passive = passive("ComboHold", 3) },
		{
			text = "Combo never drops. Every minute: combo +20.",
			passive = passive("ComboHold", 1e9),
			periodic = { { kind = "ComboAdd", every = 60, amount = 20 } :: Periodic },
		},
	},
	{
		"Dolphin", 200, rgb(120, 160, 200), "none", "happy",
		{ text = "Hits twice", passive = passive("DoubleHit", 2) },
		{
			text = "All coins x3. Tsunami: every minute breaks every source in the zone.",
			passive = passive("Coins", 3),
			periodic = { { kind = "Wave", every = 60 } :: Periodic },
		},
	},
	{
		"Octopus", 400, rgb(160, 90, 200), "none", "round",
		{ text = "Stomp every 10s", periodic = { { kind = "Area", every = 10, radius = 30, damageMult = 5 } :: Periodic } },
		{
			text = "Power of all creatures x2. Clone Army: every minute, 8 clones of your strongest for 20s.",
			passive = passive("TeamPower", 2),
			periodic = { { kind = "CloneArmy", every = 60, count = 8, duration = 20 } :: Periodic },
		},
	},
	-- 5. Mushroom Cave
	{
		"Mushroom", 110, rgb(215, 70, 70), "cap", "round",
		{ text = "5% gem chance from every source", passive = passive("Gem", 0.05) },
		{
			text = "Neon chance x5. Every 30s breaks 5 sources.",
			passive = passive("VariantChance", 5, "Neon"),
			periodic = { { kind = "Strike", every = 30, count = 5 } :: Periodic },
		},
	},
	{
		"Bat", 220, rgb(70, 60, 90), "cat", "angry",
		{ text = "Magnet (large)", passive = passive("Magnet", 2) },
		{
			text = "Team speed x3. Every 40s collects every source in the zone.",
			passive = passive("Speed", 3),
			periodic = { { kind = "Wave", every = 40 } :: Periodic },
		},
	},
	{
		"Glowworm", 440, rgb(180, 240, 90), "antenna", "sleepy",
		{ text = "Team +50% in Dark zones", passive = passive("DarkPower", 1.5) },
		{
			text = "Element bonus x4 instead of x2. Every minute: element bonus x10 for 15s.",
			passive = passive("ElementBonus", 4),
			periodic = { { kind = "Boost", every = 60, stat = "Element", mult = 10, duration = 15 } :: Periodic },
		},
	},
	{
		"Shade", 880, rgb(90, 60, 130), "horns", "angry",
		{ text = "Combo lasts +5s", passive = passive("ComboHold", 5) },
		{
			text = "Power of all creatures x2.5. Shadow Clones: every minute, power x2 for 15s.",
			passive = passive("TeamPower", 2.5),
			periodic = { { kind = "Boost", every = 60, stat = "Power", mult = 2, duration = 15 } :: Periodic },
		},
	},
	-- 6. Desert
	{
		"Camel", 250, rgb(214, 170, 110), "round", "sleepy",
		{ text = "Team speed x2", passive = passive("Speed", 2) },
		{
			text = "50% chance a hatch is free. Every 3 min: 10 free eggs.",
			passive = passive("FreeHatch", 0.5),
			periodic = { { kind = "EggDrop", every = 180, count = 10, luck = 1 } :: Periodic },
		},
	},
	{
		"Scorpion", 500, rgb(140, 90, 50), "horns", "angry",
		{ text = "Safes +100%", passive = passive("Chest", 2) },
		{
			text = "All coins x3. Venom: every source in the zone loses 5% each second.",
			passive = passive("Coins", 3),
			periodic = { { kind = "Drain", every = 1, fraction = 0.05 } :: Periodic },
		},
	},
	{
		"Cactus", 1000, rgb(90, 170, 90), "leaf", "closed",
		{ text = "10% chance a hatch is free", passive = passive("FreeHatch", 0.1) },
		{
			text = "Hatch luck x5. Every 2 min: luck x20 for 30s.",
			passive = passive("Luck", 5),
			periodic = { { kind = "Boost", every = 120, stat = "Luck", mult = 20, duration = 30 } :: Periodic },
		},
	},
	{
		"Sphinx", 2000, rgb(230, 190, 90), "crown", "shades",
		{ text = "Stomp every 8s", periodic = { { kind = "Area", every = 8, radius = 30, damageMult = 5 } :: Periodic } },
		{
			text = "All coins x4. Every 2 min: a golden vault worth 100 chests.",
			passive = passive("Coins", 4),
			periodic = { { kind = "Rain", every = 120, chests = 100 } :: Periodic },
		},
	},
	-- 7. Snow Peak
	{
		"Penguin", 600, rgb(50, 55, 70), "none", "round",
		{ text = "Chests +100%", passive = passive("Chest", 2) },
		{
			text = "Lava chance x5. Freeze: every minute, sources respawn instantly for 20s.",
			passive = passive("VariantChance", 5, "Lava"),
			periodic = { { kind = "Boost", every = 60, stat = "Respawn", mult = 2, duration = 20 } :: Periodic },
		},
	},
	{
		"Seal", 1200, rgb(160, 170, 185), "none", "happy",
		{ text = "Hits twice", passive = passive("DoubleHit", 2) },
		{
			text = "Zones restore x3 faster. Avalanche: every 45s breaks half the zone.",
			passive = passive("Restore", 3),
			periodic = { { kind = "Strike", every = 45, fraction = 0.5 } :: Periodic },
		},
	},
	{
		"Snowman", 2400, rgb(245, 248, 255), "hat", "round",
		{ text = "15% chance a hatch is free", passive = passive("FreeHatch", 0.15) },
		{
			text = "25% of sources turn gold (x10). Blizzard: every minute, power x5 for 20s.",
			passive = passive("GoldenSources", 0.25),
			periodic = { { kind = "Boost", every = 60, stat = "Power", mult = 5, duration = 20 } :: Periodic },
		},
	},
	{
		"Yeti", 4800, rgb(235, 240, 250), "horns", "angry",
		{ text = "Stomp every 8s", periodic = { { kind = "Area", every = 8, radius = 30, damageMult = 5 } :: Periodic } },
		{
			text = "Power of all creatures x3. Mega Stomp: every 15s breaks every source around.",
			passive = passive("TeamPower", 3),
			periodic = { { kind = "Area", every = 15, radius = 60, damageMult = 1e12 } :: Periodic },
		},
	},
	-- 8. Volcano
	{
		"Imp", 1500, rgb(229, 83, 75), "horns", "angry",
		{ text = "8% gem chance from every source", passive = passive("Gem", 0.08) },
		{
			text = "Coin rain every 30s. Inferno: every minute burns every source.",
			periodic = { { kind = "Rain", every = 30, chests = 5 } :: Periodic, { kind = "Wave", every = 60 } :: Periodic },
		},
	},
	{
		"Salamander", 3000, rgb(245, 120, 50), "none", "happy",
		{ text = "Combo lasts +8s", passive = passive("ComboHold", 8) },
		{
			text = "Jackpot chance x10. Every minute: every source is a jackpot for 10s.",
			passive = passive("Jackpot", 10),
			periodic = { { kind = "Boost", every = 60, stat = "Jackpot", mult = 100, duration = 10 } :: Periodic },
		},
	},
	{
		"Golem", 6000, rgb(110, 105, 100), "none", "square",
		{ text = "Safes +200%", passive = passive("Chest", 3) },
		{
			text = "The whole team stomps. Rock Fall: every 30s breaks 10 sources.",
			periodic = {
				{ kind = "Area", every = 10, radius = 30, damageMult = 30 } :: Periodic,
				{ kind = "Strike", every = 30, count = 10 } :: Periodic,
			},
		},
	},
	{
		"Phoenix", 12000, rgb(255, 140, 40), "flame", "sparkle",
		{ text = "Stomp every 5s", periodic = { { kind = "Area", every = 5, radius = 30, damageMult = 5 } :: Periodic } },
		{
			text = "Every creature gets your strongest creature's power. Every 2 min: coins x10 for 20s.",
			passive = passive("CopyStrongest", 1),
			periodic = { { kind = "Boost", every = 120, stat = "Coins", mult = 10, duration = 20 } :: Periodic },
		},
	},
	-- 9. Frozen Lake
	{
		"Ice Fox", 4000, rgb(190, 225, 245), "cat", "happy",
		{ text = "Team speed x3", passive = passive("Speed", 3) },
		{
			text = "Offline earnings x10. Every minute: a golden chest.",
			passive = passive("Offline", 10),
			periodic = { { kind = "Rain", every = 60, chests = 10 } :: Periodic },
		},
	},
	{
		"Narwhal", 8000, rgb(130, 170, 220), "unihorn", "round",
		{ text = "Magnet (whole zone)", passive = passive("Magnet", 3) },
		{
			text = "Every egg gives 3 creatures. Tsunami every 30s.",
			passive = passive("EggExtra", 2),
			periodic = { { kind = "Wave", every = 30 } :: Periodic },
		},
	},
	{
		"Frost Owl", 16000, rgb(220, 235, 250), "cat", "sparkle",
		{ text = "20% chance a hatch is free", passive = passive("FreeHatch", 0.2) },
		{
			text = "Hatch luck x10. Every 5 min: a free egg with Crystal or better.",
			passive = passive("Luck", 10),
			periodic = { { kind = "EggDrop", every = 300, count = 1, luck = 1, minVariant = "Crystal" } :: Periodic },
		},
	},
	{
		"Ice Dragon", 32000, rgb(120, 210, 235), "horns", "angry",
		{ text = "Stomp every 5s", periodic = { { kind = "Area", every = 5, radius = 30, damageMult = 5 } :: Periodic } },
		{
			text = "All coins x5. Dragon Breath: every 20s burns 8 sources.",
			passive = passive("Coins", 5),
			periodic = { { kind = "Strike", every = 20, count = 8 } :: Periodic },
		},
	},
	-- 10. Pixel Zone
	{
		"Bot", 10000, rgb(154, 165, 177), "antenna", "square",
		{ text = "+100% coins in the Pixel Rift", passive = passive("RiftCoins", 2) },
		{
			text = "Pixel chance x5. Overclock: every minute, power x5 for 15s.",
			passive = passive("VariantChance", 5, "Pixel"),
			periodic = { { kind = "Boost", every = 60, stat = "Power", mult = 5, duration = 15 } :: Periodic },
		},
	},
	{
		"Byte", 20000, rgb(142, 91, 217), "none", "square",
		{ text = "Hits 3 times", passive = passive("DoubleHit", 3) },
		{
			text = "All coins x6. Pixel Burst: every 2 min, coins x20 for 15s.",
			passive = passive("Coins", 6),
			periodic = { { kind = "Boost", every = 120, stat = "Coins", mult = 20, duration = 15 } :: Periodic },
		},
	},
	{
		"Cursor", 40000, rgb(240, 240, 240), "none", "square",
		{ text = "Combo lasts +10s", passive = passive("ComboHold", 10) },
		{
			text = "Power of all creatures x4. Click Storm: every 30s breaks 10 sources.",
			passive = passive("TeamPower", 4),
			periodic = { { kind = "Strike", every = 30, count = 10 } :: Periodic },
		},
	},
	{
		"King", 80000, rgb(108, 99, 217), "crown", "shades",
		{ text = "Stomp every 3s", periodic = { { kind = "Area", every = 3, radius = 30, damageMult = 5 } :: Periodic } },
		{
			text = "Power of all creatures x5. Royal Decree: every 3 min, coins x20 for 30s and a free egg with luck x50.",
			passive = passive("TeamPower", 5),
			periodic = {
				{ kind = "Boost", every = 180, stat = "Coins", mult = 20, duration = 30 } :: Periodic,
				{ kind = "EggDrop", every = 180, count = 1, luck = 50 } :: Periodic,
			},
		},
	},
	-- Legendaries: one per zone in look, but they only hatch from the Legendary Egg in the last zone, so they
	-- are all stronger than that zone's King (80K): from 2x (Slime King) to 16x (Glitch)
	{
		"Slime King", 160000, rgb(107, 227, 107), "crown", "happy",
		{ text = "Coins +60%", passive = passive("Coins", 1.6) },
		{
			text = "Power of all creatures x3. Split: every minute, 5 mini slimes break 5 sources.",
			passive = passive("TeamPower", 3),
			periodic = { { kind = "Strike", every = 60, count = 5 } :: Periodic },
		},
	},
	{
		"Blossom Queen", 192000, rgb(255, 176, 214), "crown", "sparkle",
		{ text = "Hatch luck x2", passive = passive("Luck", 2) },
		{
			text = "Hatch luck x6. Pollen Storm: every 2 min, 3 free eggs with luck x10.",
			passive = passive("Luck", 6),
			periodic = { { kind = "EggDrop", every = 120, count = 3, luck = 10 } :: Periodic },
		},
	},
	{
		"Elder Treant", 224000, rgb(120, 84, 56), "leaf", "round",
		{ text = "Zones restore +50% faster", passive = passive("Restore", 1.5) },
		{
			text = "Power of all creatures x3. Roots: every 30s the ground shakes and breaks everything nearby.",
			passive = passive("TeamPower", 3),
			periodic = { { kind = "Area", every = 30, radius = 50, damageMult = 15 } :: Periodic },
		},
	},
	{
		"Kraken", 272000, rgb(40, 90, 140), "crown", "angry",
		{ text = "Chests +100%", passive = passive("Chest", 2) },
		{
			text = "Power of all creatures x3.5. Tidal Wave: every 45s a wave breaks every source in the zone.",
			passive = passive("TeamPower", 3.5),
			periodic = { { kind = "Wave", every = 45 } :: Periodic },
		},
	},
	{
		"Spore Sage", 320000, rgb(150, 90, 220), "cap", "sleepy",
		{ text = "Gems +50%", passive = passive("Gem", 1.5) },
		{
			text = "Gems x3. Spore Rain: every 90s, 25 gems fall around you.",
			passive = passive("Gem", 3),
			periodic = { { kind = "GemRain", every = 90, amount = 25 } :: Periodic },
		},
	},
	{
		"Pharaoh Scarab", 384000, rgb(245, 196, 66), "horns", "sparkle",
		{ text = "Jackpot chance x3", passive = passive("Jackpot", 3) },
		{
			text = "All coins x3. Sun Blessing: every 2 min, coins x15 for 30s.",
			passive = passive("Coins", 3),
			periodic = { { kind = "Boost", every = 120, stat = "Coins", mult = 15, duration = 30 } :: Periodic },
		},
	},
	{
		"Aurora Wolf", 480000, rgb(220, 240, 255), "cat", "sparkle",
		{ text = "Team speed x3", passive = passive("Speed", 3) },
		{
			text = "Power of all creatures x4. Pack Howl: every minute, 10 ghost wolves join for 20s.",
			passive = passive("TeamPower", 4),
			periodic = { { kind = "CloneArmy", every = 60, count = 10, duration = 20 } :: Periodic },
		},
	},
	{
		"Inferno Drake", 608000, rgb(40, 30, 34), "horns", "angry",
		{ text = "Stomp every 4s", periodic = { { kind = "Area", every = 4, radius = 35, damageMult = 6 } :: Periodic } },
		{
			text = "Power of all creatures x5. Meteor: every 20s the biggest source is smashed.",
			passive = passive("TeamPower", 5),
			periodic = { { kind = "Smash", every = 20 } :: Periodic },
		},
	},
	{
		"Frost Leviathan", 800000, rgb(120, 200, 240), "unihorn", "sparkle",
		{ text = "Offline earnings x5", passive = passive("Offline", 5) },
		{
			text = "Every creature gets your strongest creature's power. Blizzard: every minute, 20 golden chests.",
			passive = passive("CopyStrongest", 1),
			periodic = { { kind = "Rain", every = 60, chests = 20 } :: Periodic },
		},
	},
	{
		"Glitch", 1280000, rgb(24, 24, 32), "halo", "square",
		{ text = "Power of all creatures x2", passive = passive("TeamPower", 2) },
		{
			text = "Power of all creatures x6. Overclock: every 3 min, coins x25 for 30s and a free egg with luck x100.",
			passive = passive("TeamPower", 6),
			periodic = {
				{ kind = "Boost", every = 180, stat = "Coins", mult = 25, duration = 30 } :: Periodic,
				{ kind = "EggDrop", every = 180, count = 1, luck = 100 } :: Periodic,
			},
		},
	},
}

local zonesById: { [number]: Zone } = {}
for _, zone in zones do
	zonesById[zone.id] = zone
end

local function findRow(speciesId: string): { any }
	for _, candidate in rows do
		if candidate[1] == speciesId then
			return candidate
		end
	end
	error("Missing species row for " .. speciesId)
end

local species: { [string]: Species } = {}
local speciesOrder: { string } = {}
local eggs: { [number]: Egg } = {}

local function addSpecies(speciesId: string, zoneId: number, chance: number, eggId: number, legendary: boolean)
	local row = findRow(speciesId)
	species[speciesId] = {
		id = speciesId,
		zone = zoneId,
		chance = chance,
		power = row[2],
		color = row[3],
		top = row[4],
		face = row[5],
		big = row[6],
		titan = row[7],
		egg = eggId,
		legendary = legendary,
	}
	table.insert(speciesOrder, speciesId)
end

for _, zone in zones do
	for index, speciesId in zone.species do
		addSpecies(speciesId, zone.id, CHANCES[index], zone.id, false)
	end
	if zone.eggPrice > 0 then
		eggs[zone.id] = {
			id = zone.id,
			name = zone.name .. " Egg",
			zone = zone.id,
			price = zone.eggPrice,
			species = zone.species,
			chances = CHANCES,
			fixedOdds = false,
		}
	end
end

-- Legendary Egg: stands in the last zone. Almost always one of that zone's creatures; each Legendary is close
-- to impossible (1 in 200K up to 1 in 10M) and luck never changes these odds, only the variant and size.
local LEGENDARY_EGG = 11
local LEGENDARY_ODDS: { { string | number } } = {
	{ "Slime King", 200000, 1 },
	{ "Blossom Queen", 300000, 2 },
	{ "Elder Treant", 400000, 3 },
	{ "Kraken", 600000, 4 },
	{ "Spore Sage", 800000, 5 },
	{ "Pharaoh Scarab", 1000000, 6 },
	{ "Aurora Wolf", 1500000, 7 },
	{ "Inferno Drake", 2500000, 8 },
	{ "Frost Leviathan", 4000000, 9 },
	{ "Glitch", 10000000, 10 },
}
do
	local lastZone = zones[#zones]
	local legendaryTotal = 0
	local legendaryIds: { string } = {}
	local legendaryChances: { number } = {}
	for _, entry in LEGENDARY_ODDS do
		local chance = 1 / (entry[2] :: number)
		legendaryTotal += chance
		table.insert(legendaryIds, entry[1] :: string)
		table.insert(legendaryChances, chance)
		addSpecies(entry[1] :: string, entry[3] :: number, chance, LEGENDARY_EGG, true)
	end
	local ids: { string } = {}
	local chances: { number } = {}
	for index, speciesId in lastZone.species do
		table.insert(ids, speciesId)
		table.insert(chances, CHANCES[index] * (1 - legendaryTotal))
	end
	for index, speciesId in legendaryIds do
		table.insert(ids, speciesId)
		table.insert(chances, legendaryChances[index])
	end
	eggs[LEGENDARY_EGG] = {
		id = LEGENDARY_EGG,
		name = "★ Legendary Egg",
		zone = lastZone.id,
		price = lastZone.eggPrice * 5,
		species = ids,
		chances = chances,
		fixedOdds = true,
	}
end

return {
	eggs = eggs,
	LEGENDARY_EGG = LEGENDARY_EGG,
	zones = zones,
	zonesById = zonesById,
	species = species,
	speciesOrder = speciesOrder,
}
