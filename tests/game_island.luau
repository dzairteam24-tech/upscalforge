-- Runs the garden's server code (IslandService, with WorldService's world) through Lune with stand-ins for the
-- engine services, to catch what only shows when it runs: a new player's first egg, the eggs in the inventory,
-- an egg from the Wild arriving home. Run from the repo root:  lune run tests/game_island.luau

local roblox = require("@lune/roblox")
local Loader = require("./loader")
local task = require("@lune/task")

local Shared = Loader.root("game/shared", "Shared")
local Server = Loader.root("game/server", "Server")

local dataModel = roblox.Instance.new("DataModel")
local workspaceInstance = dataModel:GetService("Workspace")

local function signal()
	return { Connect = function() return { Disconnect = function() end } end }
end
local remotes = {}
local function remote(name)
	remotes[name] = remotes[name] or { Name = name, FireClient = function() end, FireAllClients = function() end, OnServerEvent = signal(), OnClientEvent = signal() }
	return remotes[name]
end
local remotesFolder = { WaitForChild = function(_self, name) return remote(name) end, FindFirstChild = function(_self, name) return remote(name) end }
local replicatedStorage = {
	WaitForChild = function(_self, name)
		if name == "Shared" then
			return Shared
		end
		return remotesFolder
	end,
	FindFirstChild = function(_self, name)
		return if name == "Remotes" then remotesFolder else nil
	end,
	GetChildren = function()
		return {}
	end,
	ChildAdded = signal(),
}

-- A player: a Folder (for attributes and a Backpack) behind a few Player fields
local folder = roblox.Instance.new("Folder")
local backpack = roblox.Instance.new("Backpack")
backpack.Parent = folder
local character = roblox.Instance.new("Model")
local root = roblox.Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Parent = character
local player = setmetatable({ UserId = 1, DisplayName = "Tester", Name = "Tester", Character = character, Parent = true, ChildAdded = signal(), CharacterAdded = { Connect = signal().Connect, Wait = function() return coroutine.yield() end } }, {
	__index = function(_self, key)
		local value = (folder :: any)[key]
		if type(value) == "function" then
			return function(_, ...)
				return value(folder, ...)
			end
		end
		return value
	end,
})
local players = { GetPlayers = function() return { player } end, PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayerByUserId = function() return player end }

-- (Lune's instances have no events: a tool's Activated is kept here, to fire by hand)
local activated: { { tool: any, fn: () -> () } } = {}
local function onActivated(tool)
	for _, entry in activated do
		if entry.tool == tool then
			return entry.fn
		end
	end
	return nil
end
Loader.transform = function(_path, source)
	source = source:gsub("([%w_]+)%.Activated:Connect%(", "__activated(%1, ")
	source = source:gsub("character:WaitForChild%(", "character:FindFirstChild(")
	return source
end

Loader.extraEnv = {
	__activated = function(tool, fn)
		table.insert(activated, { tool = tool, fn = fn })
	end,
	game = {
		GetService = function(_self, name)
			if name == "ReplicatedStorage" then
				return replicatedStorage
			elseif name == "Players" then
				return players
			elseif name == "RunService" then
				return { IsServer = function() return false end, IsStudio = function() return false end, Heartbeat = signal(), Stepped = signal() }
			elseif name == "DataStoreService" then
				return { GetDataStore = function() error("no DataStore in tests") end }
			elseif name == "ProximityPromptService" then
				return { PromptTriggered = signal() }
			end
			error("service not stubbed: " .. name)
		end,
		BindToClose = function() end,
		PrivateServerId = "",
		PrivateServerOwnerId = 0,
	},
	workspace = workspaceInstance,
	warn = function() end,
	Random = { new = function() return { NextNumber = function(_self, a, b) return (a or 0) + ((b or 1) - (a or 0)) * math.random() end, NextInteger = function(_self, a, b) return math.random(a, b) end } end },
	task = task,
	tick = os.clock,
	typeof = function(v) return typeof(v) end,
}

local WorldService = Loader.require(Server.Services.WorldService)
WorldService.build()
local DataService = Loader.require(Server.Services.DataService)
local IslandService = Loader.require(Server.Services.IslandService)
IslandService.init()
DataService.init() -- (loads the player: their garden, their first egg)
task.wait(0.2)

local data = assert(DataService.get(player :: any), "the player's data loaded")
assert(data.incubating["1"], "a new player's first egg is in their garden")
local island = WorldService.island(1)
local pads = 0
for _, d in (island :: any).Eggs:GetChildren() do
	pads += 1
	assert(d:GetAttribute("Tier") == 1, "the first egg's pad shows it")
end
assert(pads == 1, "one egg on the grass")

-- Eggs held show in the inventory, one tool per kind
data.eggs["1"] = 2
data.golden["3"] = 1
IslandService.push(player :: any)
local tools = {}
for _, tool in backpack:GetChildren() do
	tools[tool:GetAttribute("EggKind")] = tool.Name
end
assert(tools["1"] == "Meadow Egg ×2", "two Meadow Eggs in the inventory: " .. tostring(tools["1"]))
assert(tools["g3"], "the Golden Forest Egg too")
data.eggs["1"] = 0
IslandService.push(player :: any)
for _, tool in backpack:GetChildren() do
	assert(tool:GetAttribute("EggKind") ~= "1", "no tool for eggs the player no longer holds")
end
-- Using the egg tool sets the egg down on the grass in front of the player
data.eggs["1"] = 1
IslandService.push(player :: any)
local tool
for _, t in backpack:GetChildren() do
	if t:GetAttribute("EggKind") == "1" then
		tool = t
	end
end
assert(tool and onActivated(tool), "a Meadow Egg tool that does something")
local Layout = Loader.require(Shared.Logic.Layout)
local frame = Layout.garden(1)
root.CFrame = frame * roblox.CFrame.new(Layout.START_SPOT + roblox.Vector3.new(14, 3, 0))
task.wait(1.2) -- (past the throttle)
onActivated(tool)()
local down = 0
for _ in data.incubating do
	down += 1
end
assert(down == 2, "the egg is down on the grass: " .. down)
assert(data.eggs["1"] == 0, "and out of the inventory")
-- The pasture grown all the way: the incubators move back with it, to its back edge
local top = #(Loader.require(Shared.Config.Island)).PASTURE_GROWTH
data.pasture = top
IslandService.render(player :: any)
for _, d in island:GetDescendants() do
	if d:IsA("BasePart") and d:GetAttribute("Machine") then
		local want = Layout.incubator(1, d:GetAttribute("Slot"), top)
		local got = d.CFrame.Position -- (Lune's parts only know their CFrame)
		assert(math.abs(got.X - want.X) < 0.01 and math.abs(got.Z - want.Z) < 0.01, "an incubator at the grown pasture's back")
	end
end
print("island test passed")
require("@lune/process").exit(0)
