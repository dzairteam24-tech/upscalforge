--!strict
-- The village: farms around a square in the middle. Each farm is a grid of tiles of land, a barn and a fence.
-- Distances are studs.

return {
	FARMS = 8, -- (a server holds up to 8 players, one farm each)
	TILE = 7, -- a tile of land
	GAP = 1, -- between tiles
	COLUMNS = 6,
	ROWS = 6, -- (36 tiles when fully grown)
	START_TILES = 6, -- the land a new farm has
	RING = 120, -- how far from the middle of the village each farm's middle is
	SQUARE = 34, -- the radius of the square in the middle
}
