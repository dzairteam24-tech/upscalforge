--!strict
-- Where everything is: one street, walked from south to north. Players arrive in a small square with a fountain;
-- the street leaves it northward past the six shops, three each side facing each other (the Egg Shop first,
-- nearest the square), then past the players' gardens, also in two rows facing each other, so everyone sees
-- their neighbours. Each garden is fenced, with a laser gate onto the street that only lets its owner in.

local IslandConfig = require(script.Parent.Parent.Config.Island)

local Layout = {
	SQUARE_RADIUS = 26, -- the square where players arrive
	SHOP_DEPTH = 26, -- a shop's lot, from the street back
	SHOP_SPACING = 30, -- between two shops' middles along the street
	GARDEN_SIZE = 80,
	GARDEN_GAP = 10, -- between two gardens in a row
	STREET_WIDTH = 26,
	GATE_WIDTH = 16, -- the opening in a garden's front fence
	FENCE_HEIGHT = 10, -- the invisible wall behind the low picket fence (too tall to jump)
	CENTER = Vector3.new(0, 0, 0),
}

local SHOPS = 6
local ROWS = math.ceil(IslandConfig.ISLANDS / 2)

-- A frame at `at` (on the ground) turned about Y so its front (-Z) faces `target` (no lookAt: the same in
-- every runtime)
function Layout.facing(at: Vector3, target: Vector3): CFrame
	local d = target - at
	return CFrame.new(at) * CFrame.Angles(0, math.atan2(-d.X, -d.Z), 0)
end

-- Where the street starts (the square's north edge) and how long it is (past the shops and the gardens)
function Layout.street(): (Vector3, number)
	local start = Layout.CENTER + Vector3.new(0, 0, -Layout.SQUARE_RADIUS + 4)
	local length = Layout.shopsLength() + ROWS * (Layout.GARDEN_SIZE + Layout.GARDEN_GAP) + 10
	return start, length
end

-- How much of the street the shops take
function Layout.shopsLength(): number
	return math.ceil(SHOPS / 2) * Layout.SHOP_SPACING + 6
end

-- A shop's spot (1..6) beside the street, facing it: odd ones west, even ones east, from the square northward
function Layout.shop(index: number): CFrame
	local start = Layout.CENTER + Vector3.new(0, 0, -Layout.SQUARE_RADIUS + 4)
	local side = if index % 2 == 1 then -1 else 1
	local row = (index - 1) // 2
	local z = start.Z - 6 - Layout.SHOP_SPACING / 2 - row * Layout.SHOP_SPACING
	local at = Vector3.new(start.X + side * (Layout.STREET_WIDTH / 2 + Layout.SHOP_DEPTH / 2), 0, z)
	return Layout.facing(at, Vector3.new(start.X, 0, z))
end

-- A garden's middle, its front (-Z) facing the street. Odd ones west of the street, even ones east, from the
-- plaza northward.
function Layout.garden(index: number): CFrame
	local side = if index % 2 == 1 then -1 else 1
	local row = (index - 1) // 2
	local start = Layout.street()
	local z = start.Z - Layout.shopsLength() - Layout.GARDEN_GAP - Layout.GARDEN_SIZE / 2 - row * (Layout.GARDEN_SIZE + Layout.GARDEN_GAP)
	local at = Vector3.new(start.X + side * (Layout.STREET_WIDTH / 2 + Layout.GARDEN_SIZE / 2), 0, z)
	return Layout.facing(at, Vector3.new(start.X, 0, z))
end

-- The middle of a garden's gate (in its front fence, onto the street)
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
-- street sees its owner training
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

-- The pasture's middle and size in the world (the creatures roam inside it)
function Layout.pasture(index: number): (CFrame, Vector3)
	return Layout.garden(index) * CFrame.new(Layout.PASTURE.center), Layout.PASTURE.size
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

-- The Wild (Config/Wild): past the gate at the far (north) end of the street, a road runs on through the
-- biomes one after another, nests on both sides of it. South of the gate is safe.
Layout.BIOME_LENGTH = 140
Layout.WILD_WIDTH = 160
Layout.ROAD_WIDTH = 14

-- The gate into the Wild (the street's far end)
function Layout.wildGate(): Vector3
	local start, length = Layout.street()
	return start + Vector3.new(0, 0, -length)
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
