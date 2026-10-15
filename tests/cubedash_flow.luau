-- Cubedash's server through its services, with the engine's services stubbed: a player joins, is put at the start,
-- picks up orbs (only real ones, near them, once a run), smashes a wall (only fast enough and right there),
-- buys upgrades, runs a smashed stage again, rebirths, buys with Robux, and leaves.
-- Run from the repo root:  lune run tests/cubedash_flow.luau

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Loader = require("./loader")

local Shared = Loader.root("cubedash/shared", "Shared")
local Server = Loader.root("cubedash/server", "Server")

local dataModel = roblox.Instance.new("DataModel")
local workspaceInstance = dataModel:GetService("Workspace")
local lighting = dataModel:GetService("Lighting")
local replicatedStorage = {
	WaitForChild = function(_self, name)
		assert(name == "Shared", "unexpected WaitForChild " .. tostring(name))
		return Shared
	end,
	FindFirstChild = function()
		return nil
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
local players = {}
local saved = {}
local studio = false
local services = {
	ReplicatedStorage = replicatedStorage,
	Lighting = lighting,
	PhysicsService = { RegisterCollisionGroup = function() end, CollisionGroupSetCollidable = function() end },
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
	os = { time = os.time, clock = function() return Loader.extraEnv.clockNow end },
	clockNow = 1000,
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

local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local Net = Loader.require(Shared.Net)
local Layout = Loader.require(Shared.Logic.Layout)
local Stage = Loader.require(Shared.Logic.Stage)
local Economy = Loader.require(Shared.Logic.Economy)
local Progress = Loader.require(Shared.Logic.Progress)
local Speed = Loader.require(Shared.Logic.Speed)
local Passes = Loader.require(Shared.Config.Passes)
local CourseService = Loader.require(Server.Services.CourseService)
local DataService = Loader.require(Server.Services.DataService)
local EconomyService = Loader.require(Server.Services.EconomyService)
local RobuxService = Loader.require(Server.Services.RobuxService)
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
CourseService.init()
EconomyService.init(CourseService.teleport)
RobuxService.init()
DataService.init()

-- a player and a character stand-in (the engine's own can't move in Lune)
local function newPlayer(id: number, name: string): any
	local root = { Name = "HumanoidRootPart", CFrame = CFrame.new(0, 10, 0), IsA = function(_self, c) return c == "BasePart" end }
	local humanoid = { WalkSpeed = 16, JumpHeight = 7.2, UseJumpPower = true }
	local character = {
		FindFirstChild = function(_self, n) return if n == "HumanoidRootPart" then root else nil end,
		FindFirstChildOfClass = function(_self, c) return if c == "Humanoid" then humanoid else nil end,
		PivotTo = function(_self, cf) root.CFrame = cf end,
		GetDescendants = function() return {} end,
		DescendantAdded = signal(),
	}
	return { UserId = id, Name = name, Parent = true, Character = character, CharacterAdded = signal(), root = root, humanoid = humanoid }
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
local function standAt(player: any, stage: number, x: number, d: number, y: number?)
	player.root.CFrame = CFrame.new(Layout.toWorld(stage, x, d) + Vector3.new(0, y or 3, 0))
end

check("the course is built", workspaceInstance:FindFirstChild("Course") ~= nil and workspaceInstance.Course:FindFirstChild("Stage10") ~= nil and workspaceInstance.Course:FindFirstChild("Finish") ~= nil)
check("the night has its glow", lighting:FindFirstChildOfClass("BloomEffect") ~= nil and lighting:FindFirstChildOfClass("Atmosphere") ~= nil)

local alice = newPlayer(1, "Alice")
table.insert(players, alice)
playerAdded:fire(alice)
wait()
local data = DataService.get(alice)
check("data loaded, fresh", data ~= nil and data.coins == 0 and data.stage == 1 and data.speed == 0)
check("put at the start of stage 1", (alice.root.CFrame.Position - Layout.spawn(1)).Magnitude < 0.01)
check("told the client", #sent("Teleported", alice) >= 1 and #sent("Data", alice) >= 1)
check("walks at the speed of their stat", math.abs(alice.humanoid.WalkSpeed - Speed.walk(Progress.stat(data))) < 1e-6 and alice.humanoid.JumpHeight == 7.5)

-- orbs
local stage1 = Stage.generate(1)
local orb = stage1.orbs[1]
standAt(alice, 1, orb.x + 40, orb.d)
check("an orb too far away isn't theirs", not CourseService.collect(alice, 1, 1) and data.speed == 0)
standAt(alice, 1, orb.x, orb.d, orb.y)
check("an orb right there is", CourseService.collect(alice, 1, 1) and data.speed == Progress.orbValue(data, 1) and data.stats.orbs == 1)
check("but only once a run", not CourseService.collect(alice, 1, 1) and data.stats.orbs == 1)
check("nonsense is ignored", not CourseService.collect(alice, 1, 9999) and not CourseService.collect(alice, "x", 1) and not CourseService.collect(alice, 2, 1) and not CourseService.collect(alice, 1.5, 1))
handlers.RunStart(alice, 1)
standAt(alice, 1, orb.x, orb.d, orb.y)
check("a new run brings the orbs back", CourseService.collect(alice, 1, 1) and data.stats.orbs == 2)
local coinsBefore = data.coins
check("orbs pay coins too", coinsBefore > 0)
wait()
check("faster after orbs", alice.humanoid.WalkSpeed > 16)

-- the wall
local length = Economy.stageLength(1)
standAt(alice, 1, 0, length - 3)
check("not fast enough: the wall holds", not CourseService.smash(alice, 1) and data.stage == 1)
local bad = sent("Notify", alice)
check("and they're told what it needs", #bad > 0 and string.find(bad[#bad].args[1], "needs") ~= nil)
data.speed = Economy.needs(1)
standAt(alice, 1, 0, 200)
check("fast enough, but far from the wall: no", not CourseService.smash(alice, 1) and data.stage == 1)
standAt(alice, 1, 0, length - 3)
check("not another stage's wall", not CourseService.smash(alice, 2) and data.stage == 1)
check("fast enough at the wall: SMASH", CourseService.smash(alice, 1) and data.stage == 2 and data.coins >= coinsBefore + Economy.wallCoins(1))
check("the client hears it", #sent("Smashed", alice) == 1 and sent("Smashed", alice)[1].args[1] == 1)
check("can't smash it twice", not CourseService.smash(alice, 1) and data.stage == 2)

-- running a smashed stage again: a bonus once a run, not too quick
handlers.RunStart(alice, 1)
standAt(alice, 1, 0, length - 2)
local c0 = data.coins
check("too quick to have run it: no bonus", not CourseService.finish(alice, 1) and data.coins == c0)
Loader.extraEnv.clockNow += 60
check("ran it: a bonus", CourseService.finish(alice, 1) and data.coins > c0 and data.stats.runs == 1)
check("once a run", not CourseService.finish(alice, 1))
check("not their furthest stage (no wall smashed)", not CourseService.finish(alice, 2))

-- upgrades
data.coins = 1000
check("buy Orb Power", EconomyService.buy(alice, "orb") and data.upgrades.orb == 1 and data.coins == 1000 - Economy.upgradeCost(Economy.upgrade("orb"), 0))
data.coins = 0
check("can't afford", not EconomyService.buy(alice, "orb") and data.upgrades.orb == 1)
check("nonsense", not EconomyService.buy(alice, 42) and not EconomyService.buy(alice, "wings"))

-- restart and teleport
handlers.Restart(alice)
check("restart: the start of their furthest stage", (alice.root.CFrame.Position - Layout.spawn(2)).Magnitude < 0.01 and CourseService.run(alice).stage == 2)
handlers.RunStart(alice, 5)
check("can't start a stage they haven't reached", CourseService.run(alice).stage == 2)

-- crash count
handlers.Crash(alice, 2, "laser")
handlers.Crash(alice, 2, "laser")
check("crashes are counted (not too fast)", data.stats.crashes == 1)

-- daily
check("daily reward", EconomyService.daily(alice) and data.coins >= 50 and data.daily.streak == 1)
check("once a day", not EconomyService.daily(alice))

-- rebirth
check("no rebirth before the course is beaten", not EconomyService.rebirth(alice, CourseService.teleport))
data.stage = Economy.STAGES + 1
data.coins = Economy.rebirthCost(0)
data.speed = 123456
check("rebirth", EconomyService.rebirth(alice, CourseService.teleport) and data.rebirths == 1 and data.stage == 1 and data.speed == 0 and data.coins == 0)
check("back at the start", (alice.root.CFrame.Position - Layout.spawn(1)).Magnitude < 0.01)

-- Robux (not in Studio: needs a real id; in Studio a 0 id is a free test)
RobuxService.request(alice, "pass", "Orbs2")
check("not in Studio, no id: nothing", data.passes.Orbs2 == nil)
studio = true
RobuxService.request(alice, "pass", "Orbs2")
check("in Studio: the pass for testing", data.passes.Orbs2 == true)
RobuxService.request(alice, "product", "Wall")
check("Wall Breaker: fast enough for the current wall", Progress.canSmash(data, data.stage))
local c1 = data.coins
RobuxService.request(alice, "product", "CoinsS")
check("coin pack", data.coins >= c1 + 100)
RobuxService.request(alice, "product", "Boost30")
check("boost", data.boostUntil > os.time() + 1700)
studio = false
-- a real receipt is paid once
Passes.PRODUCTS[3].id = 777
local c2 = data.coins
check("a receipt pays", RobuxService.process(1, 777, "r1") and data.coins > c2)
local c3 = data.coins
check("the same receipt again doesn't", RobuxService.process(1, 777, "r1") and data.coins == c3)
check("an unknown product isn't granted", not RobuxService.process(1, 555, "r2"))

-- studio tools
studio = true
check("chat command: /stage", StudioTools.command(alice, "/stage 4", CourseService.teleport) and data.stage == 4)
check("chat command: /coins", StudioTools.command(alice, "/coins 77", CourseService.teleport) and data.coins == 77)
check("not a command", not StudioTools.command(alice, "hello", CourseService.teleport))
studio = false

-- leave: saved
playerRemoving:fire(alice)
wait()
check("saved when they leave", saved["p1"] ~= nil and saved["p1"].rebirths == 1 and saved["p1"].stage == 4)

-- come back: the save reconciles
local alice2 = newPlayer(1, "Alice")
players = { alice2 }
playerAdded:fire(alice2)
wait()
local again = DataService.get(alice2)
check("loaded again", again ~= nil and again.rebirths == 1 and again.stage == 4 and again.passes.Orbs2 == true)
check("put at their furthest stage", (alice2.root.CFrame.Position - Layout.spawn(4)).Magnitude < 0.01)
-- a broken save is fixed up
saved["p2"] = { coins = "lots", stage = 999, upgrades = { orb = "x", coin = 3 }, passes = { Vip = "yes", Coins2 = true } }
local bob = newPlayer(2, "Bob")
table.insert(players, bob)
playerAdded:fire(bob)
wait()
local b = DataService.get(bob)
check("a broken save is mended", b ~= nil and b.coins == 0 and b.stage == Economy.STAGES + 1 and b.upgrades.orb == nil and b.upgrades.coin == 3 and b.passes.Vip == nil and b.passes.Coins2 == true)
local _ = closing

print(("%d passed, %d failed"):format(passed, failed))
process.exit(if failed > 0 then 1 else 0)
