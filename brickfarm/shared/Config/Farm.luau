--!strict
-- The world: a small market town in the middle, and around it, far apart, one big walled farm for each player of
-- the server. Inside a farm: the grid of land, the barn, the house, the stand at the gate where visitors buy, and
-- the tractor. Distances are studs.

return {
	FARMS = 6, -- (a server holds 6 players, one farm each)
	RING = 420, -- how far from the middle of the town each farm's middle is
	ENCLOSURE = 160, -- a farm's walled land (square)
	GATE = 26, -- the gap in its wall that faces the town
	WALL = 12, -- how tall the hedge around it is
	TOWN = 64, -- the radius of the town's square
	TILE = 7, -- a tile of land
	GAP = 1, -- between tiles
	COLUMNS = 6,
	ROWS = 6, -- (36 tiles when fully grown)
	START_TILES = 6, -- the land a new farm has
}
