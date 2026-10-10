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
	FENCE_HEIGHT = 10, -- (too tall to jump)
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

-- An incubator's spot in a garden: a row along the back, away from the gate
function Layout.incubator(index: number, slot: number): Vector3
	local count = IslandConfig.INCUBATORS + #IslandConfig.INCUBATOR_PRICES
	local across = (slot - (count + 1) / 2) * 6.5
	return (Layout.garden(index) * CFrame.new(across, 0, Layout.GARDEN_SIZE / 2 - 9)).Position
end

-- Where a creature living in the garden stands (rows of four between the gate and the incubators)
function Layout.pen(index: number, slot: number): Vector3
	local column = (slot - 1) % 4
	local row = (slot - 1) // 4
	return (Layout.garden(index) * CFrame.new((column - 1.5) * 11, 0, -12 + row * 10)).Position
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
