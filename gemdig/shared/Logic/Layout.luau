--!strict
-- Where everything is: the town in the middle, and a plot with a mine for each player in a ring around it.
-- A mine's cubes are addressed (x, layer, z): x and z in 1..WIDTH, layer 1 at the surface, going down.

local Config = script.Parent.Parent.Config
local Game = require(Config.Game)
local MineConfig = require(Config.Mine)

local Layout = {}

Layout.RING = 170 -- studs from the town to each plot
Layout.PLOT = 52 -- a plot's platform is this wide
Layout.HUB = 90 -- the town's platform is this wide

local SHAFT = MineConfig.CELL * MineConfig.WIDTH

function Layout.shaftSize(): number
	return SHAFT
end

-- The middle of a plot's mine, at ground level (the top of layer 1)
function Layout.plotCenter(index: number): Vector3
	local angle = (index - 1) / Game.MAX_PLAYERS * 2 * math.pi
	return Vector3.new(math.cos(angle) * Layout.RING, 0, math.sin(angle) * Layout.RING)
end

-- The middle of a cube
function Layout.cellCenter(index: number, x: number, layer: number, z: number): Vector3
	local mid = (MineConfig.WIDTH + 1) / 2
	local cell = MineConfig.CELL
	return Layout.plotCenter(index) + Vector3.new((x - mid) * cell, -(layer - 0.5) * cell, (z - mid) * cell)
end

-- The cube a point is in: x, layer, z, or nil if it's outside the shaft
function Layout.cellAt(index: number, position: Vector3): (number?, number?, number?)
	local local_ = position - Layout.plotCenter(index)
	local cell = MineConfig.CELL
	local mid = (MineConfig.WIDTH + 1) / 2
	local x = math.floor(local_.X / cell + mid + 0.5)
	local z = math.floor(local_.Z / cell + mid + 0.5)
	local layer = math.floor(-local_.Y / cell) + 1
	if x < 1 or x > MineConfig.WIDTH or z < 1 or z > MineConfig.WIDTH or layer < 1 then
		return nil, nil, nil
	end
	return x, layer, z
end

-- Where a player stands on their plot beside the mine
function Layout.plotSpawn(index: number): Vector3
	local center = Layout.plotCenter(index)
	local toTown = (Vector3.zero - center) * Vector3.new(1, 0, 1)
	local direction = if toTown.Magnitude > 0 then toTown.Unit else Vector3.new(1, 0, 0)
	return center + direction * (SHAFT / 2 + 9) + Vector3.new(0, 4, 0)
end

-- The town's spawn
function Layout.hubSpawn(): Vector3
	return Vector3.new(0, 4, 0)
end

return Layout
