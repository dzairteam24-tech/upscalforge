--!strict
-- Where everything is (docs/images/map-plan.png): players arrive on a round square in the middle (no fountain).
-- North of it, the shops stand on an arc, each facing the square, with a ring road round the square linking
-- them; a straight road runs north from the square to the big gate into the Wild. South of the square, the
-- players' gardens stand side by side on a wider arc, their laser gates (only the owner gets in) facing the
-- square, an arc road running past all the gates.

local IslandConfig = require(script.Parent.Parent.Config.Island)

local Layout = {
	SQUARE_RADIUS = 26, -- the square where players arrive
	RING_RADIUS = 120, -- the ring road round the square
	SHOP_RADIUS = 150, -- the shops' middles, this far from the square's
	SHOP_DEPTH = 26, -- a shop's lot, from its front back
	GARDEN_RADIUS = 300, -- the gardens' middles, this far from the square's
	GARDEN_STEP = 18, -- degrees between two gardens on their arc
	GARDEN_ROAD_RADIUS = 238, -- the arc road past the gardens' gates
	ROAD_WIDTH_TOWN = 20,
	WILD_GATE_DISTANCE = 260, -- the big gate into the Wild, this far north of the square
	GARDEN_SIZE = 80,
	GATE_WIDTH = 16, -- the opening in a garden's front fence
	FENCE_HEIGHT = 10, -- the invisible wall behind the low picket fence (too tall to jump)
	CENTER = Vector3.new(0, 0, 0),
}

-- The shops' spots on their arc: degrees from north, west negative (the road north runs between them)
Layout.SHOP_ANGLES = { -50, -24, 32 }

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

-- A shop's spot, facing the square
function Layout.shop(index: number): CFrame
	return Layout.facing(around(Layout.SHOP_RADIUS, Layout.SHOP_ANGLES[index]), Layout.CENTER)
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
Layout.POND = { center = Layout.PASTURE.center, radius = 6.5 }
Layout.NEST_SIZE = 6 -- a nest's width (an egg in it is drawn to fit, whatever its tier)
Layout.PATH_WIDTH = 6
Layout.TROUGH = Vector3.new(-12, 0, PASTURE_FRONT + 5) -- in the pasture, beside where the path comes in
-- The treadmill: outside, in front of the garden beside its gate, along the fence (it runs along X), where the
-- road past the gardens sees its owner training
Layout.TREADMILL = Vector3.new(Layout.GATE_WIDTH / 2 + 8, 0, -HALF - 4.5)
Layout.BARN = Vector3.new(HALF - 11.5, 0, HALF - 8.5) -- the storage barn, in the pasture's back corner

-- What the creatures walk round (a spot in the garden's space and how far from it to keep)
Layout.OBSTACLES = {
	{ center = Layout.POND.center, radius = Layout.POND.radius + 2 },
	{ center = Layout.TROUGH, radius = 4 },
	{ center = Layout.BARN, radius = 7 },
}
function Layout.blocked(inside: Vector3): boolean
	for _, obstacle in Layout.OBSTACLES do
		if Vector3.new(inside.X - obstacle.center.X, 0, inside.Z - obstacle.center.Z).Magnitude < obstacle.radius then
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
function Layout.incubator(index: number, slot: number): Vector3
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

-- Where a creature living in the garden starts: in a ring round the pond (it wanders from there)
function Layout.pen(index: number, slot: number): Vector3
	local count = IslandConfig.PENS + #IslandConfig.PEN_PRICES
	local angle = (slot - 1) * 2 * math.pi / count
	local inside = Layout.POND.center + Vector3.new(math.sin(angle) * Layout.PASTURE.size.X * 0.32, 0, -math.cos(angle) * Layout.PASTURE.size.Z * 0.3)
	return Layout.garden(index):PointToWorldSpace(inside)
end

-- Where a player comes home to: just inside their garden's gate, facing in
function Layout.home(index: number): CFrame
	return Layout.garden(index) * CFrame.new(0, 0, -HALF + 4) * CFrame.Angles(0, math.pi, 0)
end

-- The Wild (Config/Wild): past the big gate north of the square, a road runs on through the biomes one after
-- another, nests on both sides of it. South of the gate is safe.
Layout.BIOME_LENGTH = 140
Layout.WILD_WIDTH = 160
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
	return Layout.biome(i) + Vector3.new(side * (Layout.ROAD_WIDTH / 2 + 30), 0, if row == 0 then 30 else -30)
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
