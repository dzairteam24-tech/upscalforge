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
	Random = { new = function() return { NextNumber = function() return 0.5 end } end },
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

print(("%d passed, %d failed"):format(passed, failed))
process.exit(if failed > 0 then 1 else 0) -- (the services' save loop would keep Lune running)
