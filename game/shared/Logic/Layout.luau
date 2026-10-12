--!strict
-- Where everything is (docs/images/map-plan.png): players arrive on a round square in the middle (no fountain).
-- The shops stand in a row of market stalls on its north side, facing south: the spawn and every garden see
-- their fronts. Behind them a straight road runs north to the big gate into the Wild. South of the square, the
-- players' gardens stand side by side on a wider arc, their laser gates (only the owner gets in) facing the
-- square, an arc road running past all the gates.

local IslandConfig = require(script.Parent.Parent.Config.Island)

local Layout = {
	SQUARE_RADIUS = 34, -- the square where players arrive: the town square
	SHOP_DEPTH = 8, -- a stall, from its counter back
	SHOP_WIDTH = 15,
	SHOP_STEP = 34, -- the distance between two stalls' middles (a good gap between them)
	GARDEN_RADIUS = 330, -- the gardens' middles, this far from the square's
	GARDEN_STEP = 34, -- degrees between two gardens: they fill the whole south half round the square, east to west
	GARDEN_ROAD_RADIUS = 260, -- the arc road past the gardens' gates
	ROAD_WIDTH_TOWN = 20,
	WILD_GATE_DISTANCE = 260, -- the big gate into the Wild, this far north of the square
	GARDEN_SIZE = 96,
	GATE_WIDTH = 16, -- the opening in a garden's front fence
	FENCE_HEIGHT = 10, -- the invisible wall behind the low picket fence (too tall to jump)
	CENTER = Vector3.new(0, 0, 0),
}

-- The shops' stalls: a row along the square's north edge, a little apart, their fronts south toward the square
-- and the gardens (the road to the Wild starts behind them)
Layout.SHOP_ROW = -40 -- (Z of the stalls' counters)
Layout.SHOP_SPOTS = {}
for k = 1, 5 do -- (the Fuse Machine, the Trail and Sell Shops, a gap for the road to the Wild, the Food Shop, the Mutation Machine)
	table.insert(Layout.SHOP_SPOTS, Vector3.new((k - 3.5) * Layout.SHOP_STEP, 0, Layout.SHOP_ROW))
end
-- Where players appear in the square, facing the stalls (north)
Layout.SPAWN = CFrame.new(0, 0.2, -4)

-- A frame at `at` (on the ground) turned about Y so its front (-Z) faces `target` (no lookAt: the same in
-- every runtime)
function Layout.facing(at: Vector3, target: Vector3): CFrame
	local d = target - at
	return CFrame.new(at) * CFrame.Angles(0, math.atan2(-d.X, -d.Z), 0)
end

-- A point on a circle round the square, `degrees` from north (west negative)
local function around(radius: number, degrees: number): Vector3
	local a = math.rad(degrees)
	return Layout.CENTER + Vector3.new(math.sin(a) * radius, 0, -math.cos(a) * radius)
end
Layout.around = around

-- A shop's stall: its counter's middle, facing south (the square, the gardens)
function Layout.shop(index: number): CFrame
	local at = Layout.SHOP_SPOTS[index]
	return Layout.facing(at, at + Vector3.new(0, 0, 1))
end

-- How far round (degrees from south, west negative) a garden stands: the first in the west
function Layout.gardenAngle(index: number): number
	return (index - (IslandConfig.ISLANDS + 1) / 2) * Layout.GARDEN_STEP
end

-- A garden's middle, its front (-Z, its gate) facing the square
function Layout.garden(index: number): CFrame
	local at = around(Layout.GARDEN_RADIUS, 180 - Layout.gardenAngle(index))
	return Layout.facing(at, Layout.CENTER)
end

-- The middle of a garden's gate (in its front fence, toward the square)
function Layout.gate(index: number): CFrame
	return Layout.garden(index) * CFrame.new(0, 0, -Layout.GARDEN_SIZE / 2)
end

-- Inside a garden (its frame's space, front -Z toward the gate): the gate opens onto the hatchery, a wooden
-- deck across the front with the nests either side of a short path, so the owner guards them from the gate. The
-- path leads on into the pasture, which fills the rest of the garden, back to the fence, round a pond.
local HALF = Layout.GARDEN_SIZE / 2
local PASTURE_FRONT, PASTURE_BACK = -HALF + 25, HALF - 2
Layout.HATCHERY = { center = Vector3.new(0, 0, -HALF + 11), size = Vector3.new(66, 0, 20) }
Layout.PASTURE = {
	center = Vector3.new(0, 0, (PASTURE_FRONT + PASTURE_BACK) / 2),
	size = Vector3.new(Layout.GARDEN_SIZE - 8, 0, PASTURE_BACK - PASTURE_FRONT),
}
Layout.NEST_SIZE = 6 -- a nest's width (an egg in it is drawn to fit, whatever its tier)
Layout.PATH_WIDTH = 6
Layout.TROUGH = Vector3.new(-12, 0, PASTURE_FRONT + 5) -- in the pasture, beside where the path comes in
-- The treadmill: outside, in front of the garden beside its gate, along the fence (it runs along X), where the
-- road past the gardens sees its owner training
Layout.TREADMILL = Vector3.new(Layout.GATE_WIDTH / 2 + 8, 0, -HALF - 4.5)
Layout.BARN = Vector3.new(HALF - 11.5, 0, HALF - 8.5) -- the storage barn, in the pasture's back corner
-- The incubators (machines), in a row along the back of the pasture, west of the barn
Layout.MACHINES = {}
for k = 1, #IslandConfig.MACHINE_PRICES do
	table.insert(Layout.MACHINES, Vector3.new(-HALF + 12 + (k - 1) * 11, 0, HALF - 9))
end

-- The barn and the incubators stand at the back of the pasture: as it grows back (pastureGrowth), they move back
-- with it, always at the back edge. These spots (Layout.BARN, Layout.MACHINES) are at the first level.
function Layout.backShift(level: number?): Vector3
	return Vector3.new(0, 0, Layout.pastureGrowth(level or 1))
end

-- What the creatures walk round (a spot in the garden's space and how far from it to keep; `back`: it moves
-- back with the pasture)
Layout.OBSTACLES = {
	{ center = Layout.TROUGH, radius = 4, back = false },
	{ center = Layout.BARN, radius = 7, back = true },
}
for _, spot in Layout.MACHINES do
	table.insert(Layout.OBSTACLES, { center = spot, radius = 5, back = true })
end
function Layout.blocked(inside: Vector3, level: number?): boolean
	local shift = Layout.backShift(level)
	for _, obstacle in Layout.OBSTACLES do
		local center = if obstacle.back then obstacle.center + shift else obstacle.center
		if Vector3.new(inside.X - center.X, 0, inside.Z - center.Z).Magnitude < obstacle.radius then
			return true
		end
	end
	return false
end

-- A nest's spot (an incubator): eight on each side of the path, in two rows of four; the first ones (the safe
-- one first) beside the path, then outward
local NESTS: { Vector3 } = {}
for column = 0, 3 do
	for _, z in { -HALF + 15.5, -HALF + 6.5 } do
		for _, side in { -1, 1 } do
			table.insert(NESTS, Vector3.new(side * (7.5 + column * 7), 0, z))
		end
	end
end
-- Where a new player's free first egg is set down (in front, beside the path)
Layout.START_SPOT = NESTS[1]

-- Whether an egg can be set down at this spot in a garden (its own space): on its grass, the pasture grown to
-- `level`, clear of the trough, the barn and the incubators
function Layout.eggSpot(inside: Vector3, level: number): boolean
	local back = HALF + Layout.pastureGrowth(level) - 3
	return math.abs(inside.X) <= HALF - 3 and inside.Z >= -HALF + 3 and inside.Z <= back and not Layout.blocked(inside, level)
end

function Layout.incubator(index: number, slot: number, level: number?): Vector3
	if slot > IslandConfig.MACHINE_SLOT then
		return Layout.garden(index):PointToWorldSpace(Layout.MACHINES[slot - IslandConfig.MACHINE_SLOT] + Layout.backShift(level))
	end
	return Layout.garden(index):PointToWorldSpace(NESTS[slot])
end

-- How far past the garden's back fence the pasture reaches at a level (it grows away from the square)
function Layout.pastureGrowth(level: number): number
	local growth = IslandConfig.PASTURE_GROWTH
	return growth[math.clamp(level, 1, #growth)]
end

-- The pasture's middle (in the garden's space) and size at a level
function Layout.pastureArea(level: number): (Vector3, Vector3)
	local extra = Layout.pastureGrowth(level)
	return Layout.PASTURE.center + Vector3.new(0, 0, extra / 2), Layout.PASTURE.size + Vector3.new(0, 0, extra)
end

-- The pasture's middle and size in the world (the creatures roam inside it), at a level (1 if not given)
function Layout.pasture(index: number, level: number?): (CFrame, Vector3)
	local center, size = Layout.pastureArea(level or 1)
	return Layout.garden(index) * CFrame.new(center), size
end

-- Where a creature living in the garden starts: in a ring round the pasture's middle (it wanders from there)
function Layout.pen(index: number, slot: number): Vector3
	local count = IslandConfig.PENS + #IslandConfig.PEN_PRICES
	local angle = (slot - 1) * 2 * math.pi / count
	local inside = Layout.PASTURE.center + Vector3.new(math.sin(angle) * Layout.PASTURE.size.X * 0.32, 0, -math.cos(angle) * Layout.PASTURE.size.Z * 0.3)
	return Layout.garden(index):PointToWorldSpace(inside)
end

-- Where a player comes home to: just inside their garden's gate, facing in
function Layout.home(index: number): CFrame
	return Layout.garden(index) * CFrame.new(0, 0, -HALF + 4) * CFrame.Angles(0, math.pi, 0)
end

-- The Wild (Config/Wild): past the big gate north of the square, a road runs on through the biomes one after
-- another, nests on both sides of it. South of the gate is safe.
Layout.BIOME_LENGTH = 220 -- (big biomes: room to run, and to get caught)
Layout.WILD_WIDTH = 240
Layout.ROAD_WIDTH = 14

-- The big gate into the Wild
function Layout.wildGate(): Vector3
	return Layout.CENTER + Vector3.new(0, 0, -Layout.WILD_GATE_DISTANCE)
end

-- A biome's middle (1 nearest the gate)
function Layout.biome(i: number): Vector3
	return Layout.wildGate() + Vector3.new(0, 0, -(i - 0.5) * Layout.BIOME_LENGTH)
end

-- A nest in a biome: two each side of the road
function Layout.wildNest(i: number, k: number): Vector3
	local side = if k % 2 == 1 then -1 else 1
	local row = (k - 1) // 2
	-- (spread over the biome: halfway out from the road, a quarter of the way in from each end)
	local out = Layout.ROAD_WIDTH / 2 + (Layout.WILD_WIDTH / 2 - Layout.ROAD_WIDTH / 2) * 0.5
	local along = Layout.BIOME_LENGTH * 0.25
	return Layout.biome(i) + Vector3.new(side * out, 0, if row == 0 then along else -along)
end

-- Which biome a position is in, if any
function Layout.biomeAt(position: Vector3, count: number): number?
	local gate = Layout.wildGate()
	local into = gate.Z - position.Z
	if into < 0 or math.abs(position.X - gate.X) > Layout.WILD_WIDTH / 2 then
		return nil
	end
	local i = into // Layout.BIOME_LENGTH + 1
	return if i <= count then i else nil
end

-- Whether a position is back through the gate (where a thief is safe)
function Layout.pastGate(position: Vector3): boolean
	return position.Z > Layout.wildGate().Z
end

-- The town's ground (the square, the shops, the gardens; the Wild goes on north of it): how far it reaches east
-- and west of the square, and its north and south edges
function Layout.ground(): (number, number, number)
	local growth = IslandConfig.PASTURE_GROWTH
	local south = Layout.GARDEN_RADIUS + Layout.GARDEN_SIZE / 2 + growth[#growth] + 30
	return Layout.GARDEN_RADIUS + 150, -Layout.WILD_GATE_DISTANCE, south
end

-- The town's roads: straight ones (from a to b) and arcs round the square (degrees from north), with widths
export type Road = { a: Vector3, b: Vector3, width: number }
export type Arc = { radius: number, from: number, to: number, width: number }
function Layout.roads(): ({ Road }, { Arc })
	local w = Layout.ROAD_WIDTH_TOWN
	local around = Layout.around
	local roads: { Road } = {}
	local arcs: { Arc } = {}
	-- (from behind the stalls)
	table.insert(roads, { a = Layout.CENTER + Vector3.new(0, 0, Layout.SHOP_ROW - Layout.SHOP_DEPTH - 9), b = Layout.wildGate(), width = w })
	table.insert(roads, { a = around(Layout.SQUARE_RADIUS - 2, 180), b = around(Layout.GARDEN_ROAD_RADIUS, 180), width = w })
	local last = Layout.gardenAngle(IslandConfig.ISLANDS) + Layout.GARDEN_STEP * 0.3
	table.insert(arcs, { radius = Layout.GARDEN_ROAD_RADIUS, from = 180 - last, to = 180 + last, width = w })
	for index = 1, IslandConfig.ISLANDS do
		local angle = 180 - Layout.gardenAngle(index)
		table.insert(roads, { a = around(Layout.GARDEN_ROAD_RADIUS, angle), b = Layout.gate(index).Position, width = Layout.GATE_WIDTH })
	end
	return roads, arcs
end

-- How far a point is from the edge of the nearest town road (negative: on it)
function Layout.roadDistance(point: Vector3): number
	local roads, arcs = Layout.roads()
	local p = Vector3.new(point.X, 0, point.Z)
	local best = math.huge
	for _, r in roads do
		local a, b = Vector3.new(r.a.X, 0, r.a.Z), Vector3.new(r.b.X, 0, r.b.Z)
		local ab = b - a
		local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
		best = math.min(best, (p - (a + ab * t)).Magnitude - r.width / 2)
	end
	local fromCenter = p - Vector3.new(Layout.CENTER.X, 0, Layout.CENTER.Z)
	local degrees = math.deg(math.atan2(fromCenter.X, -fromCenter.Z)) % 360
	for _, arc in arcs do
		local lo, hi = arc.from % 360, arc.to % 360
		local within = arc.to - arc.from >= 360 or (if lo <= hi then degrees >= lo and degrees <= hi else degrees >= lo or degrees <= hi)
		if within then
			best = math.min(best, math.abs(fromCenter.Magnitude - arc.radius) - arc.width / 2)
		end
	end
	return best
end

-- Which garden a position is in, if any
function Layout.gardenAt(position: Vector3): number?
	for index = 1, IslandConfig.ISLANDS do
		local inside = Layout.garden(index):PointToObjectSpace(position)
		if math.abs(inside.X) <= Layout.GARDEN_SIZE / 2 and math.abs(inside.Z) <= Layout.GARDEN_SIZE / 2 then
			return index
		end
	end
	return nil
end

return Layout
