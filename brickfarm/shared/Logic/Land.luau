--!strict
-- Land, in lots: a farm starts with one lot (LOT x LOT tiles) and buys more, one lot at a time, each next to land
-- it has; every lot costs more than the one before, with no end. A tile is named by its column and row ("x,z") in
-- the farm's own grid; a lot by its own ("cx,cz"). Lot 0,0 is the first, by the yard; columns go either side,
-- rows go back.

local FarmConfig = require(script.Parent.Parent.Config.Farm)

local Land = {}

Land.LOT = FarmConfig.LOT
Land.FIRST = "0,0"
Land.BASE = 3000 -- the second lot costs this...
Land.GROWTH = 2.2 -- ...and each one after this many times the one before

function Land.key(a: number, b: number): string
	return a .. "," .. b
end

-- "3,-2" -> 3, -2 (nil if it isn't one)
function Land.parse(key: any): (number?, number?)
	if type(key) ~= "string" then
		return nil, nil
	end
	local a, b = string.match(key, "^(%-?%d+),(%-?%d+)$")
	if not a then
		return nil, nil
	end
	return tonumber(a), tonumber(b)
end

-- The lot a tile is in
function Land.lotOf(tx: number, tz: number): (number, number)
	return tx // Land.LOT, tz // Land.LOT
end

function Land.inBounds(cx: number, cz: number): boolean
	return cz >= 0 and cz <= FarmConfig.LOTS_DEEP and math.abs(cx) <= FarmConfig.LOTS_WIDE
end

function Land.count(lots: { [string]: boolean }): number
	local n = 0
	for _ in lots do
		n += 1
	end
	return n
end

-- What the next lot costs, when they have `owned`
function Land.cost(owned: number): number
	local raw = Land.BASE * Land.GROWTH ^ (owned - 1)
	local round = 10 ^ math.max(0, math.floor(math.log10(raw)) - 1) -- (two figures: 500, 800, 1300, 2000...)
	return math.floor(raw / round + 0.5) * round
end

-- Whether a tile is on their land
function Land.owns(lots: { [string]: boolean }, key: any): boolean
	local tx, tz = Land.parse(key)
	if not tx or not tz then
		return false
	end
	local cx, cz = Land.lotOf(tx, tz)
	return lots[Land.key(cx, cz)] == true
end

-- Whether a lot can be bought: inside the walls, not theirs yet, next to land they have
function Land.buyable(lots: { [string]: boolean }, cx: number, cz: number): boolean
	if not Land.inBounds(cx, cz) or lots[Land.key(cx, cz)] then
		return false
	end
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		if lots[Land.key(cx + d[1], cz + d[2])] then
			return true
		end
	end
	return false
end

-- Every lot they could buy now
function Land.frontier(lots: { [string]: boolean }): { { cx: number, cz: number } }
	local list = {}
	local seen = {}
	for key in lots do
		local cx, cz = Land.parse(key)
		if cx and cz then
			for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local nx, nz = cx + d[1], cz + d[2]
				local k = Land.key(nx, nz)
				if not seen[k] and Land.buyable(lots, nx, nz) then
					seen[k] = true
					table.insert(list, { cx = nx, cz = nz })
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return if a.cz ~= b.cz then a.cz < b.cz else a.cx < b.cx
	end)
	return list
end

-- The tiles of a lot
function Land.tiles(cx: number, cz: number): { string }
	local list = {}
	for j = 0, Land.LOT - 1 do
		for i = 0, Land.LOT - 1 do
			table.insert(list, Land.key(cx * Land.LOT + i, cz * Land.LOT + j))
		end
	end
	return list
end

return Land
