--!strict
-- Where everything is (docs/images/map-plan.png): players arrive on a round square in the middle (no fountain).
-- The shops stand in a row of market stalls on its north side, facing south: the spawn and every garden see
-- their fronts. Behind them a straight road runs north to the big gate into the Wild. South of the square, the
-- players' gardens stand side by side on a wider arc, their laser gates (only the owner gets in) facing the
-- square, an arc road running past all the gates.

local IslandConfig = require(script.Parent.Parent.Config.Island)

local Layout = {
	SQUARE_RADIUS = 55, -- the paved square where players arrive (the grass round it is open ground) -- the square where players arrive: the town square
	SHOP_DEPTH = 10, -- a stall, from its counter back
	SHOP_SCALE = 1.35, -- the shop buildings are drawn this much bigger than their base size below
	SHOP_WIDTH = 18,
	GARDEN_RADIUS = 330, -- the gardens' middles, this far from the square's
	GARDEN_STEP = 34, -- degrees between two gardens: they fill the whole south half round the square, east to west
	GARDEN_ROAD_RADIUS = 260, -- the arc road past the gardens' gates
	ROAD_WIDTH_TOWN = 20,
	AVENUE_WIDTH = 28, -- the paved way from the square to the Wild's gate: grass on both sides
	WILD_GATE_DISTANCE = 400, -- the big gate into the Wild, this far north of the square
	GARDEN_SIZE = 96,
	GATE_WIDTH = 16, -- the opening in a garden's front fence
	FENCE_HEIGHT = 10, -- the invisible wall behind the low picket fence (too tall to jump)
	CENTER = Vector3.new(0, 0, 0), -- the town's middle: the gardens' arc and the way to the Wild are measured from it
	SQUARE_CENTER = Vector3.new(0, 0, -140), -- the square itself, moved up toward the gate to leave room for the gardens
}

-- The shops: a straight row in line with the Wild's gate, two on each side of it, outside its towers, their fronts
-- toward the square. The avenue and the grass round it stay open (room to fight).
Layout.SHOP_Z = -Layout.WILD_GATE_DISTANCE + 20 -- (the counters' Z: just in front of the gate's line, room behind them for the building)
Layout.SHOP_SPOTS = {
	Vector3.new(-138, 0, Layout.SHOP_Z), -- the Shop
	Vector3.new(-184, 0, Layout.SHOP_Z), -- the Fuse Machine
	Vector3.new(138, 0, Layout.SHOP_Z), -- the Trail Shop
	Vector3.new(184, 0, Layout.SHOP_Z), -- the Mutation Machine
}
-- The paved strip along the gate's line, under the shops: as wide as the row of them, in front of the gate
Layout.GATE_PLAZA_HALF = 215 -- (half its width)
Layout.GATE_PLAZA_DEPTH = 50 -- (from the gate's line toward the square)
-- Where players appear in the square, facing the stalls (north)
Layout.SPAWN = CFrame.new(Layout.SQUARE_CENTER.X, 0.2, Layout.SQUARE_CENTER.Z - 4)

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

-- A shop's stall: its counter's middle, facing south (the square)
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

-- Inside a garden (its frame's space, front -Z toward the gate), from the gate back:
--   the yard: the incubators (machines) left of the path, the storage barn and the trough right of it;
--   the hatching field behind a low hedge: eggs are set down only here, and it stays clear (nothing walks in it);
--   the pen at the back, behind its own fence: every creature in the garden lives there. It grows back with
--   the pasture's level (PASTURE_GROWTH).
local HALF = Layout.GARDEN_SIZE / 2
-- The garden is longer than it is wide: its pen reaches PEN_EXTRA studs past the square's back edge
Layout.PEN_EXTRA = 40
Layout.GARDEN_BACK = HALF + Layout.PEN_EXTRA -- (its back fence, in its frame's space)
-- Behind the yard, fence to fence: the hatching field, then the pen (twice as deep)
local FIELD_FRONT, FIELD_BACK = -HALF + 16, 7
local PEN_FRONT, PEN_BACK = FIELD_BACK + 1, Layout.GARDEN_BACK - 1 -- the creatures' pen
Layout.FIELD = { center = Vector3.new(0, 0, (FIELD_FRONT + FIELD_BACK) / 2), size = Vector3.new(Layout.GARDEN_SIZE - 2, 0, FIELD_BACK - FIELD_FRONT) }
-- (the pen: called the pasture in the rest of the game, it's where the creatures roam)
Layout.PASTURE = {
	center = Vector3.new(0, 0, (PEN_FRONT + PEN_BACK) / 2),
	size = Vector3.new(Layout.GARDEN_SIZE - 2, 0, PEN_BACK - PEN_FRONT),
}
Layout.GRASS_TOP = 0.65 -- (the top of the pen's grass over the garden's ground: what stands in it stands there)
Layout.NEST_SIZE = 6 -- a nest's width (an egg in it is drawn to fit, whatever its tier)
Layout.PATH_WIDTH = 6
local YARD_Z = -HALF + 11 -- (the row the yard's things stand in)
Layout.TROUGH = Vector3.new(16, 0, YARD_Z) -- in the yard, right of the path
-- The treadmill: outside, in front of the garden beside its gate, along the fence (it runs along X), where the
-- road past the gardens sees its owner training
Layout.TREADMILL = Vector3.new(Layout.GATE_WIDTH / 2 + 8, 0, -HALF - 4.5)
Layout.BARN = Vector3.new(33, 0, YARD_Z) -- the storage barn, in the yard's right corner
-- The incubators (machines), in a row left of the path, from the path outward
Layout.MACHINES = {}
for k = 1, #IslandConfig.MACHINE_PRICES do
	table.insert(Layout.MACHINES, Vector3.new(-12 - (k - 1) * 9.5, 0, YARD_Z))
end

-- Nothing moves back with the pen any more (the yard stays by the gate): kept for callers, always zero
function Layout.backShift(_level: number?): Vector3
	return Vector3.zero
end

-- What the creatures walk round in the pen (nothing stands in it now)
Layout.OBSTACLES = {} :: { { center: Vector3, radius: number, back: boolean } }
function Layout.blocked(inside: Vector3, level: number?): boolean
	for _, obstacle in Layout.OBSTACLES do
		if Vector3.new(inside.X - obstacle.center.X, 0, inside.Z - obstacle.center.Z).Magnitude < obstacle.radius then
			return true
		end
	end
	return false
end

-- A nest's spot (an egg's default place, by slot): in the hatching field, eight on each side of the path, in two
-- rows of four; the first ones beside the path, then outward
local NESTS: { Vector3 } = {}
for column = 0, 3 do
	for _, z in { FIELD_FRONT + 6, FIELD_FRONT + 15 } do
		for _, side in { -1, 1 } do
			table.insert(NESTS, Vector3.new(side * (7.5 + column * 7), 0, z))
		end
	end
end
-- Where a new player's free first egg is set down (at the front of the field, beside the path)
Layout.START_SPOT = NESTS[1]

-- Whether an egg can be set down at this spot in a garden (its own space): only in the hatching field, off the path
function Layout.eggSpot(inside: Vector3, _level: number): boolean
	local onPath = math.abs(inside.X) <= Layout.PATH_WIDTH / 2 + 1
	return not onPath and math.abs(inside.X) <= Layout.FIELD.size.X / 2 - 2 and inside.Z >= FIELD_FRONT + 2 and inside.Z <= FIELD_BACK - 2
end

function Layout.incubator(index: number, slot: number, level: number?): Vector3
	if slot > IslandConfig.MACHINE_SLOT then
		return Layout.garden(index):PointToWorldSpace(Layout.MACHINES[slot - IslandConfig.MACHINE_SLOT])
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
	local inside = Layout.PASTURE.center + Vector3.new(math.sin(angle) * Layout.PASTURE.size.X * 0.32, Layout.GRASS_TOP, -math.cos(angle) * Layout.PASTURE.size.Z * 0.3)
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

-- Where a biome's guardian sleeps: in its far corner, by the wall (the left one, then the right one, biome after
-- biome), with its nests round it (like Steal an Egg)
function Layout.wildGuardian(i: number): Vector3
	local side = if i % 2 == 1 then -1 else 1
	return Layout.biome(i) + Vector3.new(side * (Layout.WILD_WIDTH / 2 - 26), 0, -Layout.BIOME_LENGTH * 0.3)
end

-- A nest in a biome (k of count): in a half ring in front of its sleeping guardian, open toward the road
function Layout.wildNest(i: number, k: number, count: number?): Vector3
	local n = count or 6
	local guardian = Layout.wildGuardian(i)
	local toRoad = math.atan2(0, -math.sign(guardian.X - Layout.biome(i).X)) -- (the angle facing the road)
	local spread = math.rad(150)
	local angle = toRoad + (if n > 1 then -spread / 2 + (k - 1) * spread / (n - 1) else 0)
	return guardian + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 8
end

-- A biome's nests scattered by luck in front of its guardian (toward the road), apart from each other: a new
-- layout each server (random gives numbers in [0, 1))
Layout.WILD_NEST_GAP = 4 -- (studs between two nests' middles: small, close together, like Steal an Egg's)
function Layout.wildNests(i: number, count: number, random: () -> number): { Vector3 }
	local guardian = Layout.wildGuardian(i)
	local toRoad = math.atan2(0, -math.sign(guardian.X - Layout.biome(i).X))
	local spots: { Vector3 } = {}
	for _ = 1, count do
		-- (tries spots by luck; the first with room enough wins, else the roomiest one tried)
		local best, room = guardian, -1
		for _ = 1, 200 do
			local angle = toRoad + (random() - 0.5) * math.rad(140)
			local spot = guardian + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (5 + random() * 8)
			local nearest = math.huge
			for _, other in spots do
				nearest = math.min(nearest, (other - spot).Magnitude)
			end
			if nearest > room then
				best, room = spot, nearest
			end
			if room >= Layout.WILD_NEST_GAP then
				break
			end
		end
		table.insert(spots, best)
	end
	return spots
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
	local south = Layout.GARDEN_RADIUS + Layout.GARDEN_BACK + growth[#growth] + 30
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
	table.insert(roads, { a = Layout.SQUARE_CENTER + Vector3.new(0, 0, -Layout.SQUARE_RADIUS - 2), b = Layout.wildGate(), width = Layout.AVENUE_WIDTH })
	table.insert(roads, { a = Layout.SQUARE_CENTER + Vector3.new(0, 0, Layout.SQUARE_RADIUS - 2), b = around(Layout.GARDEN_ROAD_RADIUS, 180), width = w })
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
		if math.abs(inside.X) <= Layout.GARDEN_SIZE / 2 and inside.Z >= -Layout.GARDEN_SIZE / 2 and inside.Z <= Layout.GARDEN_BACK then
			return index
		end
	end
	return nil
end

return Layout
