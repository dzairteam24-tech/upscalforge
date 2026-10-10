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
local maxPads = IslandConfig.INCUBATORS + #IslandConfig.INCUBATOR_PRICES
print(("gardens=%d gates=%d incubators=%d shops=%d"):format(gardens, gates, pads, shops))
assert(gardens == IslandConfig.ISLANDS, "one garden per player")
assert(gates == IslandConfig.ISLANDS, "a gate per garden")
assert(pads == IslandConfig.ISLANDS * maxPads, "every incubator in every garden")
assert(shops == #Layout.SHOP_ANGLES, "a shop on each spot")

-- Every incubator and pen spot lies in its garden; the gardens stand on their arc south of the square, their gates
-- toward it, clear of each other, of the shops and of the road to the Wild
for index = 1, IslandConfig.ISLANDS do
	for slot = 1, maxPads do
		assert(Layout.gardenAt(Layout.incubator(index, slot)) == index, ("incubator %d in garden %d"):format(slot, index))
	end
	for slot = 1, IslandConfig.PENS + #IslandConfig.PEN_PRICES do
		assert(Layout.gardenAt(Layout.pen(index, slot)) == index, ("pen %d in garden %d"):format(slot, index))
	end
	-- Nests on the hatchery deck, creatures in the pasture, both off the path
	local frame = Layout.garden(index)
	local function inside(point, area)
		local p = frame:PointToObjectSpace(point) - area.center
		return math.abs(p.X) <= area.size.X / 2 - 1 and math.abs(p.Z) <= area.size.Z / 2 - 1
	end
	for slot = 1, maxPads do
		local spot = Layout.incubator(index, slot)
		assert(inside(spot, Layout.HATCHERY), ("nest %d on the hatchery deck"):format(slot))
		assert(math.abs(frame:PointToObjectSpace(spot).X) - 2.2 >= Layout.PATH_WIDTH / 2, "nests off the path")
		for other = slot + 1, maxPads do
			assert((spot - Layout.incubator(index, other)).Magnitude >= 4.6, "nests don't touch")
		end
	end
	local hatchery, pasture = Layout.HATCHERY, Layout.PASTURE
	assert(hatchery.center.Z + hatchery.size.Z / 2 <= pasture.center.Z - pasture.size.Z / 2, "the hatchery before the pasture")
	assert(pasture.size.X * pasture.size.Z >= 1900, "a roomy pasture")
	assert(pasture.center.Z + pasture.size.Z / 2 >= Layout.GARDEN_SIZE / 2 - 3, "the pasture reaches the back fence")
	for slot = 1, IslandConfig.PENS + #IslandConfig.PEN_PRICES do
		assert(inside(Layout.pen(index, slot), Layout.PASTURE), ("creature %d in the pasture"):format(slot))
		local p = frame:PointToObjectSpace(Layout.pen(index, slot)) - Layout.POND.center
		assert(Vector3.new(p.X, 0, p.Z).Magnitude > Layout.POND.radius + 2, "not in the pond")
		assert(not Layout.blocked(frame:PointToObjectSpace(Layout.pen(index, slot))), "not in the trough or the barn")
	end
	assert(inside(frame:PointToWorldSpace(Layout.TROUGH), Layout.PASTURE) and inside(frame:PointToWorldSpace(Layout.BARN), Layout.PASTURE), "the trough and the barn in the pasture")
	assert(math.abs(Layout.TROUGH.X) - 3 >= Layout.PATH_WIDTH / 2, "the trough off the path")
	local center = Layout.garden(index).Position
	local gate = Layout.gate(index).Position
	assert(center.Z > Layout.CENTER.Z + Layout.SQUARE_RADIUS, "south of the square")
	assert((gate - Layout.CENTER).Magnitude < (center - Layout.CENTER).Magnitude - Layout.GARDEN_SIZE / 2 + 0.01, "its gate toward the square")
	assert((gate - Layout.CENTER).Magnitude > Layout.GARDEN_ROAD_RADIUS + Layout.ROAD_WIDTH_TOWN / 2, "past the arc road")
	-- (its corners and its treadmill in nobody else's garden)
	local spots = { frame:PointToWorldSpace(Layout.TREADMILL) }
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
assert(Layout.gardenAt(Layout.CENTER) == nil, "the square is no garden")
-- The shops: on their arc north of the square, facing it, clear of the road to the Wild and of each other
for shop = 1, #Layout.SHOP_ANGLES do
	local frame = Layout.shop(shop)
	local at = frame.Position
	assert(at.Z < Layout.CENTER.Z - Layout.SQUARE_RADIUS, "north of the square")
	assert(math.abs(at.X) - Layout.SHOP_DEPTH / 2 >= Layout.ROAD_WIDTH_TOWN / 2, "off the road to the Wild")
	assert((frame * CFrame.new(0, 0, -10)).Position.Magnitude < at.Magnitude, "facing the square")
	assert(Layout.gardenAt(at) == nil, "not in a garden")
	for other = shop + 1, #Layout.SHOP_ANGLES do
		assert((Layout.shop(other).Position - at).Magnitude >= Layout.SHOP_DEPTH + 10, "shops apart")
	end
end

-- A creature drawn without the 3D models
local built = PetModel.build({ s = "Kitty", v = "Golden", z = "Normal" })
assert(#built.parts > 0 and built.height > 0, "a creature is drawn")

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
	for k = 1, WildConfig.NESTS do
		local nest = Layout.wildNest(i, k)
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
assert(wildEggs == #WildConfig.BIOMES * WildConfig.NESTS, "an egg in every nest")
print("wild test passed")
