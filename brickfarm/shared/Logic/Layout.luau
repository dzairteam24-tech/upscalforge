--!strict
-- Where things are in the world: farms in a wide ring around the town, each facing it. In a farm's own frame -Z
-- points at the town (its gate is that way). Tiles are named by column and row in the farm's own grid (Logic/Land):
-- columns run across, rows run back from the yard.

local FarmConfig = require(script.Parent.Parent.Config.Farm)

local Layout = {}

Layout.STEP = FarmConfig.TILE + FarmConfig.GAP

-- A farm's frame: its middle on the ground, facing the square
function Layout.farm(index: number): CFrame
	local a = (index - 1) / FarmConfig.FARMS * math.pi * 2
	local at = Vector3.new(math.cos(a) * FarmConfig.RING, 0, math.sin(a) * FarmConfig.RING)
	return CFrame.lookAt(at, Vector3.zero)
end

local HALF = FarmConfig.TERRITORY / 2
local LOT_SIZE = FarmConfig.LOT * Layout.STEP
Layout.LOT_SIZE = LOT_SIZE
local Z0 = -HALF + FarmConfig.YARD -- (where the land starts, behind the yard)

-- A tile's place in its farm's own frame (column tx, row tz; lot 0,0's middle is on the farm's middle line)
local function tileLocal(tx: number, tz: number): (number, number)
	return (tx + 0.5) * Layout.STEP - LOT_SIZE / 2, Z0 + (tz + 0.5) * Layout.STEP
end

-- The middle of a tile's top (on the ground), in the world
function Layout.tile(farm: number, tx: number, tz: number): CFrame
	local x, z = tileLocal(tx, tz)
	return Layout.farm(farm) * CFrame.new(x, 0, z)
end

-- The middle of a lot, on the ground
function Layout.lot(farm: number, cx: number, cz: number): CFrame
	return Layout.farm(farm) * CFrame.new(cx * LOT_SIZE, 0, Z0 + (cz + 0.5) * LOT_SIZE)
end

-- The farm, column and row of the tile under a world position (if it's on some farm's land area)
function Layout.tileAt(position: Vector3): (number?, number?, number?)
	for farm = 1, FarmConfig.FARMS do
		local p = Layout.farm(farm):PointToObjectSpace(position)
		if math.abs(p.X) < HALF and math.abs(p.Z) < HALF and p.Z >= Z0 then
			local tx = math.floor((p.X + LOT_SIZE / 2) / Layout.STEP)
			local tz = math.floor((p.Z - Z0) / Layout.STEP)
			return farm, tx, tz
		end
	end
	return nil, nil, nil
end

-- The barn: in the yard, left of the way in
function Layout.barn(farm: number): CFrame
	return Layout.farm(farm) * CFrame.new(-60, 0, -HALF + 58)
end

-- A point in a farm's own frame, in the world
function Layout.point(farm: number, x: number, z: number): CFrame
	return Layout.farm(farm) * CFrame.new(x, 0, z)
end

-- The middle of the gap in its wall, facing the town
function Layout.gate(farm: number): CFrame
	return Layout.farm(farm) * CFrame.new(0, 0, -HALF)
end

-- The house: in the yard, right of the way in (its door faces the gate)
function Layout.house(farm: number): CFrame
	return Layout.farm(farm) * CFrame.new(60, 0, -HALF + 58)
end

-- The stand where visitors buy: just inside the gate, on the right (facing the way in)
function Layout.stand(farm: number): CFrame
	return Layout.farm(farm) * CFrame.new(22, 0, -HALF + 14) * CFrame.Angles(0, math.pi / 2, 0)
end

-- Where the farm's tractor waits: just inside the gate, on the left
function Layout.tractor(farm: number): CFrame
	return Layout.farm(farm) * CFrame.new(-24, 0, -HALF + 18)
end

-- The town's orders board: on the square
function Layout.board(): CFrame
	return CFrame.new(0, 0, -FarmConfig.TOWN + 14)
end

-- Where its farmer stands when they arrive: in the yard, looking at the land
function Layout.spawn(farm: number): CFrame
	local at = (Layout.farm(farm) * CFrame.new(0, 3, Z0 - 14)).Position
	local ahead = (Layout.farm(farm) * CFrame.new(0, 3, Z0 + 20)).Position
	return CFrame.lookAt(at, ahead)
end

return Layout
