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
local roster = { player }
local players = { GetPlayers = function() return roster end, PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayerByUserId = function() return player end }

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
	source = source:gsub("([%w_]+)%.[%w]+:Connect%(", function(target)
		return if target == "created" or target == "prompt" then "__ignore(" else nil
	end)
	source = source:gsub("character:WaitForChild%(", "character:FindFirstChild(")
	return source
end

Loader.extraEnv = {
	__ignore = function() end,
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

-- A second player, to steal from the first with a bat
local thiefFolder = roblox.Instance.new("Folder")
local thiefBackpack = roblox.Instance.new("Backpack")
thiefBackpack.Parent = thiefFolder
local thiefCharacter = roblox.Instance.new("Model")
local thiefRoot = roblox.Instance.new("Part")
thiefRoot.Name = "HumanoidRootPart"
thiefRoot.Parent = thiefCharacter
local thief = setmetatable({ UserId = 2, DisplayName = "Thief", Name = "Thief", Character = thiefCharacter, Parent = true, ChildAdded = signal(), CharacterAdded = { Connect = signal().Connect, Wait = function() return coroutine.yield() end } }, {
	__index = function(_self, key)
		local value = (thiefFolder :: any)[key]
		if type(value) == "function" then
			return function(_, ...)
				return value(thiefFolder, ...)
			end
		end
		return value
	end,
})
table.insert(roster, thief)

local WorldService = Loader.require(Server.Services.WorldService)
WorldService.build()
local DataService = Loader.require(Server.Services.DataService)
local IslandService = Loader.require(Server.Services.IslandService)
IslandService.init()
local CarryService = Loader.require(Server.Services.CarryService)
CarryService.init()
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
-- A hatched creature goes to the inventory not into the garden; used in the garden, it's set
-- down there; taken back, it's in the inventory again
local function creatureTool(id)
	for _, t in backpack:GetChildren() do
		if t:GetAttribute("CreatureId") == id then
			return t
		end
	end
	return nil
end
local id = assert(IslandService.addCreature(player :: any, data, "Cat", "Normal"), "a new creature")
assert(not table.find(data.placed, id), "not set down by itself")
IslandService.push(player :: any)
task.wait(0.1) -- (the tools come a moment after: CarryService)
local catTool = creatureTool(id)
assert(catTool and catTool.Name == "Cat", "a Cat in the inventory: " .. tostring(catTool and catTool.Name))
root.CFrame = frame * roblox.CFrame.new(0, 3, 0)
onActivated(catTool)()
assert(table.find(data.placed, id), "used in the garden, it's set down there")
task.wait(0.1)
assert(creatureTool(id) == nil, "and out of the inventory")
-- Not in the garden: used elsewhere it stays in the inventory (selling is at the Sell Shop, not here)
local at = table.find(data.placed, id)
table.remove(data.placed, at)
IslandService.push(player :: any)
task.wait(0.1)
local again = assert(creatureTool(id), "back in the inventory")
root.CFrame = roblox.CFrame.new(roblox.Vector3.new(0, 3, 18))
onActivated(again)()
assert(data.creatures[id] and not table.find(data.placed, id), "away from the garden it isn't set down, nor sold")
assert(not workspaceInstance:FindFirstChild("SellPad", true), "no Sell pad in the square")

-- Stealing: two bat hits on a player carrying eggs outside any garden knock one out onto the ground
local StealService = Loader.require(Server.Services.StealService)
StealService.init()
task.wait(0.5) -- (the bat comes to the backpack a moment later)
local bat = thiefBackpack:FindFirstChild("Bat")
assert(bat, "the thief has a bat")
local swingBat = assert(onActivated(bat), "the bat can be swung")
local victimData = assert(DataService.get(player :: any), "the victim's data")
local thiefData = assert(DataService.get(thief :: any), "the thief's data")
victimData.creatures = {}
victimData.placed = {}
victimData.stored = {}
victimData.eggs = { ["1"] = 2 }
victimData.golden = {}
victimData.firstPlayed = 0
thiefData.firstPlayed = 0
root.CFrame = roblox.CFrame.new(0, 3, -100)
thiefRoot.CFrame = roblox.CFrame.new(0, 3, -95) -- (looking north, toward them)
swingBat()
assert((victimData.eggs["1"] or 0) == 2, "one hit knocks nothing out")
task.wait(0.6)
swingBat()
assert(victimData.eggs["1"] == 1, "two hits knock an egg out of their bag")
assert(workspaceInstance:FindFirstChild("Dropped"), "the egg lies on the ground")
-- (a new player can't be hit)
victimData.firstPlayed = os.time()
task.wait(0.6)
swingBat()
task.wait(0.6)
swingBat()
assert(victimData.eggs["1"] == 1, "a new player is left alone")
victimData.firstPlayed = 0
-- (nor anyone in a garden)
root.CFrame = Layout.garden(1) * roblox.CFrame.new(0, 3, 0)
thiefRoot.CFrame = root.CFrame * roblox.CFrame.new(0, 0, 4)
task.wait(0.6)
swingBat()
task.wait(0.6)
swingBat()
assert(victimData.eggs["1"] == 1, "the garden is safe")

-- Storage: only in their own garden; the barn keeps eggs and creatures out of the hotbar
local handlers = {}
for _, name in { "Store", "Withdraw" } do
	remote(name).OnServerEvent = { Connect = function(_self, fn) handlers[name] = fn end }
end
local StorageService = Loader.require(Server.Services.StorageService)
StorageService.init()
local mine = IslandService.islandOf(player :: any)
root.CFrame = roblox.CFrame.new(0, 3, -100)
victimData.eggs = { ["1"] = 2 }
victimData.storedEggs = {}
handlers.Store(player, "egg", 1, true)
assert((victimData.storedEggs["1"] or 0) == 0 and victimData.eggs["1"] == 2, "nothing is stored away from the garden")
root.CFrame = Layout.garden(mine) * roblox.CFrame.new(0, 3, 0)
handlers.Store(player, "egg", 1, false)
assert(victimData.eggs["1"] == 1 and victimData.storedEggs["1"] == 1, "one egg into the barn at home")
handlers.Store(player, "egg", 1, true)
assert(victimData.eggs["1"] == nil and victimData.storedEggs["1"] == 2, "all of them, and none carried")
handlers.Withdraw(player, "egg", 1, false)
assert(victimData.eggs["1"] == 1 and victimData.storedEggs["1"] == 1, "one back out")
local keptId = assert(IslandService.addCreature(player :: any, victimData, "Cat", "Normal"), "a creature")
IslandService.push(player :: any)
task.wait(0.1)
local carried = 0
for _, t in backpack:GetChildren() do
	if t:GetAttribute("CreatureId") == keptId then
		carried += 1
	end
end
assert(carried == 1, "a creature not in the barn is in the hotbar")
handlers.Store(player, "creature", keptId)
task.wait(0.1)
carried = 0
for _, t in backpack:GetChildren() do
	if t:GetAttribute("CreatureId") == keptId then
		carried += 1
	end
end
assert(victimData.stored[keptId] == true and carried == 0, "a creature in the barn isn't in the hotbar")
handlers.Withdraw(player, "creature", keptId)
assert(victimData.stored[keptId] == nil, "and out again")
print("island test passed")
require("@lune/process").exit(0)
