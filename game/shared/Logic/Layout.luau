--!strict
-- Where everything is. The town is a small round plaza with the six shops round a fountain. From it a street
-- runs north with the players' gardens in two rows facing each other across it, so everyone sees their
-- neighbours. Each garden is fenced, with a laser gate onto the street (Config/Raid).

local IslandConfig = require(script.Parent.Parent.Config.Island)

local Layout = {
	TOWN_RADIUS = 64,
	SHOP_RADIUS = 42, -- the shops' middles
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

-- A shop's spot (1..6) round the fountain, facing it. (The street leaves the plaza between shops 6 and 1.)
function Layout.shop(index: number): CFrame
	local angle = math.rad((index - 0.5) * 360 / SHOPS)
	local at = Layout.CENTER + Vector3.new(math.sin(angle), 0, -math.cos(angle)) * Layout.SHOP_RADIUS
	return Layout.facing(at, Layout.CENTER)
end

-- Where the street starts (the plaza's north edge) and how long it is
function Layout.street(): (Vector3, number)
	local start = Layout.CENTER + Vector3.new(0, 0, -Layout.TOWN_RADIUS + 6)
	local length = ROWS * (Layout.GARDEN_SIZE + Layout.GARDEN_GAP) + 10
	return start, length
end

-- A garden's middle, its front (-Z) facing the street. Odd ones west of the street, even ones east, from the
-- plaza northward.
function Layout.garden(index: number): CFrame
	local side = if index % 2 == 1 then -1 else 1
	local row = (index - 1) // 2
	local start = Layout.street()
	local z = start.Z - Layout.GARDEN_GAP - Layout.GARDEN_SIZE / 2 - row * (Layout.GARDEN_SIZE + Layout.GARDEN_GAP)
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
