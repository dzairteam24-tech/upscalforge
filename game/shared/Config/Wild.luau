--!strict
-- The Wild (past the laser gate at the far end of the street): eight biomes one after another, each further
-- out than the last, with nests of its own eggs guarded by its predators, asleep. A player grabs an egg; a
-- moment later that biome's guardian wakes and comes after them, and only inside its biome: out of it, they're
-- safe, and walk the egg back through the gate. Caught, they drop the egg there and are sent back to the gate:
-- they can come back for it (if nobody else takes it first).
-- Further biomes have faster guardians: players train their speed on the treadmill in their garden to outrun
-- them (the first biome's they outrun from the start). All the eggs come back every few minutes.

export type Biome = { id: string, name: string, tier: number, need: number, color: Color3, theme: number }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local BIOMES: { Biome } = {
	-- `tier`: its eggs (Config/Eggs); `need`: the speed (⚡) a player needs to outrun its guardian with an egg
	-- (Logic/Wild turns it into the guardian's real pace); `theme`: its props (Config/PropLooks zones)
	{ id = "Meadow", name = "Meadow", tier = 1, need = 0, color = rgb(132, 200, 110), theme = 1 },
	{ id = "Flower", name = "Flower Field", tier = 2, need = 200, color = rgb(190, 220, 120), theme = 2 },
	{ id = "Forest", name = "Forest", tier = 3, need = 1000, color = rgb(84, 150, 84), theme = 3 },
	{ id = "Beach", name = "Beach", tier = 4, need = 5000, color = rgb(240, 222, 160), theme = 4 },
	{ id = "Cave", name = "Cave", tier = 5, need = 25000, color = rgb(120, 110, 140), theme = 5 },
	{ id = "Desert", name = "Desert", tier = 6, need = 100000, color = rgb(232, 196, 130), theme = 6 },
	{ id = "Snow", name = "Snow", tier = 7, need = 400000, color = rgb(230, 240, 250), theme = 7 },
	{ id = "Volcano", name = "Volcano", tier = 8, need = 1500000, color = rgb(120, 70, 60), theme = 8 },
}

return {
	BIOMES = BIOMES,
	NESTS = 4, -- nests in each biome, two each side of the road
	GUARDIANS = 1, -- predators in each biome
	CATCH_RANGE = 4, -- a guardian this close catches the player
	WAKE = 1.5, -- seconds after an egg is taken before its guardian starts the chase
	-- Golden nests: when the nests fill up again, each biome may get one, with a Golden Egg (what hatches from it
	-- is Golden or better). Its guardian chases harder.
	GOLDEN_CHANCE = 0.3, -- for each biome, at each refill
	GOLDEN_MUTATION = "Golden",
	GOLDEN_GUARDIAN = 1.15, -- times the guardian's speed, chasing a Golden Egg
	DROP_TIME = 60, -- a thief caught by a guardian drops the egg there: it waits this long, then goes home
	-- Players can steal a Wild egg from each other on the way back (not in a Peaceful private server)
	ROB_RANGE = 10,
	ROB_GUARD = 4, -- seconds a new carrier can't be robbed
	RESET = 300, -- every nest gets its egg back this often
	CARRY = 0.9, -- a player carrying an egg runs this much of their speed
	-- Speed (⚡) is a big number that grows without end (0, 200, 5K, 1.5M...); how fast the player really walks
	-- grows with it slowly (Logic/Wild.walk): START_SPEED studs a second at 0, WALK_PER_DOUBLING more each time
	-- ⚡ + WALK_BASE doubles, up to WALK_MAX
	START_SPEED = 24,
	WALK_BASE = 100,
	WALK_PER_DOUBLING = 5,
	WALK_MAX = 110,
	-- Sprint (Shift, or the button on a phone): walking this many times faster while it's held
	SPRINT = 2,
	-- On the floating seat (MoveService) the player goes this many times their own walk, up to SEAT_MAX_SPEED.
	-- Not while carrying an egg: the chases stay fair.
	SEAT_SPEED = 4,
	SEAT_MAX_SPEED = 120,
	-- The treadmill in front of each garden: running on it, every TREADMILL_EVERY seconds the player gets
	-- TREADMILL_GAIN ⚡, plus more the more their garden earns (its coins a second to the TREADMILL_POWER), like
	-- Steal an Egg: better creatures, faster training. No coins spent: only running.
	TREADMILL_GAIN = 2,
	TREADMILL_POWER = 0.7,
	TREADMILL_EVERY = 5,
}
