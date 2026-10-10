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
local WorldService = Loader.require(Server.Services.WorldService)
local Layout = Loader.require(Shared.Logic.Layout)
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
	if d:IsA("ProximityPrompt") and d:GetAttribute("OpenUI") then
		shops += 1
	end
end
local maxPads = IslandConfig.INCUBATORS + #IslandConfig.INCUBATOR_PRICES
print(("gardens=%d gates=%d incubators=%d shops=%d"):format(gardens, gates, pads, shops))
assert(gardens == IslandConfig.ISLANDS, "one garden per player")
assert(gates == IslandConfig.ISLANDS, "a gate per garden")
assert(pads == IslandConfig.ISLANDS * maxPads, "every incubator in every garden")
assert(shops == 6, "six shops")

-- Every incubator and pen spot lies in its garden; the gardens face each other across the street, clear of
-- it, of the plaza and of each other; each gate opens onto the street
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
		assert(inside(Layout.incubator(index, slot), Layout.HATCHERY), ("nest %d on the deck"):format(slot))
	end
	for slot = 1, IslandConfig.PENS + #IslandConfig.PEN_PRICES do
		assert(inside(Layout.pen(index, slot), Layout.PASTURE), ("creature %d in the pasture"):format(slot))
	end
	local center = Layout.garden(index).Position
	assert(math.abs(center.X) - Layout.GARDEN_SIZE / 2 >= Layout.STREET_WIDTH / 2, "clear of the street")
	for shop = 1, 6 do
		local s = Layout.shop(shop).Position
		assert(center.Z + Layout.GARDEN_SIZE / 2 < s.Z - Layout.SHOP_SPACING / 2, "north of the shops")
	end
	local gate = Layout.gate(index).Position
	assert(math.abs(math.abs(gate.X) - Layout.STREET_WIDTH / 2) < 0.01, "the gate is on the street")
	if index % 2 == 1 then
		local across = Layout.garden(index + 1).Position
		assert(math.abs(across.Z - center.Z) < 0.01 and across.X > 0 and center.X < 0, "facing its neighbour across the street")
	end
	for other = index + 1, IslandConfig.ISLANDS do
		local d = Layout.garden(other).Position - center
		assert(math.max(math.abs(d.X), math.abs(d.Z)) >= Layout.GARDEN_SIZE, "gardens don't overlap")
	end
end
assert(Layout.gardenAt(Layout.CENTER) == nil, "the square is no garden")
-- The shops: three each side of the street, facing each other, the Egg Shop first (nearest the square)
for shop = 1, 6 do
	local at = Layout.shop(shop).Position
	assert(math.abs(at.X) - Layout.SHOP_DEPTH / 2 >= Layout.STREET_WIDTH / 2 - 0.01, "beside the street")
	assert(at.Z < Layout.CENTER.Z - Layout.SQUARE_RADIUS + 4, "north of the square")
	assert(Layout.gardenAt(at) == nil, "not in a garden")
end
assert(Layout.shop(1).Position.Z > Layout.shop(6).Position.Z, "the Egg Shop is nearest the square")

-- A creature drawn without the 3D models
local built = PetModel.build({ s = "Kitty", v = "Golden", z = "Normal" })
assert(#built.parts > 0 and built.height > 0, "a creature is drawn")

print("world test passed")
