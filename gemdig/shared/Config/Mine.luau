--!strict
-- The mine: a shaft of cubes under each player's plot, built a few layers at a time as they dig down.

export type Zone = { name: string, from: number, color: Color3, material: Enum.Material, hp: number, perLayer: number }

local rgb = Color3.fromRGB

return {
	CELL = 6, -- studs across one cube (a character is about 5 tall, so a tunnel it dug fits it)
	WIDTH = 5, -- cubes across the shaft (x and z)
	MAX_LAYER = 40, -- the deepest layer; the floor under it can't be dug
	KEEP_ABOVE = 5, -- layers kept built above the player...
	AHEAD = 6, -- ...and below them
	REACH = 24, -- studs: how far from the player a cube can be dug
	GEM_CHANCE = 0.08, -- of cubes hold a gem
	-- Zones, by the layer they start at: how hard a cube is is `hp + perLayer * layers into the zone`
	ZONES = {
		{ name = "Dirt", from = 1, color = rgb(121, 85, 58), material = Enum.Material.Ground, hp = 3, perLayer = 0.25 },
		{ name = "Stone", from = 9, color = rgb(128, 130, 138), material = Enum.Material.Slate, hp = 9, perLayer = 0.5 },
		{ name = "Deep", from = 25, color = rgb(58, 62, 84), material = Enum.Material.Basalt, hp = 26, perLayer = 1 },
	} :: { Zone },
}
