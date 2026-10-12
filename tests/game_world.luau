-- Builds the new game's world (game/server WorldService) with real Roblox instances (through Lune) to catch
-- wrong property names or classes, and checks the layout. Run from the repo root:  lune run tests/game_world.luau

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./loader")

local Shared = Loader.root("game/shared", "Shared")
local Server = Loader.root("game/server", "Server")

local dataModel = roblox.Instance.new("DataModel")
local workspaceInstance = dataModel:GetService("Workspace")
local replicatedStorage = {
	WaitForChild = function(_self, name)
		assert(name == "Shared", "unexpected WaitForChild " .. tostring(name))
		return Shared
	end,
	FindFirstChild = function()
		return nil
	end,
}
Loader.extraEnv = {
	game = {
		GetService = function(_self, name)
			if name == "ReplicatedStorage" then
				return replicatedStorage
			end
			error("service not stubbed: " .. name)
		end,
	},
	workspace = workspaceInstance,
	-- (a seeded stand-in for Roblox's Random)
	Random = {
		new = function(seed: number)
			local state = seed
			local function nextNumber(): number
				state = (state * 1103515245 + 12345) % 2147483648
				return state / 2147483648
			end
			return {
				NextNumber = function(_self, a: number?, b: number?): number
					return if a and b then a + (b - a) * nextNumber() else nextNumber()
				end,
				NextInteger = function(_self, a: number, b: number): number
					return a + math.floor(nextNumber() * (b - a + 1))
				end,
			}
		end,
	},
}

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local WorldService = Loader.require(Server.Services.WorldService)
local Layout = Loader.require(Shared.Logic.Layout)
local WildConfig = Loader.require(Shared.Config.Wild)
local IslandConfig = Loader.require(Shared.Config.Island)
local PetModel = Loader.require(Shared.PetModel)

local world = WorldService.build()
local gardens, pads, shops, gates = 0, 0, 0, 0
for _, child in world:GetChildren() do
	if string.find(child.Name, "^Island_") then
		gardens += 1
	end
end
for _, d in world:GetDescendants() do
	if d:IsA("BasePart") and d:HasTag("Incubator") then
		pads += 1
	end
	if d:IsA("BasePart") and d:HasTag("Gate") then
		gates += 1
	end
	if d:IsA("ProximityPrompt") and d:GetAttribute("OpenUI") and not d:GetAttribute("Island") then
		shops += 1
	end
end
print(("gardens=%d gates=%d incubators=%d shops=%d"):format(gardens, gates, pads, shops))
assert(gardens == IslandConfig.ISLANDS, "one garden per player")
assert(gates == IslandConfig.ISLANDS, "a gate per garden")
assert(pads == IslandConfig.ISLANDS * #IslandConfig.MACHINE_PRICES, "every incubator in every garden (eggs on the grass get theirs when set down)")
assert(shops == #Layout.SHOP_SPOTS, "a shop on each spot")

-- Every incubator and pen spot lies in its garden; the gardens stand on their arc south of the square, their gates
-- toward it, clear of each other, of the shops and of the road to the Wild
for index = 1, IslandConfig.ISLANDS do
	for slot = 1, IslandConfig.PENS + #IslandConfig.PEN_PRICES do
		assert(Layout.gardenAt(Layout.pen(index, slot)) == index, ("pen %d in garden %d"):format(slot, index))
	end
	-- Nests on the hatchery deck, creatures in the pasture, both off the path
	local frame = Layout.garden(index)
	local function inside(point, area)
		local p = frame:PointToObjectSpace(point) - area.center
		return math.abs(p.X) <= area.size.X / 2 - 1 and math.abs(p.Z) <= area.size.Z / 2 - 1
	end
	-- Front yard (incubators left of the path, barn and trough right), then the hatching field, then the pen (twice as deep)
	local field, pasture = Layout.FIELD, Layout.PASTURE
	assert(Layout.eggSpot(Layout.START_SPOT, 1), "the first egg's spot is in the hatching field")
	assert(not Layout.eggSpot(Vector3.new(0, 0, Layout.GARDEN_SIZE), 1), "not outside the garden")
	assert(not Layout.eggSpot(pasture.center, 1), "no eggs in the pen")
	assert(not Layout.eggSpot(Layout.BARN, 1), "no eggs in the yard")
	assert(field.center.Z + field.size.Z / 2 <= pasture.center.Z - pasture.size.Z / 2, "the field before the pen")
	assert(pasture.size.Z >= 1.9 * field.size.Z and pasture.size.X >= field.size.X, "a pen twice as deep as the field, fence to fence")
	assert(not Layout.eggSpot(pasture.center, 1), "no eggs in the pen")
	assert(not Layout.eggSpot(Vector3.new(0, 0, -5), 1), "no eggs on the path")
	assert(pasture.center.Z + pasture.size.Z / 2 >= Layout.GARDEN_BACK - 3, "the pen reaches the back fence")
	assert(Layout.gardenAt(frame:PointToWorldSpace(Vector3.new(0, 0, Layout.GARDEN_BACK - 1))) == index, "the whole pen is the garden")
	for slot = 1, IslandConfig.PENS + #IslandConfig.PEN_PRICES do
		assert(inside(Layout.pen(index, slot), Layout.PASTURE), ("creature %d in the pen"):format(slot))
		assert(not Layout.blocked(frame:PointToObjectSpace(Layout.pen(index, slot))), "not in the trough or the barn")
	end
	local yardEnd = field.center.Z - field.size.Z / 2
	for k = 1, #IslandConfig.MACHINE_PRICES do
		local spot = frame:PointToObjectSpace(Layout.incubator(index, IslandConfig.MACHINE_SLOT + k))
		assert(spot.X + 3.5 < -Layout.PATH_WIDTH / 2 and spot.Z + 3.5 < yardEnd and spot.Z - 3.5 > -Layout.GARDEN_SIZE / 2, ("incubator %d in the yard, left of the path"):format(k))
	end
	for _, spot in { Layout.TROUGH, Layout.BARN } do
		assert(spot.X - 3 > Layout.PATH_WIDTH / 2 and spot.Z < yardEnd, "the trough and the barn in the yard, right of the path")
	end
	assert((Layout.TROUGH - Layout.BARN).Magnitude > 9, "the trough clear of the barn")
	local center = Layout.garden(index).Position
	local gate = Layout.gate(index).Position
	assert(center.Z > Layout.CENTER.Z, "south of the square")
	assert((center - Layout.SQUARE_CENTER).Magnitude > Layout.SQUARE_RADIUS + Layout.GARDEN_SIZE, "well away from the square")
	assert((gate - Layout.CENTER).Magnitude < (center - Layout.CENTER).Magnitude - Layout.GARDEN_SIZE / 2 + 0.01, "its gate toward the square")
	assert((gate - Layout.CENTER).Magnitude > Layout.GARDEN_ROAD_RADIUS + Layout.ROAD_WIDTH_TOWN / 2, "past the arc road")
	-- (its corners, its treadmill and its pasture grown all the way in nobody else's garden)
	local grown = Layout.pastureGrowth(#IslandConfig.PASTURE_GROWTH)
	local spots = { frame:PointToWorldSpace(Layout.TREADMILL), frame:PointToWorldSpace(Vector3.new(-Layout.GARDEN_SIZE / 2, 0, Layout.GARDEN_BACK + grown)), frame:PointToWorldSpace(Vector3.new(Layout.GARDEN_SIZE / 2, 0, Layout.GARDEN_BACK + grown)) }
	for _, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		table.insert(spots, frame:PointToWorldSpace(corner * (Layout.GARDEN_SIZE / 2 - 0.5)))
	end
	for _, spot in spots do
		local other = Layout.gardenAt(spot)
		assert(other == nil or other == index, ("garden %d runs into garden %s"):format(index, tostring(other)))
	end
	if index > 1 then
		assert(Layout.garden(index).Position.X > Layout.garden(index - 1).Position.X, "from west to east")
	end
end
assert(Layout.gardenAt(Layout.SQUARE_CENTER) == nil, "the square is no garden")
-- The shops: buildings in a straight row in line with the gate, outside its towers, facing the square, a little apart, off every road
local gateZ = Layout.wildGate().Z
for shop = 1, #Layout.SHOP_SPOTS do
	local frame = Layout.shop(shop)
	local at = frame.Position
	assert(math.abs(at.X) > Layout.WILD_WIDTH / 2 + 10 and math.abs(at.Z - gateZ) < 30, "in line with the gate, outside its towers")
	assert(at.Z + Layout.SHOP_WIDTH / 2 < Layout.SQUARE_CENTER.Z - Layout.SQUARE_RADIUS and at.Z - Layout.SHOP_WIDTH / 2 > gateZ, "between the square and the gate")
	assert(frame.LookVector.Z > 0.9, "facing the square")
	assert(Layout.roadDistance(at + frame.LookVector * -Layout.SHOP_DEPTH / 2) > 0, "off the roads")
	assert(Layout.gardenAt(at) == nil, "not in a garden")
	local toStall = at - Layout.SPAWN.Position
	assert(Layout.SPAWN.LookVector:Dot(toStall.Unit) > 0.3, "in front of the spawn")
	for other = shop + 1, #Layout.SHOP_SPOTS do
		assert((Layout.shop(other).Position - at).Magnitude >= Layout.SHOP_WIDTH + 8, "stalls a little apart")
	end
end

-- A creature drawn without the 3D models
local built = PetModel.build({ s = "Cat", v = "Golden", z = "Normal" })
assert(#built.parts > 0 and built.height > 0, "a creature is drawn")

-- A guardian asleep, in each pose: on the ground (not sunk into it, not floating), its eyes shut; awake, as made
local SleepPose = Loader.require(Shared.SleepPose)
for _, pose in { "side", "back", "loaf", "curl", "sit" } do
	local bear = PetModel.build({ s = "Bear", v = "Normal", z = "Huge" })
	local sizes = SleepPose.sizes(bear.parts)
	SleepPose.place(bear, CFrame.new(10, 0, 10), pose, 0, sizes)
	local lowest = math.huge
	for _, p in bear.parts do
		local half = p.Size / 2
		for _, corner in { Vector3.new(-1, -1, -1), Vector3.new(1, -1, -1), Vector3.new(-1, 1, -1), Vector3.new(1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(1, -1, 1), Vector3.new(-1, 1, 1), Vector3.new(1, 1, 1) } do
			lowest = math.min(lowest, (p.CFrame * (half * corner)).Y)
		end
		if p.Name == "Eye" then
			assert(p.Size.Y < sizes[table.find(bear.parts, p) :: number].Y * 0.5, pose .. ": its eyes shut")
		end
	end
	assert(math.abs(lowest) < 0.15, ("%s: on the ground (its lowest point at %.2f)"):format(pose, lowest))
	SleepPose.wake(bear, sizes)
	for i, p in bear.parts do
		assert(p.Size == sizes[i], pose .. ": awake, as made")
	end
end
local WildConfigPoses = WildConfig.SLEEP_POSES
assert(WildConfigPoses.Chicken == "sit" and WildConfig.BIOMES[1].guardian == "Chicken", "the Meadow's guardian: a chicken, asleep sitting")

-- A carried creature is a ball in its rarity's color
local Ball = Loader.require(Shared.Ball)
local ballModel, ballBody = Ball.build("Cat", roblox.CFrame.new(0, 5, 0), false)
assert(#ballModel:GetChildren() >= 3 and ballBody.Name == "Body", "a ball: a body, a belt and a button")
assert(Ball.color("Cat") ~= Ball.color("Dog"), "its rarity's color")

print("world test passed")

-- The Wild: past the street's far end, its biomes one after another, their nests off the road
local gate = Layout.wildGate()
for index = 1, IslandConfig.ISLANDS do
	assert(Layout.garden(index).Position.Z - Layout.GARDEN_SIZE / 2 > gate.Z, "the gardens are before the gate")
	assert(Layout.pastGate(Layout.garden(index).Position), "a garden is safe")
end
for i = 1, #WildConfig.BIOMES do
	assert(Layout.biomeAt(Layout.biome(i), #WildConfig.BIOMES) == i, "a biome is where it says")
	assert(not Layout.pastGate(Layout.biome(i)), "in the Wild")
	-- (scattered by luck in front of the guardian, apart: tried with many seeds)
	for seed = 1, 30 do
		local state = seed
		local spots = Layout.wildNests(i, WildConfig.NESTS, function()
			state = (state * 1103515245 + 12345) % 2147483648
			return state / 2147483648
		end)
		local guardian = Layout.wildGuardian(i)
		for k, nest in spots do
			assert((nest - guardian).Magnitude < 18 and math.abs(nest.X) < math.abs(guardian.X), "in front of its guardian, toward the road")
			for other = k + 1, #spots do
				assert((spots[other] - nest).Magnitude >= 5.6, "nests apart (each one 5.4 across)")
			end
			assert(Layout.biomeAt(nest, #WildConfig.BIOMES) == i, "a scattered nest in its biome")
			assert(math.abs(nest.X) - 4 > Layout.ROAD_WIDTH / 2 and math.abs(nest.X) + 4 < Layout.WILD_WIDTH / 2, "off the road, inside the walls")
		end
	end
	for k = 1, WildConfig.NESTS do
		local nest = Layout.wildNest(i, k, WildConfig.NESTS)
		assert(Layout.biomeAt(nest, #WildConfig.BIOMES) == i, "a nest in its biome")
		assert(math.abs(nest.X) - 4 > Layout.ROAD_WIDTH / 2 and math.abs(nest.X) + 4 < Layout.WILD_WIDTH / 2, "off the road, inside the walls")
	end
end
local wildEggs = 0
for _, d in world.Wild:GetChildren() do
	if d.Name == "WildEgg" then
		wildEggs += 1
	end
end
local openBiomes = 0
for _, biome in WildConfig.BIOMES do
	if biome.tier <= IslandConfig.OPEN_TIER then
		openBiomes += 1
	end
end
assert(wildEggs == openBiomes * WildConfig.NESTS, "an egg in every nest of the open biomes (the others: Coming Soon)")
print("wild test passed")

