--!strict
-- The world: a small market town in the middle and, far around it, one huge walled territory for each player of
-- the server. A farm starts as one lot of land and grows a lot at a time, as far as its farmer likes: the yard by
-- the gate has the barn, the house, the stand and the tractor; the land spreads out behind them. Distances are studs.

return {
	FARMS = 6, -- (a server holds 6 players, one farm each)
	RING = 1250, -- how far from the middle of the town each farm's middle is
	TERRITORY = 800, -- a farm's walled territory (square)
	GATE = 26, -- the gap in its wall that faces the town
	WALL = 12, -- how tall the hedge around it is
	TOWN = 64, -- the radius of the town's square
	TILE = 7, -- a tile of land
	GAP = 1, -- between tiles
	LOT = 4, -- a lot of land is LOT x LOT tiles
	LOTS_WIDE = 11, -- lots can go this many to either side of the first one...
	LOTS_DEEP = 20, -- ...and this many back from it
	YARD = 110, -- studs from the gate to the first lot (the buildings are in this yard)
}
