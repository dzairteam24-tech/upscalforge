--!strict
-- Where things are in the world: farms in a wide ring around the town, each facing it. In a farm's own frame -Z
-- points at the town (its gate is that way); tile 1 is at the front left, tiles go along the front row first, then back.

local FarmConfig = require(script.Parent.Parent.Config.Farm)

local Layout = {}

Layout.STEP = FarmConfig.TILE + FarmConfig.GAP

-- A farm's frame: its middle on the ground, facing the square
function Layout.farm(index: number): CFrame
	local a = (index - 1) / FarmConfig.FARMS * math.pi * 2
	local at = Vector3.new(math.cos(a) * FarmConfig.RING, 0, math.sin(a) * FarmConfig.RING)
	return CFrame.lookAt(at, Vector3.zero)
end

-- Column and row (1-based) of a tile number
function Layout.cell(tile: number): (number, number)
	local column = (tile - 1) % FarmConfig.COLUMNS + 1
	local row = (tile - 1) // FarmConfig.COLUMNS + 1
	return column, row
end

-- The middle of a tile's top (on the ground), in the world
function Layout.tile(farm: number, tile: number): CFrame
	local column, row = Layout.cell(tile)
	local x = (column - (FarmConfig.COLUMNS + 1) / 2) * Layout.STEP
	local z = (row - (FarmConfig.ROWS + 1) / 2) * Layout.STEP
	return Layout.farm(farm) * CFrame.new(x, 0, z)
end

-- The barn, behind the tiles
function Layout.barn(farm: number): CFrame
	return Layout.farm(farm) * CFrame.new(-FarmConfig.COLUMNS * Layout.STEP / 2 - 12, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0) -- (its door faces the tiles)
end

local HALF = FarmConfig.ENCLOSURE / 2

-- A point in a farm's own frame, in the world
function Layout.point(farm: number, x: number, z: number): CFrame
	return Layout.farm(farm) * CFrame.new(x, 0, z)
end

-- The middle of the gap in its wall, facing the town
function Layout.gate(farm: number): CFrame
	return Layout.farm(farm) * CFrame.new(0, 0, -HALF)
end

-- The house: behind the land, on the right
function Layout.house(farm: number): CFrame
	return Layout.farm(farm) * CFrame.new(38, 0, 46) -- (its door faces the gate)
end

-- The stand where visitors buy: just inside the gate, on the right
function Layout.stand(farm: number): CFrame
	return Layout.farm(farm) * CFrame.new(22, 0, -HALF + 14) * CFrame.Angles(0, math.pi / 2, 0) -- (facing the way in)
end

-- Where the farm's tractor waits: just inside the gate, on the left
function Layout.tractor(farm: number): CFrame
	return Layout.farm(farm) * CFrame.new(-24, 0, -HALF + 18)
end

-- The town's orders board: on the square, facing the way most people come in
function Layout.board(): CFrame
	return CFrame.new(0, 0, -FarmConfig.TOWN + 14)
end

-- Where its farmer stands when they arrive: in front of the tiles, looking at them
function Layout.spawn(farm: number): CFrame
	local frame = Layout.farm(farm)
	local at = (frame * CFrame.new(0, 3, -FarmConfig.ROWS * Layout.STEP / 2 - 8)).Position
	return CFrame.lookAt(at, Vector3.new(frame.Position.X, at.Y, frame.Position.Z))
end

-- The farm (index) and tile under a world position, if any
function Layout.tileAt(position: Vector3): (number?, number?)
	for farm = 1, FarmConfig.FARMS do
		local p = Layout.farm(farm):PointToObjectSpace(position)
		local column = math.floor(p.X / Layout.STEP + FarmConfig.COLUMNS / 2) + 1
		local row = math.floor(p.Z / Layout.STEP + FarmConfig.ROWS / 2) + 1
		if column >= 1 and column <= FarmConfig.COLUMNS and row >= 1 and row <= FarmConfig.ROWS then
			return farm, (row - 1) * FarmConfig.COLUMNS + column
		end
	end
	return nil, nil
end

return Layout
