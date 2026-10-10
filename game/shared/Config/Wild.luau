--!strict
-- The Wild (past the laser gate at the far end of the street): eight biomes one after another, each further
-- out than the last, with nests of its own eggs guarded by its predators. A player grabs an egg; a moment later
-- one of that biome's guardians comes after them, and only inside its biome: out of it, they're safe, and walk
-- the egg back through the gate. Caught, the egg goes back to its nest and they're sent back to the gate.
-- Further biomes have faster guardians: players train their speed on the treadmill in their garden to outrun
-- them (the first biome's they outrun from the start). All the eggs come back every few minutes.

export type Biome = { id: string, name: string, tier: number, guardian: number, color: Color3, theme: number }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local BIOMES: { Biome } = {
	-- `tier`: its eggs (Config/Eggs); `guardian`: its guardians' speed (studs a second, a player starts at 16);
	-- `theme`: its props (Config/PropLooks zones)
	{ id = "Meadow", name = "Meadow", tier = 1, guardian = 21, color = rgb(132, 200, 110), theme = 1 },
	{ id = "Flower", name = "Flower Field", tier = 2, guardian = 24, color = rgb(190, 220, 120), theme = 2 },
	{ id = "Forest", name = "Forest", tier = 3, guardian = 29, color = rgb(84, 150, 84), theme = 3 },
	{ id = "Beach", name = "Beach", tier = 4, guardian = 33, color = rgb(240, 222, 160), theme = 4 },
	{ id = "Cave", name = "Cave", tier = 5, guardian = 39, color = rgb(120, 110, 140), theme = 5 },
	{ id = "Desert", name = "Desert", tier = 6, guardian = 45, color = rgb(232, 196, 130), theme = 6 },
	{ id = "Snow", name = "Snow", tier = 7, guardian = 52, color = rgb(230, 240, 250), theme = 7 },
	{ id = "Volcano", name = "Volcano", tier = 8, guardian = 60, color = rgb(120, 70, 60), theme = 8 },
}

return {
	BIOMES = BIOMES,
	NESTS = 4, -- nests in each biome, two each side of the road
	GUARDIANS = 2, -- predators in each biome
	CATCH_RANGE = 4, -- a guardian this close catches the player
	WAKE = 1.5, -- seconds after an egg is taken before its guardian starts the chase
	RESET = 300, -- every nest gets its egg back this often
	CARRY = 0.9, -- a player carrying an egg runs this much of their speed
	START_SPEED = 24,
	MAX_SPEED = 70,
	-- Sprint (Shift, or the button on a phone): walking this many times faster while it's held
	SPRINT = 2,
	-- On the floating seat (MoveService) the player goes this many times their own speed, up to SEAT_MAX_SPEED.
	-- Not while carrying an egg: the chases stay fair.
	SEAT_SPEED = 4,
	SEAT_MAX_SPEED = 100,
	-- The treadmill in each garden: walking on it trains speed, `gains` a second per level (less the faster the
	-- player already is), the next level costing `prices`
	TREADMILL_GAINS = { 0.05, 0.1, 0.2, 0.35, 0.6 },
	TREADMILL_PRICES = { 2500, 25000, 250000, 2500000 },
}
