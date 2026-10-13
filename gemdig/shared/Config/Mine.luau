--!strict
-- The mine: a shaft of cubes under each player's plot, built a few layers at a time as they dig down.

export type Zone = { name: string, from: number, color: Color3, material: Enum.Material, hp: number, perLayer: number, needs: number }

local rgb = Color3.fromRGB

return {
	CELL = 6, -- studs across one cube (a character is about 5 tall, so a tunnel it dug fits it)
	WIDTH = 5, -- cubes across the shaft (x and z)
	MAX_LAYER = 40, -- the deepest layer; the floor under it can't be dug
	KEEP_ABOVE = 5, -- layers kept built above the player...
	AHEAD = 6, -- ...and below them
	REACH = 24, -- studs: how far from the player a cube can be dug
	GEM_CHANCE = 0.15, -- of cubes hold a gem
	GEODE_CHANCE = 0.02, -- of cubes are a geode: it breaks into several gems at once
	GEODE_GEMS = 3,
	GEODE_DEEPER = 4, -- a geode's gems are rolled as if from this many layers deeper (so a bit rarer)
	TUTORIAL = { x = 3, l = 2, z = 3 }, -- the cube right under the first one dug down the middle: always a gem
	RESET_COOLDOWN = 20, -- seconds between mine resets
	CHECKPOINT_EVERY = 5, -- the elevator saves your depth in steps of this many layers
	-- Zones, by the layer they start at. How hard a cube is: `hp + perLayer * layers into the zone`. `needs`: the
	-- shovel (its number in Config/Gear) that can break cubes here at all: a weaker one only says "too hard".
	ZONES = {
		{ name = "Dirt", from = 1, color = rgb(121, 85, 58), material = Enum.Material.Ground, hp = 3, perLayer = 0.25, needs = 1 },
		{ name = "Stone", from = 9, color = rgb(128, 130, 138), material = Enum.Material.Slate, hp = 8, perLayer = 0.5, needs = 2 },
		{ name = "Deep", from = 17, color = rgb(58, 62, 84), material = Enum.Material.Basalt, hp = 14, perLayer = 0.75, needs = 3 },
		{ name = "Abyss", from = 25, color = rgb(70, 44, 96), material = Enum.Material.Basalt, hp = 22, perLayer = 1, needs = 4 },
		{ name = "Core", from = 33, color = rgb(128, 44, 44), material = Enum.Material.Basalt, hp = 32, perLayer = 1.25, needs = 5 },
	} :: { Zone },
}
