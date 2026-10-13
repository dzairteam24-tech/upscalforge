-- Gem Dig's whole loop through its services, with the engine's services stubbed: a player joins, gets a plot
-- and a mine, digs, sells, buys, and leaves. Run from the repo root:  lune run tests/gemdig_flow.luau

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Loader = require("./loader")

local Shared = Loader.root("gemdig/shared", "Shared")
local Server = Loader.root("gemdig/server", "Server")

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

-- a signal stand-in
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
local players = {}
local saved = {} -- what the fake DataStore holds
local services = {
	ReplicatedStorage = replicatedStorage,
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
	},
	MarketplaceService = {
		UserOwnsGamePassAsync = function()
			return false
		end,
		PromptGamePassPurchase = function() end,
		PromptProductPurchase = function() end,
		PromptGamePassPurchaseFinished = signal(),
	},
	RunService = { IsStudio = function() return false end, IsServer = function() return true end },
	DataStoreService = {
		GetDataStore = function()
			return {
				GetAsync = function(_self, key) return saved[key] end,
				SetAsync = function(_self, key, value) saved[key] = value end,
			}
		end,
	},
}
local closing
Loader.extraEnv = {
	game = {
		GetService = function(_self, name)
			return services[name] or error("service not stubbed: " .. name)
		end,
		BindToClose = function(_self, fn) closing = fn end,
	},
	workspace = workspaceInstance,
	task = task,
	Random = { new = function() local n = 0 return { NextNumber = function() return 0.5 end, NextInteger = function(_self, a, b) n += 1 return a + (n * 7919) % (b - a + 1) end } end },
}
-- the remotes: record what's sent to clients, keep the server handlers (the stand-in Net reads these globals)
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
services.ProximityPromptService = { PromptTriggered = signal() }

local Vector3 = roblox.Vector3
local Net = Loader.require(Shared.Net)
local Layout = Loader.require(Shared.Logic.Layout)
local Gear = Loader.require(Shared.Config.Gear)
local PlotService = Loader.require(Server.Services.PlotService)
local TownService = Loader.require(Server.Services.TownService)
local DataService = Loader.require(Server.Services.DataService)
local EconomyService = Loader.require(Server.Services.EconomyService)
local RobuxService = Loader.require(Server.Services.RobuxService)
local Passes = Loader.require(Shared.Config.Passes)
local Multiplier = Loader.require(Shared.Logic.Multiplier)
local Rebirth = Loader.require(Shared.Logic.Rebirth)
local Gem = Loader.require(Shared.Logic.Gem)
local StudioTools = Loader.require(Server.Services.StudioTools)
local MineService = Loader.require(Server.Services.MineService)

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
PlotService.init()
TownService.init(EconomyService.sell, function(player)
	Net.event("OpenShop"):FireClient(player)
end)
EconomyService.init()
MineService.init()
RobuxService.init(function(player)
	local d = DataService.get(player)
	return if d then EconomyService.perMinute(d) else 0
end, EconomyService.welcomeBack)
DataService.init()

-- a player and their character
local function newPlayer(id: number, name: string): any
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Position = Vector3.new(0, 10, 0)
	local character = roblox.Instance.new("Model")
	root.Parent = character
	return { UserId = id, Name = name, DisplayName = name, Parent = true, Character = character, CharacterAdded = signal() }
end
local function rootOf(player: any): any
	return player.Character:FindFirstChild("HumanoidRootPart")
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

local alice = newPlayer(1, "Alice")
table.insert(players, alice)
playerAdded:fire(alice)
wait()
local data = DataService.get(alice)
check("data loaded", data ~= nil and data.coins == 0 and data.shovel == 1)
local mine = MineService.mineOf(alice)
check("a mine was built", mine ~= nil and PlotService.index(alice) == 1)
check("the client got its first picture", #sent("Data", alice) >= 1 and sent("Data", alice)[1].args[1].capacity == Gear.PACKS[1].slots)
check("the character stands on the plot", (rootOf(alice).CFrame.Position - Layout.plotSpawn(1)).Magnitude < 1, tostring(rootOf(alice).Position))

-- dig: stand over the plot, strike a gem cube with a fast shovel
data.shovel = 5
local standing = Layout.plotCenter(1) + Vector3.new(0, 3, 0)
rootOf(alice).Position = standing
local gemCell
for x = 1, 5 do
	for z = 1, 5 do
		for l = 1, 6 do
			if not gemCell and mine:gemAt(x, l, z) then
				gemCell = { x, l, z }
			end
		end
	end
end
check("a gem to dig", gemCell ~= nil)
rootOf(alice).Position = Layout.cellCenter(1, gemCell[1], gemCell[2], gemCell[3]) + Vector3.new(0, 8, 0) -- (stood by it)
handlers.Dig(alice, gemCell[1], gemCell[2], gemCell[3])
wait()
local gems = 0
for _ in data.items do
	gems += 1
end
check("digging gives a gem and tells the client", gems == 1 and #sent("Fx", alice) >= 2 and #sent("Notify", alice) >= 1)
local pictures = #sent("Data", alice)
check("the client's data was pushed", pictures >= 2)
-- bad requests do nothing
handlers.Dig(alice, "a", 1, 1)
handlers.Dig(alice, 99, 99, 99)
handlers.Dig(alice, nil, nil, nil)
check("bad Dig arguments are ignored", data.stats.dug == 1)

-- teleports
handlers.Teleport(alice, "surface")
check("to the town", (rootOf(alice).CFrame.Position - Layout.hubSpawn()).Magnitude < 1)
handlers.Teleport(alice, "depth")
check("back to where they dug", (rootOf(alice).CFrame.Position - Layout.cellCenter(1, gemCell[1], gemCell[2], gemCell[3])).Magnitude < 2)
handlers.Teleport(alice, "plot")
check("to the plot", (rootOf(alice).CFrame.Position - Layout.plotSpawn(1)).Magnitude < 1)
handlers.Teleport(alice, "nowhere")
check("an unknown place does nothing", (rootOf(alice).CFrame.Position - Layout.plotSpawn(1)).Magnitude < 1)

-- sell
local value = 0
for _, item in data.items do
	local Gem = Loader.require(Shared.Logic.Gem)
	value += Gem.value(item)
end
EconomyService.sell(alice)
check("selling pays the gems' value and empties the backpack", data.coins == value and next(data.items) == nil, tostring(data.coins) .. " vs " .. tostring(value))
EconomyService.sell(alice)
check("selling an empty backpack says so", sent("Notify", alice)[#sent("Notify", alice)].args[1]:find("empty") ~= nil)

-- buy
data.coins = 1000
check("can't skip a shovel", not EconomyService.buy(alice, "shovel", 3))
check("can't buy what's owned", not EconomyService.buy(alice, "shovel", 1))
check("can't buy rubbish", not EconomyService.buy(alice, "sword", 2) and not EconomyService.buy(alice, "shovel", "2") and not EconomyService.buy(alice, "shovel", nil))
data.shovel = 1
check("buy the Stone Shovel", EconomyService.buy(alice, "shovel", 2) and data.shovel == 2 and data.coins == 1000 - Gear.SHOVELS[2].price)
check("buy the next pack", EconomyService.buy(alice, "pack", 2) and data.pack == 2 and data.coins == 1000 - Gear.SHOVELS[2].price - Gear.PACKS[2].price)
data.coins = 0
check("not enough coins", not EconomyService.buy(alice, "shovel", 3) and data.shovel == 2)

-- a second player gets their own plot; leaving frees it and saves
local bob = newPlayer(2, "Bob")
table.insert(players, bob)
playerAdded:fire(bob)
wait()
check("Bob has plot 2", PlotService.index(bob) == 2 and MineService.mineOf(bob) ~= nil)
check("each mine is in its own folder", workspaceInstance:FindFirstChild("Mine_1") ~= nil and workspaceInstance:FindFirstChild("Mine_2") ~= nil)
-- Bob can't dig Alice's mine: his Dig always goes to his own
rootOf(bob).Position = Layout.plotCenter(1) + Vector3.new(0, 3, 0)
local before = DataService.get(alice).stats.dug
handlers.Dig(bob, 2, 1, 2)
check("a player digs only their own mine", DataService.get(alice).stats.dug == before and DataService.get(bob).stats.dug == 0)
players[1] = nil
playerRemoving:fire(alice)
wait()
check("leaving saves and frees the plot", saved.p1 ~= nil and saved.p1.shovel == 2 and PlotService.index(alice) == nil and workspaceInstance:FindFirstChild("Mine_1") == nil)

-- coming back: the save loads
local again = newPlayer(1, "Alice")
table.insert(players, again)
playerAdded:fire(again)
wait()
local back = DataService.get(again)
check("their data comes back", back ~= nil and back.shovel == 2 and back.pack == 2 and back.stats.dug == 1 and back.deepest >= 1)


-- ---------------------------------------------------------------------------------------------------------------
-- The rest of the loop with Dave: a weak shovel, a mine reset, rebirth, the daily reward, passes and products
local dave = newPlayer(4, "Dave")
table.insert(players, dave)
playerAdded:fire(dave)
wait()
local dd = DataService.get(dave)
local dm = MineService.mineOf(dave)
local daveIndex = PlotService.index(dave)
local function lastNotify(player: any): string
	local list = sent("Notify", player)
	return if #list > 0 then list[#list].args[1] else ""
end
check("Dave has a mine", dd ~= nil and dm ~= nil and daveIndex ~= nil)

-- a weak shovel is told so (once, not on every swing)
dm:ensure(9)
dd.shovel = 1
rootOf(dave).Position = Layout.cellCenter(daveIndex, 3, 9, 3)
handlers.Dig(dave, 3, 9, 3)
check("too hard: told which shovel", lastNotify(dave):find("Too hard") ~= nil and lastNotify(dave):find("Stone Shovel") ~= nil, lastNotify(dave))
local before = #sent("Notify", dave)
handlers.Dig(dave, 3, 9, 3)
handlers.Dig(dave, 3, 9, 3)
check("the same warning isn't repeated at once", #sent("Notify", dave) == before)
check("nothing was dug", dd.stats.dug == 0)

-- reset the mine
local oldSeed = dd.seed
handlers.ResetMine(dave)
check("a reset gives a new seed", dd.seed ~= oldSeed and lastNotify(dave):find("New mine") ~= nil)
check("and puts him on his plot", (rootOf(dave).CFrame.Position - Layout.plotSpawn(daveIndex)).Magnitude < 1)
local seedAfter = dd.seed
handlers.ResetMine(dave)
check("not again straight away", dd.seed == seedAfter and lastNotify(dave):find("just reset") ~= nil)

-- rebirth needs the depth and the coins
dd.coins = Rebirth.cost(0)
dd.deepest = 10
handlers.Rebirth(dave)
check("too shallow to rebirth", dd.rebirths == 0 and dd.coins == Rebirth.cost(0))
dd.deepest = 32
dd.shovel = 4
dd.pack = 3
local keep = dd.found
handlers.Rebirth(dave)
check("rebirth: start over, one rebirth, coins spent", dd.rebirths == 1 and dd.coins == 0 and dd.shovel == 1 and dd.pack == 1 and dd.deepest == 0 and dd.checkpoint == 0)
check("the mine was reset with it", dm.shaft == 0 and dm.lastDug == nil)
wait()
check("and the client is told", #sent("Data", dave) > 0 and sent("Data", dave)[#sent("Data", dave)].args[1].rebirths == 1)

-- the daily reward, once a day
local coinsBefore = dd.coins
handlers.Daily(dave)
check("the daily reward pays", dd.coins > coinsBefore and dd.daily.streak == 1)
local after = dd.coins
handlers.Daily(dave)
check("but not twice", dd.coins == after and lastNotify(dave):find("tomorrow") ~= nil)

-- Sell Anywhere is a pass
dd.items = { ["1"] = { g = "Ruby", s = "Normal" } }
dd.nextId = 2
dd.coins = 0
handlers.RemoteSell(dave)
check("selling from anywhere needs the pass", dd.coins == 0 and next(dd.items) ~= nil and lastNotify(dave):find("pass") ~= nil)
local function pass(key: string): any
	for _, p in Passes.PASSES do
		if p.key == key then
			return p
		end
	end
	error("no pass " .. key)
end
RobuxService.grantPass(dave, pass("RemoteSell"))
handlers.RemoteSell(dave)
local multiplier = Multiplier.sell(dd, os.time())
check("with it, he sells from anywhere", next(dd.items) == nil and dd.coins == math.floor(40 * multiplier + 0.5), tostring(dd.coins))
-- 2x Coins doubles it (adds 1)
RobuxService.grantPass(dave, pass("Coins2"))
dd.items = { ["2"] = { g = "Ruby", s = "Normal" } }
dd.coins = 0
EconomyService.sell(dave)
check("2x Coins adds one to the multiplier", Multiplier.sell(dd, os.time()) == multiplier + 1 and dd.coins == math.floor(40 * (multiplier + 1) + 0.5), tostring(dd.coins))
wait()
check("the client's snapshot shows the passes", sent("Data", dave)[#sent("Data", dave)].args[1].passes.Coins2 == true)

-- a request in the Store with no id yet and outside Studio says so; nothing is granted
local passCount = 0
for _ in dd.passes do
	passCount += 1
end
handlers.BuyRobux(dave, "pass", "Vip")
local passCount2 = 0
for _ in dd.passes do
	passCount2 += 1
end
check("an unset-up pass isn't given outside Studio", passCount2 == passCount and lastNotify(dave):find("Not available") ~= nil)
handlers.BuyRobux(dave, "pass", "Nonsense")
handlers.BuyRobux(dave, "gun", "x")
handlers.BuyRobux(dave, 5, nil)
check("rubbish requests are ignored", passCount2 == passCount)

-- products: a boost, and income packs, once per receipt
local products = {}
for _, p in Passes.PRODUCTS do
	products[p.key] = p
end
RobuxService.grantProduct(dave, products.Boost30, 100)
check("a boost lasts 30 minutes", dd.boostUntil >= os.time() + 29 * 60 and dd.boostUntil <= os.time() + 31 * 60)
local c0 = dd.coins
RobuxService.grantProduct(dave, products.CoinsS, 1000)
check("an income pack pays minutes of income", dd.coins - c0 == math.floor(30 * 1000 * Multiplier.sell(dd, os.time())))
local c1 = dd.coins
RobuxService.grantProduct(dave, products.CoinsS, 0)
check("never less than the minimum", dd.coins - c1 == 200)
-- the receipt: paid once
products.CoinsM.id = 777
local c2 = dd.coins
check("the receipt is processed", RobuxService.process(dave.UserId, 777, "receipt-1", function() return 500 end) == true and dd.coins > c2)
local c3 = dd.coins
check("the same receipt isn't paid twice", RobuxService.process(dave.UserId, 777, "receipt-1", function() return 500 end) == true and dd.coins == c3)
check("a stranger's receipt isn't processed", RobuxService.process(999, 777, "receipt-2", function() return 500 end) == false)
check("an unknown product isn't", RobuxService.process(dave.UserId, 555, "receipt-3", function() return 500 end) == false and not table.find(dd.receipts, "receipt-3"))
products.CoinsM.id = 0

-- the drone: a player coming back after three hours is paid for two (the free cap)
saved.p5 = { coins = 0, shovel = 2, pack = 2, items = {}, nextId = 1, found = {}, stats = { dug = 0, sold = 0, earned = 0 }, deepest = 10, seed = 1, lastSeen = os.time() - 3 * 3600, rebirths = 0, checkpoint = 5, passes = {}, boostUntil = 0, daily = { last = 0, streak = 0 }, receipts = {} }
local eve = newPlayer(5, "Eve")
table.insert(players, eve)
playerAdded:fire(eve)
wait()
local ed = DataService.get(eve)
local report = sent("Offline", eve)
check("a returning player gets the drone's coins", ed.coins > 0 and #report == 1 and report[1].args[1] == ed.coins)
check("for two hours: the free cap", report[1].args[2] == 2 * 3600 and report[1].args[3] == true)
check("a mine with an elevator to his saved depth", MineService.mineOf(eve).shaft == 5)
-- a brand new player has no report
check("a new player has no report", #sent("Offline", dave) == 0)


-- Studio chat commands
check("/coins sets coins", StudioTools.command(eve, "/coins 12345") and ed.coins == 12345)
check("/shovel and /pack are clamped", StudioTools.command(eve, "/shovel 99") and ed.shovel == #Gear.SHOVELS and StudioTools.command(eve, "/pack 0") and ed.pack == 1)
check("/deep is clamped to the mine", StudioTools.command(eve, "/deep 999") and ed.deepest == 40 and ed.checkpoint == 35)
check("/rebirths", StudioTools.command(eve, "/rebirths 3") and ed.rebirths == 3)
check("/daily makes it claimable again", StudioTools.command(eve, "/daily") and ed.daily.last == 0)
check("/gem adds a golden huge gem", StudioTools.command(eve, "/gem Void") and (function() for _, item in ed.items do if item.g == "Void" and item.s == "Huge" and item.m == "Golden" then return true end end return false end)())
check("unknown commands and chat are ignored", not StudioTools.command(eve, "hello everyone") and not StudioTools.command(eve, "/coins abc") and not StudioTools.command(eve, "/gem Nothing"))


-- the mine builds itself round a player who falls down the elevator shaft
do
	local fd = DataService.get(eve)
	local fm = MineService.mineOf(eve)
	local fi = PlotService.index(eve)
	rootOf(eve).Position = Layout.cellCenter(fi, 3, 22, 3)
	MineService.follow(eve)
	check("layers round the player are built where he is", fm.built[22] ~= nil and fm.built[22 + 6] ~= nil and fm.built[1] == nil)
	rootOf(eve).Position = Layout.plotCenter(fi) + Vector3.new(500, 3, 0)
	MineService.follow(eve)
	check("outside the shaft changes nothing", fm.built[22] ~= nil)
end

print(("%d passed, %d failed"):format(passed, failed))
process.exit(if failed > 0 then 1 else 0) -- (the services' save loop would keep Lune running)
