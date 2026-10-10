--!strict
-- Where everything is: one street, walked from south to north. Players arrive in a small square with a fountain;
-- the street leaves it northward past the six shops, three each side facing each other (the Egg Shop first,
-- nearest the square), then past the players' gardens, also in two rows facing each other, so everyone sees
-- their neighbours. Each garden is fenced, with a laser gate onto the street (Config/Raid).

local IslandConfig = require(script.Parent.Parent.Config.Island)

local Layout = {
	SQUARE_RADIUS = 26, -- the square where players arrive
	SHOP_DEPTH = 26, -- a shop's lot, from the street back
	SHOP_SPACING = 30, -- between two shops' middles along the street
	GARDEN_SIZE = 60,
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

-- Inside a garden (its frame's space, front -Z toward the gate): the path runs from the gate up the middle to
-- the nest house at the back. The pasture, where the creatures roam, takes the whole of one side; on the other,
-- the hatchery: a round floor with the nests in a ring round a warm lamp.
Layout.PASTURE = { center = Vector3.new(-16, 0, -1), size = Vector3.new(24, 0, 52) }
Layout.HATCHERY = { center = Vector3.new(16, 0, 1), radius = 11, ring = 7 }
Layout.HOUSE = Vector3.new(0, 0, 24)
Layout.PATH_WIDTH = 6

-- A nest's spot (an incubator) in a garden: on the hatchery's ring, the first (the safe one) nearest the path
function Layout.incubator(index: number, slot: number): Vector3
	local count = IslandConfig.INCUBATORS + #IslandConfig.INCUBATOR_PRICES
	local angle = (slot - 1) * 2 * math.pi / count
	local inside = Layout.HATCHERY.center + Vector3.new(-math.cos(angle), 0, math.sin(angle)) * Layout.HATCHERY.ring
	return Layout.garden(index):PointToWorldSpace(inside)
end

-- The pasture's middle and size in the world (the creatures roam inside it)
function Layout.pasture(index: number): (CFrame, Vector3)
	return Layout.garden(index) * CFrame.new(Layout.PASTURE.center), Layout.PASTURE.size
end

-- Where a creature living in the garden starts (spread over the pasture; it wanders from there)
function Layout.pen(index: number, slot: number): Vector3
	local column = (slot - 1) % 3
	local row = (slot - 1) // 3
	local inside = Layout.PASTURE.center + Vector3.new((column - 1) * 7, 0, 18 - row * 12)
	return Layout.garden(index):PointToWorldSpace(inside)
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
