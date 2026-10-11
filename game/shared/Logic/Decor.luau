--!strict
-- Where the map's decor goes (PropService draws it with the props in Config/PropLooks): the same every server.
--   * The square: flower planters and benches round its edge, facing in.
--   * Street lamps along both sides of every road.
--   * The town's open grass: meadow and flower props scattered over it, clear of the roads, the gardens, the shops
--     and the gate into the Wild.
--   * A forest round the town's edges (hiding its invisible walls), open where the Wild begins.
--   * The Wild: each biome scattered with its own props (Config/Wild theme), clear of the road, the nests and the
--     sign, and a row of its tall props down each side as a wall.
-- A spot names a prop (`name`), or a zone to pick from (`zone`, only tall props when `tall`).

local IslandConfig = require(script.Parent.Parent.Config.Island)
local WildConfig = require(script.Parent.Parent.Config.Wild)
local Layout = require(script.Parent.Layout)

export type Spot = { at: Vector3, yaw: number, scale: number, name: string?, zone: number?, tall: boolean? }

local Decor = {}

local HALF = Layout.GARDEN_SIZE / 2
local GROWN = IslandConfig.PASTURE_GROWTH[#IslandConfig.PASTURE_GROWTH]

-- Whether a spot on the town's grass is free for decor (`room`: how much space the prop needs round it)
function Decor.clearInTown(point: Vector3, room: number): boolean
	local half, north, south = Layout.ground()
	if math.abs(point.X - Layout.CENTER.X) > half - room or point.Z < north + room or point.Z > south - room then
		return false
	end
	if (Vector3.new(point.X, 0, point.Z) - Layout.CENTER).Magnitude < Layout.SQUARE_RADIUS + room + 2 then
		return false
	end
	if Layout.roadDistance(point) < room + 2 then
		return false
	end
	-- (a garden, its treadmill in front, and its pasture grown all the way back)
	for index = 1, IslandConfig.ISLANDS do
		local inside = Layout.garden(index):PointToObjectSpace(point)
		if math.abs(inside.X) < HALF + room + 3 and inside.Z > -HALF - 12 - room and inside.Z < HALF + GROWN + room + 3 then
			return false
		end
	end
	for index = 1, #Layout.SHOP_ANGLES do
		local lot = (Layout.shop(index) * CFrame.new(0, 0, 4)).Position
		if (lot - point).Magnitude < Layout.SHOP_DEPTH + room then
			return false
		end
	end
	if (Layout.wildGate() - point).Magnitude < 45 + room then
		return false
	end
	return true
end

-- Whether a spot in a biome of the Wild is free for decor
function Decor.clearInWild(i: number, point: Vector3, room: number): boolean
	local gate = Layout.wildGate()
	if math.abs(point.X - gate.X) < Layout.ROAD_WIDTH / 2 + room + 3 then
		return false
	end
	if math.abs(point.X - gate.X) > Layout.WILD_WIDTH / 2 - room - 1 then
		return false
	end
	if Layout.biomeAt(point, #WildConfig.BIOMES) ~= i then
		return false
	end
	if gate.Z - point.Z < 30 + room then -- (the gate's towers)
		return false
	end
	for k = 1, WildConfig.NESTS do
		if (Layout.wildNest(i, k) - point).Magnitude < 12 + room then
			return false
		end
	end
	local center = Layout.biome(i)
	local sign = center + Vector3.new(Layout.ROAD_WIDTH / 2 + 2, 0, Layout.BIOME_LENGTH / 2 - 2)
	return (sign - point).Magnitude > 8 + room
end

local function yawTo(from: Vector3, to: Vector3): number
	local d = to - from
	return math.atan2(-d.X, -d.Z)
end

function Decor.town(): { Spot }
	local rng = Random.new(2024)
	local spots: { Spot } = {}
	local half, north, south = Layout.ground()
	-- The square's edge: planters and benches, but not where a road comes in
	local count = 16
	for k = 0, count - 1 do
		local degrees = k * 360 / count + 360 / count / 2
		local at = Layout.around(Layout.SQUARE_RADIUS + 1.5, degrees)
		if Layout.roadDistance(at) > 3 then
			table.insert(spots, { at = at, yaw = yawTo(at, Layout.CENTER), scale = 1, name = if k % 2 == 0 then "FlowerPlanter" else "Bench" })
		end
	end
	-- Street lamps along the roads, both sides
	local roads, arcs = Layout.roads()
	local placed: { Vector3 } = {}
	local function lamp(at: Vector3, facing: Vector3)
		for _, other in placed do
			if (other - at).Magnitude < 14 then
				return
			end
		end
		if Layout.roadDistance(at) < 1 or (Vector3.new(at.X, 0, at.Z) - Layout.CENTER).Magnitude < Layout.SQUARE_RADIUS + 3 then
			return
		end
		for index = 1, IslandConfig.ISLANDS do
			if Layout.gardenAt(at) == index then
				return
			end
		end
		table.insert(placed, at)
		table.insert(spots, { at = at, yaw = yawTo(at, facing), scale = 0.85, name = "StreetLamp" })
	end
	for _, r in roads do
		local along = Vector3.new(r.b.X - r.a.X, 0, r.b.Z - r.a.Z)
		local length = along.Magnitude
		if length < 30 then
			continue
		end
		local dir = along.Unit
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local steps = math.floor(length / 36)
		for s = 1, steps do
			local mid = r.a + dir * (length * s / (steps + 1))
			for _, sign in { -1, 1 } do
				local at = mid + side * sign * (r.width / 2 + 2.5)
				lamp(at, mid)
			end
		end
	end
	for _, a in arcs do
		local span = a.to - a.from
		local steps = math.floor(math.rad(span) * a.radius / 40)
		for s = 0, steps - 1 do
			local degrees = a.from + span * (s + 0.5) / steps
			for _, sign in { -1, 1 } do
				local at = Layout.around(a.radius + sign * (a.width / 2 + 2.5), degrees)
				lamp(at, Layout.around(a.radius, degrees))
			end
		end
	end
	-- The open grass: a jittered grid of meadow and flower props
	local step = 30
	for x = -half + step / 2, half - step / 2, step do
		for z = north + step / 2, south - step / 2, step do
			local at = Vector3.new(x + rng:NextNumber(-10, 10), 0, z + rng:NextNumber(-10, 10))
			if rng:NextNumber() < 0.75 and Decor.clearInTown(at, 6) then
				table.insert(spots, { at = at, yaw = rng:NextNumber(0, math.pi * 2), scale = rng:NextNumber(0.55, 0.9), zone = if rng:NextNumber() < 0.6 then 1 else 2 })
			end
		end
	end
	-- The forest round the edges (open in the middle of the north edge, onto the Wild)
	local function tree(at: Vector3)
		if math.abs(at.X - Layout.CENTER.X) < Layout.WILD_WIDTH / 2 + 4 and at.Z < north + 20 then
			return
		end
		table.insert(spots, { at = at, yaw = rng:NextNumber(0, math.pi * 2), scale = rng:NextNumber(0.95, 1.35), zone = if rng:NextNumber() < 0.5 then 1 else 3, tall = true })
	end
	for _, inset in { 5, 15 } do
		local gap = if inset == 5 then 16 else 24
		local shift = if inset == 5 then 0 else gap / 2
		for x = -half + inset + shift, half - inset, gap do
			tree(Vector3.new(x + rng:NextNumber(-3, 3), 0, north + inset))
			tree(Vector3.new(x + rng:NextNumber(-3, 3), 0, south - inset))
		end
		for z = north + inset + gap + shift, south - inset - gap, gap do
			tree(Vector3.new(-half + inset, 0, z + rng:NextNumber(-3, 3)))
			tree(Vector3.new(half - inset, 0, z + rng:NextNumber(-3, 3)))
		end
	end
	return spots
end

function Decor.wild(): { Spot }
	local rng = Random.new(77)
	local spots: { Spot } = {}
	local gate = Layout.wildGate()
	for i, biome in WildConfig.BIOMES do
		local center = Layout.biome(i)
		-- Scattered over the biome
		local step = 20
		for x = -Layout.WILD_WIDTH / 2 + step / 2, Layout.WILD_WIDTH / 2 - step / 2, step do
			for z = -Layout.BIOME_LENGTH / 2 + step / 2, Layout.BIOME_LENGTH / 2 - step / 2, step do
				local at = Vector3.new(center.X + x + rng:NextNumber(-7, 7), 0, center.Z + z + rng:NextNumber(-7, 7))
				if rng:NextNumber() < 0.55 and Decor.clearInWild(i, at, 4) then
					table.insert(spots, { at = at, yaw = rng:NextNumber(0, math.pi * 2), scale = rng:NextNumber(0.6, 1), zone = biome.theme })
				end
			end
		end
		-- A wall of its tall props down each side
		for z = -Layout.BIOME_LENGTH / 2 + 6, Layout.BIOME_LENGTH / 2 - 6, 13 do
			for _, side in { -1, 1 } do
				local at = Vector3.new(gate.X + side * (Layout.WILD_WIDTH / 2 - 4), 0, center.Z + z + rng:NextNumber(-2, 2))
				if gate.Z - at.Z > 26 then
					table.insert(spots, { at = at, yaw = rng:NextNumber(0, math.pi * 2), scale = rng:NextNumber(1, 1.4), zone = biome.theme, tall = true })
				end
			end
		end
	end
	return spots
end

return Decor
