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
local islands, pads, shops = 0, 0, 0
for _, child in world:GetChildren() do
	if string.find(child.Name, "^Island_") then
		islands += 1
	end
end
for _, d in world:GetDescendants() do
	if d:IsA("BasePart") and d:HasTag("Incubator") then
		pads += 1
	end
	if d:IsA("ProximityPrompt") and d:GetAttribute("OpenUI") then
		shops += 1
	end
end
local maxPads = IslandConfig.INCUBATORS + #IslandConfig.INCUBATOR_PRICES
print(("islands=%d incubators=%d shops=%d"):format(islands, pads, shops))
assert(islands == IslandConfig.ISLANDS, "one island per player")
assert(pads == IslandConfig.ISLANDS * maxPads, "every incubator on every island")
assert(shops == 6, "six shops")

-- Every incubator and pen spot lies on its island; the islands don't overlap the town or each other
for index = 1, IslandConfig.ISLANDS do
	for slot = 1, maxPads do
		assert(Layout.islandAt(Layout.incubator(index, slot)) == index, ("incubator %d on island %d"):format(slot, index))
	end
	for slot = 1, IslandConfig.PENS + #IslandConfig.PEN_PRICES do
		assert(Layout.islandAt(Layout.pen(index, slot)) == index, ("pen %d on island %d"):format(slot, index))
	end
	local center = Layout.island(index).Position
	assert((center - Layout.CENTER).Magnitude - Layout.ISLAND_SIZE * 0.71 > Layout.TOWN_RADIUS, "clear of the town")
	local nextCenter = Layout.island(index % IslandConfig.ISLANDS + 1).Position
	assert((center - nextCenter).Magnitude > Layout.ISLAND_SIZE * 1.42, "clear of the next island")
end
assert(Layout.islandAt(Layout.CENTER) == nil, "the town is no island")

-- A creature drawn without the 3D models
local built = PetModel.build({ s = "Kitty", v = "Golden", z = "Normal" })
assert(#built.parts > 0 and built.height > 0, "a creature is drawn")

print("world test passed")
