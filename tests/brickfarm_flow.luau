-- Brick Farm's server through its services, with the engine's services stubbed: two players join and get their
-- own farms, plant, harvest (only when ready, only near it, only their own), sell, buy seeds and land, level up,
-- leave (the farm is freed) and come back (crops grew while away). Run from the repo root:
--   lune run tests/brickfarm_flow.luau

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Loader = require("./loader")

local Shared = Loader.root("brickfarm/shared", "Shared")
local Server = Loader.root("brickfarm/server", "Server")

local dataModel = roblox.Instance.new("DataModel")
local workspaceInstance = dataModel:GetService("Workspace")
local lighting = dataModel:GetService("Lighting")
local replicatedStorage = {
	WaitForChild = function(_self, name)
		assert(name == "Shared", "unexpected WaitForChild " .. tostring(name))
		return Shared
	end,
}

local function signal()
	local handlers = {}
	return {
		Connect = function(_self, fn)
			table.insert(handlers, fn)
			return { Disconnect = function() end }
		end,
		fire = function(_self, ...)
			for _, fn in handlers do
				task.spawn(fn, ...)
			end
		end,
	}
end

local playerAdded, playerRemoving = signal(), signal()
local promptTriggered = signal()
local players = {}
local saved = {}
local studio = false
local clock = 1000000
local services = {
	ReplicatedStorage = replicatedStorage,
	Lighting = lighting,
	ProximityPromptService = { PromptTriggered = promptTriggered },
	Players = {
		PlayerAdded = playerAdded,
		PlayerRemoving = playerRemoving,
		GetPlayers = function()
			return players
		end,
	},
	RunService = { IsStudio = function() return studio end, IsServer = function() return true end },
	DataStoreService = {
		GetDataStore = function()
			return {
				GetAsync = function(_self, key) return saved[key] end,
				SetAsync = function(_self, key, value) saved[key] = value end,
			}
		end,
	},
}
Loader.extraEnv = {
	game = {
		GetService = function(_self, name)
			return services[name] or error("service not stubbed: " .. name)
		end,
		BindToClose = function() end,
	},
	workspace = workspaceInstance,
	task = task,
	os = { time = function() return clock end, clock = os.clock },
}
local fired, handlers = {}, {}
Loader.extraEnv.fired, Loader.extraEnv.handlers = fired, handlers
Loader.transform = function(path: string, source: string): string
	if string.find(path, "shared/Net.luau", 1, true) then
		return [[
return {
	init = function() end,
	event = function(name)
		return {
			FireClient = function(_self, player, ...) table.insert(fired, { name = name, player = player, args = { ... } }) end,
			OnServerEvent = { Connect = function(_self, fn) handlers[name] = fn end },
		}
	end,
}]]
	end
	return source
end

local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
local Net = Loader.require(Shared.Net)
local Crops = Loader.require(Shared.Config.Crops)
local Layout = Loader.require(Shared.Logic.Layout)
local Land = Loader.require(Shared.Logic.Land)
local Level = Loader.require(Shared.Logic.Level)
local Farm = Loader.require(Shared.Logic.Farm)
local DataService = Loader.require(Server.Services.DataService)
local FarmService = Loader.require(Server.Services.FarmService)
local StudioTools = Loader.require(Server.Services.StudioTools)

local passed, failed = 0, 0
local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (if detail then " (" .. detail .. ")" else ""))
	end
end

Net.init()
FarmService.init()
DataService.init()

local function newPlayer(id: number, name: string): any
	local root = { Name = "HumanoidRootPart", CFrame = CFrame.new(0, 3, 0), IsA = function(_self, c) return c == "BasePart" end }
	local character = {
		FindFirstChild = function(_self, n) return if n == "HumanoidRootPart" then root else nil end,
		PivotTo = function(_self, cf) root.CFrame = cf end,
	}
	return { UserId = id, Name = name, DisplayName = name, Parent = true, Character = character, CharacterAdded = signal(), root = root }
end
local function sent(name: string, player: any): { any }
	local list = {}
	for _, f in fired do
		if f.name == name and f.player == player then
			table.insert(list, f)
		end
	end
	return list
end
local function wait()
	task.wait(0.05)
end
local function standBy(player: any, farm: number, tile: number)
	player.root.CFrame = Layout.tile(farm, tile) * CFrame.new(0, 3, 0)
end

local village = workspaceInstance:FindFirstChild("Village")
check("the village is built", village ~= nil and village:FindFirstChild("Farm8") ~= nil and village.Farm1.Tiles:FindFirstChild("Tile36") ~= nil and village:FindFirstChild("Square") ~= nil)
check("it's a sunny day", lighting.ClockTime == 14 and lighting:FindFirstChildOfClass("Atmosphere") ~= nil)

local alice = newPlayer(1, "Alice")
table.insert(players, alice)
playerAdded:fire(alice)
wait()
local data = DataService.get(alice)
check("a fresh farmer: some coins and carrot seeds", data ~= nil and data.coins == 20 and data.seeds.carrot == 6 and data.tiles == Land.START)
check("gets farm 1", FarmService.farmOf(alice) == 1 and village.Farm1:GetAttribute("Owner") == 1)
check("their name is on its sign", village.Farm1.NameBoard:FindFirstChildOfClass("SurfaceGui").Owner.Text == "Alice's Farm")
check("stands in front of it", (alice.root.CFrame.Position - Layout.spawn(1).Position).Magnitude < 0.01)
check("their land shows", village.Farm1.Tiles.Tile6:GetAttribute("Owned") == true and village.Farm1.Tiles.Tile7:GetAttribute("Owned") == false)
local snap = sent("Data", alice)
check("the client knows which farm is theirs", #snap >= 1 and snap[#snap].args[1].farm == 1 and snap[#snap].args[1].level == 1)

-- plant
alice.root.CFrame = CFrame.new(0, 3, 0) -- (the square, far from the farm)
check("too far away: no", FarmService.tap(alice, 1, "carrot") == nil and data.seeds.carrot == 6)
standBy(alice, 1, 1)
check("plant a carrot", FarmService.tap(alice, 1, "carrot") == "plant" and data.seeds.carrot == 5)
check("the tile shows it", village.Farm1.Tiles.Tile1:GetAttribute("Crop") == "carrot" and village.Farm1.Tiles.Tile1:GetAttribute("Planted") == clock)
check("not on land they don't have", FarmService.tap(alice, 7, "carrot") == nil)
check("not a crop they can't grow yet (no seeds)", FarmService.tap(alice, 2, "goldcorn") == nil)
check("tapping it while it grows does nothing", FarmService.tap(alice, 1, "carrot") == nil and data.seeds.carrot == 5)
check("nonsense is ignored", FarmService.tap(alice, "x", "carrot") == nil and FarmService.tap(alice, 1.5, "carrot") == nil and FarmService.tap(alice, 99, "carrot") == nil)

-- harvest
clock += Crops.byKey.carrot.grow
check("ready: harvest", FarmService.tap(alice, 1, "carrot") == "harvest" and data.barn.carrot == Crops.byKey.carrot.yield and data.xp == Crops.byKey.carrot.xp)
check("the client sees it", #sent("Harvested", alice) == 1 and sent("Harvested", alice)[1].args[2] == "carrot")
check("the tile is empty again", village.Farm1.Tiles.Tile1:GetAttribute("Crop") == "")

-- sell
check("sell all", FarmService.sell(alice, "all") == Crops.byKey.carrot.sell * Crops.byKey.carrot.yield and data.coins == 20 + Crops.byKey.carrot.sell * Crops.byKey.carrot.yield)
check("nonsense to sell", FarmService.sell(alice, 42) == 0 and FarmService.sell(alice, "banana") == 0)

-- seeds
check("buy carrot seeds", FarmService.buySeeds(alice, "carrot", 2) and data.seeds.carrot == 7)
check("not locked ones", not FarmService.buySeeds(alice, "corn", 1))

-- a level up
data.xp = Level.toNext(1) - 1
standBy(alice, 1, 2)
FarmService.tap(alice, 2, "carrot")
clock += 60
FarmService.tap(alice, 2)
check("a level up is told", #sent("LevelUp", alice) == 1 and sent("LevelUp", alice)[1].args[1] == 2 and sent("LevelUp", alice)[1].args[2][1] == "radish")

-- land
data.coins = Land.cost(Land.START + 1)
check("buy land", FarmService.expand(alice) and data.tiles == Land.START + 1 and village.Farm1.Tiles.Tile7:GetAttribute("Owned") == true)
check("can't without coins", not FarmService.expand(alice))

-- a second player: their own farm, can't touch Alice's
local bob = newPlayer(2, "Bob")
table.insert(players, bob)
playerAdded:fire(bob)
wait()
check("Bob gets farm 2", FarmService.farmOf(bob) == 2)
standBy(alice, 1, 3)
FarmService.tap(alice, 3, "carrot")
bob.root.CFrame = alice.root.CFrame
clock += 100
check("Bob can't harvest Alice's carrots", FarmService.tap(bob, 3) == nil and village.Farm1.Tiles.Tile3:GetAttribute("Crop") == "carrot")

-- the barn
promptTriggered:fire({ Name = "BarnPrompt" }, alice)
wait()
check("the barn's prompt opens the barn", #sent("OpenBarn", alice) == 1)

-- broke: a few seeds free
local bdata = DataService.get(bob)
bdata.seeds = {}
bdata.coins = 0
check("a broke farmer gets seeds", FarmService.rescue(bdata) and bdata.seeds.carrot == 4)
check("but not one with something", not FarmService.rescue(data))

-- studio tools
studio = true
check("/grow makes everything ready", StudioTools.command(alice, "/grow", FarmService.show) and Farm.readyCount(data, clock) >= 1)
check("/level", StudioTools.command(alice, "/level 6", FarmService.show) and Farm.level(data) == 6)
check("/seeds", StudioTools.command(alice, "/seeds corn 3", FarmService.show) and data.seeds.corn == 3)
check("not a command", not StudioTools.command(alice, "hello", FarmService.show))
studio = false

-- Alice leaves with a corn planted; her farm is freed and saved
standBy(alice, 1, 4)
FarmService.tap(alice, 4, "corn")
playerRemoving:fire(alice)
wait()
check("saved", saved["p1"] ~= nil and saved["p1"].plots["4"].c == "corn")
check("her farm is freed", village.Farm1:GetAttribute("Owner") == 0 and village.Farm1.Tiles.Tile4:GetAttribute("Crop") == "" and village.Farm1.NameBoard:FindFirstChildOfClass("SurfaceGui").Owner.Text == "Free farm")

-- she comes back the next day: the corn grew while she was away
clock += 86400
local alice2 = newPlayer(1, "Alice")
players = { bob, alice2 }
playerAdded:fire(alice2)
wait()
local again = DataService.get(alice2)
check("back with her farm as it was", again ~= nil and again.plots["4"].c == "corn" and again.tiles == Land.START + 1)
check("on the free farm", FarmService.farmOf(alice2) == 1)
local welcome = sent("Notify", alice2)
check("told what's ready", #welcome > 0 and string.find(welcome[#welcome].args[1], "ready") ~= nil)
standBy(alice2, 1, 4)
check("and harvests it", FarmService.tap(alice2, 4) == "harvest" and again.barn.corn == Crops.byKey.corn.yield)

-- a broken save is mended
saved["p3"] = { coins = "lots", tiles = 999, seeds = { carrot = 5, banana = 3, corn = -2 }, plots = { ["1"] = { c = "corn", t = 5 }, ["2"] = { c = "nope", t = 1 }, ["50"] = { c = "corn", t = 1 } } }
local cara = newPlayer(3, "Cara")
table.insert(players, cara)
playerAdded:fire(cara)
wait()
local c = DataService.get(cara)
check("a broken save is mended", c ~= nil and c.coins == 20 and c.tiles == Land.MAX and c.seeds.carrot == 5 and c.seeds.banana == nil and c.seeds.corn == nil and c.plots["1"].c == "corn" and c.plots["2"] == nil and c.plots["50"] == nil)
check("Cara gets farm 3", FarmService.farmOf(cara) == 3)
local _ = Vector3

print(("%d passed, %d failed"):format(passed, failed))
process.exit(if failed > 0 then 1 else 0)
