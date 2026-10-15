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
		GetPlayerByUserId = function(_self, id)
			for _, p in players do
				if p.UserId == id then
					return p
				end
			end
			return nil
		end,
		GetPlayerFromCharacter = function(_self, character)
			for _, p in players do
				if p.Character == character then
					return p
				end
			end
			return nil
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
	PhysicalProperties = roblox.PhysicalProperties,
	Random = { new = function() local n = 0 return { NextInteger = function(_self, a, b) n += 1 return a + (n * 7919) % (b - a + 1) end } end },
	__pivot = function(model, cf)
		model.PrimaryPart.CFrame = cf
	end,
	__occupant = function(seat, fn)
		occupantHooks[seat] = fn
	end,
}
local fired, handlers = {}, {}
occupantHooks = {}
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
	if string.find(path, "TractorService.luau", 1, true) then
		source = string.gsub(source, 'seat:GetPropertyChangedSignal%("Occupant"%):Connect%(function%(%)', "__occupant(seat, function()")
		-- (Lune's models can't be pivoted: move the base)
		source = string.gsub(source, "model:PivotTo%(", "__pivot(model, ")
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
local MarketService = Loader.require(Server.Services.MarketService)
local TractorService = Loader.require(Server.Services.TractorService)
local Orders = Loader.require(Shared.Logic.Orders)
local Stand = Loader.require(Shared.Logic.Stand)

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
MarketService.init(FarmService.farmOf, FarmService.ownerOf, FarmService.levelUp)
TractorService.init(FarmService.farmOf, DataService.onLoaded, DataService.onLeaving)
DataService.init()

local function newPlayer(id: number, name: string): any
	local root = { Name = "HumanoidRootPart", CFrame = CFrame.new(0, 3, 0), IsA = function(_self, c) return c == "BasePart" end }
	local character = {
		FindFirstChild = function(_self, n) return if n == "HumanoidRootPart" then root else nil end,
		PivotTo = function(_self, cf) root.CFrame = cf end,
		WaitForChild = function() return nil end,
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
check("the village is built", village ~= nil and village:FindFirstChild("Farm6") ~= nil and village:FindFirstChild("Farm7") == nil and village.Farm1.Tiles:FindFirstChild("Tile36") ~= nil and village:FindFirstChild("Town") ~= nil)
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

-- the town's orders
check("three orders waiting", #data.orders == Orders.COUNT)
local order = data.orders[1]
data.barn[order.c] = order.n
standBy(alice, 1, 1)
check("not handed in far from the board", not MarketService.deliver(alice, 1) and data.barn[order.c] == order.n)
alice.root.CFrame = Layout.board() * CFrame.new(0, 3, -6)
local coinsBefore = data.coins
check("handed in at the board", MarketService.deliver(alice, 1) and data.coins == coinsBefore + order.coins and #data.orders == Orders.COUNT)
check("swap an order", MarketService.swap(alice, 2) and not MarketService.swap(alice, 2))
promptTriggered:fire({ Name = "OrdersPrompt" }, alice)
wait()
check("the board's prompt opens the orders", #sent("OpenOrders", alice) == 1)

-- Alice's stand: she puts corn out, Bob comes and buys
data.barn.corn = 9
check("Alice stocks her stand", MarketService.put(alice, "corn", 6, 60) and data.stand.corn.n == 6)
check("the corn shows on her counter", village.Farm1.Stand:FindFirstChild("Goods") ~= nil and #village.Farm1.Stand.Goods:GetChildren() == 2)
local bdata2 = DataService.get(bob)
bdata2.coins = 1000
bob.root.CFrame = Layout.tile(2, 1) * CFrame.new(0, 3, 0)
check("Bob can't buy from afar", not MarketService.buy(bob, 1, "corn", 2))
bob.root.CFrame = Layout.stand(1) * CFrame.new(0, 3, -6)
local aliceCoins = data.coins
check("Bob buys 2 corn at Alice's stand", MarketService.buy(bob, 1, "corn", 2) and bdata2.coins == 880 and bdata2.barn.corn == 2 and data.coins == aliceCoins + 120 and data.stand.corn.n == 4)
local told = sent("Notify", alice)
check("Alice is told, wherever she is", string.find(told[#told].args[1], "bought 2 Corn") ~= nil)
check("Alice can't buy from her own stand", not MarketService.buy(alice, 1, "corn", 1))
check("nobody's stand on a free farm", not MarketService.buy(bob, 5, "corn", 1))
promptTriggered:fire({ Name = "StandPrompt", FindFirstAncestorWhichIsA = function() return village.Farm1 end }, bob)
wait()
local opened = sent("OpenStand", bob)
check("Bob opens Alice's stand: her name, her stock, not his", #opened >= 1 and opened[#opened].args[1] == 1 and opened[#opened].args[2] == "Alice" and opened[#opened].args[4] == false)
check("Alice takes the rest back", MarketService.take(alice, "corn") and data.stand.corn == nil and data.barn.corn == 7)

-- a trade: Alice and Bob together
alice.root.CFrame = CFrame.new(0, 3, 10)
bob.root.CFrame = CFrame.new(0, 3, 16)
data.barn.pumpkin = 2
bdata2.barn.tomato = 10
MarketService.ask(alice, 2)
check("Bob is asked", #sent("TradeAsked", bob) == 1)
MarketService.answer(bob, 1, true)
check("the trade starts", MarketService.session(alice) ~= nil and MarketService.session(alice) == MarketService.session(bob))
MarketService.offer(alice, { pumpkin = 1 }, 50)
MarketService.offer(bob, { tomato = 6 }, 0)
MarketService.ready(alice, true)
check("one ready, nothing yet", data.barn.tomato == nil)
local aCoins, bCoins = data.coins, bdata2.coins
MarketService.ready(bob, true)
check("both ready: it's done", data.barn.tomato == 6 and data.barn.pumpkin == 1 and bdata2.barn.pumpkin == 1 and bdata2.barn.tomato == 4 and data.coins == aCoins - 50 and bdata2.coins == bCoins + 50)
check("and over", MarketService.session(alice) == nil and MarketService.session(bob) == nil)
-- too far apart: no trade
bob.root.CFrame = CFrame.new(300, 3, 300)
MarketService.ask(alice, 2)
check("too far to ask", #sent("TradeAsked", bob) == 1)

-- the tractor
local tractor = TractorService.of(alice)
check("Alice has a tractor by her gate", tractor ~= nil and (tractor.PrimaryPart.CFrame.Position - Layout.tractor(1).Position).Magnitude < 3)
check("it has its seat and movers", tractor:FindFirstChild("DriverSeat") ~= nil and tractor.PrimaryPart:FindFirstChild("Move") ~= nil and tractor.PrimaryPart:FindFirstChild("Turn") ~= nil)
alice.root.CFrame = CFrame.new(50, 3, 50)
check("call it: it comes", TractorService.call(alice) and (tractor.PrimaryPart.CFrame.Position - Vector3.new(50, 1.2, 50)).Magnitude < 12)
check("Bob has his own", TractorService.of(bob) ~= nil and TractorService.of(bob) ~= tractor)

-- Alice leaves with a corn planted; her farm is freed and saved
standBy(alice, 1, 4)
FarmService.tap(alice, 4, "corn")
playerRemoving:fire(alice)
wait()
check("saved", saved["p1"] ~= nil and saved["p1"].plots["4"].c == "corn")
check("her tractor is gone", TractorService.of(alice) == nil and tractor.Parent == nil)
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
local cornBefore = again.barn.corn or 0
check("and harvests it", FarmService.tap(alice2, 4) == "harvest" and again.barn.corn == cornBefore + Crops.byKey.corn.yield)

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
