-- Builds the World 1 map and coin sources with real Roblox instances (through Lune) to catch
-- wrong property names or classes. Run from the repo root:  lune run tests/smoke_world.luau

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./loader")

local Shared = Loader.root("roblox/shared", "Shared")
local Server = Loader.root("roblox/server", "Server")

local dataModel = roblox.Instance.new("DataModel")
local workspaceInstance = dataModel:GetService("Workspace")

-- Minimal stand-ins for engine APIs that Lune doesn't provide
local replicatedStorage = {
	WaitForChild = function(_self, name)
		assert(name == "Shared", "unexpected WaitForChild " .. tostring(name))
		return Shared
	end,
}
local fakeGame = {
	GetService = function(_self, name)
		if name == "ReplicatedStorage" then
			return replicatedStorage
		end
		error("service not stubbed: " .. name)
	end,
}
local Random = {
	new = function(seed)
		local state = seed or 1
		local function next()
			state = (state * 16807) % 2147483647
			return state / 2147483647
		end
		return {
			NextNumber = function(_self, min, max)
				min = min or 0
				max = max or 1
				return min + (max - min) * next()
			end,
			NextInteger = function(_self, min, max)
				return min + math.floor(next() * (max - min + 1))
			end,
		}
	end,
}

Loader.extraEnv = { game = fakeGame, workspace = workspaceInstance, Random = Random }

local WorldBuilder = Loader.require(Server.Services.WorldBuilder)
local BreakableService = Loader.require(Server.Services.BreakableService)

local world = WorldBuilder.build()
BreakableService.build()

local zones, gates, eggs = 0, 0, 0
for _, child in world:GetChildren() do
	if string.find(child.Name, "^Zone_") then
		zones += 1
	elseif string.find(child.Name, "^Gate_") then
		gates += 1
	end
end
for zoneId in WorldBuilder.eggPositions do
	eggs += 1
end
local sources = #workspaceInstance:FindFirstChild("Breakables"):GetChildren()

-- A Big and a guardian (Titan) built with real instances
local Vector3 = roblox.Vector3
local big = BreakableService.spawnSpecial(1, "Big", { s = "Kitty", v = "Lava", z = "Big" }, Vector3.new(20, 0, 20), 1000, 180)
local guardian = BreakableService.spawnSpecial(1, "Guardian", { s = "Bear", v = "Normal", z = "Titan" }, Vector3.new(-20, 0, 20), 10000, 300)
assert(big.part:FindFirstChildOfClass("Model"), "Big has a model")
assert(#BreakableService.specials() == 2, "two specials")
assert(#BreakableService.aliveInZone(1) == 24, "specials are not in the instant-break list")
BreakableService.despawn(big)
BreakableService.despawn(guardian)
assert(#BreakableService.specials() == 0, "despawned")

print(("zones=%d gates=%d eggs=%d sources=%d"):format(zones, gates, eggs, sources))
local ok = zones == 11 and gates == 12 and eggs == 10 and sources == 10 * 24
if not ok then
	print("FAIL: unexpected world shape")
	process.exit(1)
end
print("world smoke test passed")
