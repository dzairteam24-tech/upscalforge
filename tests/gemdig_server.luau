-- Gem Dig's server side with real Roblox instances (through Lune): the mine builds, digs, prunes; the services
-- build the town and plots. Run from the repo root:  lune run tests/gemdig_server.luau

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./loader")

local Shared = Loader.root("gemdig/shared", "Shared")
local Server = Loader.root("gemdig/server", "Server")

local triggerPrompt: any = nil
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
			if name == "ProximityPromptService" then
				return { PromptTriggered = { Connect = function(_self, fn) triggerPrompt = fn end } }
			end
			error("service not stubbed: " .. name)
		end,
	},
	workspace = workspaceInstance,
}

local Vector3 = roblox.Vector3
local Mine = Loader.require(Server.Mine)
local MineConfig = Loader.require(Shared.Config.Mine)
local Gear = Loader.require(Shared.Config.Gear)
local Layout = Loader.require(Shared.Logic.Layout)
local Gems = Loader.require(Shared.Config.Gems)
local Game = Loader.require(Shared.Config.Game)

local passed, failed = 0, 0
local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (if detail then " (" .. detail .. ")" else ""))
	end
end

local function rng(seed: number)
	local state = seed
	return {
		NextNumber = function(_self: any): number
			state = (state * 1103515245 + 12345) % 2147483648
			return state / 2147483648
		end,
	}
end

local function count(folder: any, name: string?): number
	local n = 0
	for _, d in folder:GetDescendants() do
		if not name or d.Name == name then
			n += 1
		end
	end
	return n
end

local function newData(): any
	return { coins = 0, shovel = 1, pack = 1, items = {}, nextId = 1, found = {}, stats = { dug = 0, sold = 0, earned = 0 }, deepest = 0, seed = 1, lastSeen = 0 }
end

local W = MineConfig.WIDTH
local random = rng(5)

-- the mine builds a window of layers, walls and all
do
	local mine = Mine.new(1, 1234, 77, workspaceInstance)
	mine:ensure(1)
	local blocks = count(mine.folder, "Block")
	check("layers 1.." .. 1 + MineConfig.AHEAD .. " built", blocks == W * W * (1 + MineConfig.AHEAD), tostring(blocks))
	check("the walls are there for layers below the first", count(mine.folder, "Wall") == 4 * MineConfig.AHEAD)
	-- every cube is tagged with its owner and cell
	local ok = true
	for _, d in mine.folder:GetDescendants() do
		if d.Name == "Block" and (d:GetAttribute("Owner") ~= 77 or not d:GetAttribute("X") or not d:GetAttribute("L") or not d:GetAttribute("Z")) then
			ok = false
		end
	end
	check("blocks carry owner and cell", ok)
	-- gem cubes have flecks and a Gem attribute
	local gemBlocks, flecked = 0, 0
	for _, d in mine.folder:GetDescendants() do
		if d.Name == "Block" and d:GetAttribute("Gem") then
			gemBlocks += 1
			if #d:GetChildren() == 5 then
				flecked += 1
			end
		end
	end
	check("some gem cubes, each with its flecks", gemBlocks > 0 and gemBlocks == flecked, gemBlocks .. "/" .. flecked)
	-- moving down builds more and removes the top
	mine:ensure(20)
	check("the surface layers are gone when deep", not mine.built[1] and mine.built[20] ~= nil and mine.built[20 + MineConfig.AHEAD] ~= nil)
	check("and not too many parts", count(mine.folder, "Block") == W * W * (MineConfig.KEEP_ABOVE + 1 + MineConfig.AHEAD))
	mine:ensure(MineConfig.MAX_LAYER)
	check("a floor under the deepest layer", mine.built[MineConfig.MAX_LAYER + 1] ~= nil and count(mine.folder, "Bedrock") == 1)
	mine:destroy()
end

-- digging
do
	local mine = Mine.new(2, 99, 5, workspaceInstance)
	mine:ensure(1)
	local data = newData()
	local standing = Layout.plotCenter(2) + Vector3.new(0, 3, 0)
	-- outside the shaft, bad numbers
	check("outside refused", mine:swing(data, 0, 1, 1, standing, 10, random).reason == "outside")
	check("too deep refused", mine:swing(data, 1, MineConfig.MAX_LAYER + 1, 1, standing, 10, random).reason == "outside")
	check("a fraction refused", mine:swing(data, 1.5, 1, 1, standing, 10, random).reason == "outside")
	-- too far away
	local faraway = Layout.plotCenter(2) + Vector3.new(500, 3, 0)
	check("too far refused", mine:swing(data, 3, 1, 3, faraway, 10, random).reason == "far")
	-- a first layer cube takes 3 hits with the wooden shovel (hp 3, power 1)
	local x, l, z = 3, 1, 3
	local now = 100
	local results = {}
	for i = 1, 3 do
		local outcome = mine:swing(data, x, l, z, standing, now, random)
		table.insert(results, outcome)
		now += 1
	end
	check("hits then breaks", results[1].ok and not results[1].broke and results[2].ok and not results[2].broke and results[3].ok and results[3].broke, tostring(results[3].reason))
	check("the cube is gone", mine.blocks[l * 64 + x * 8 + z] == nil and mine.dug[l * 64 + x * 8 + z] == true)
	check("dug counted", data.stats.dug == 1 and data.deepest == 1)
	check("a hole: digging it again finds nothing", mine:swing(data, x, l, z, standing, now, random).reason == "empty")
	-- the cooldown
	check("a swing too soon is refused", (function()
		mine:swing(data, 2, 1, 2, standing, 200, random)
		return mine:swing(data, 2, 1, 2, standing, 200.05, random).reason == "cooldown"
	end)())
	-- a better shovel is faster
	local strong = newData()
	strong.shovel = 5
	local m2 = Mine.new(3, 99, 6, workspaceInstance)
	m2:ensure(1)
	check("the Diamond Shovel breaks it in one", m2:swing(strong, 2, 1, 2, Layout.plotCenter(3) + Vector3.new(0, 3, 0), 1, random).broke == true)
	m2:destroy()
	-- gem cubes give gems; find one
	local gemCell
	for gx = 1, W do
		for gz = 1, W do
			for gl = 1, MineConfig.AHEAD do
				if not gemCell and mine:gemAt(gx, gl, gz) then
					gemCell = { gx, gl, gz }
				end
			end
		end
	end
	check("this mine has a gem in view", gemCell ~= nil)
	if gemCell then
		local g = newData()
		g.shovel = 5
		local m3 = Mine.new(2, 99, 5, workspaceInstance)
		m3:ensure(1)
		local outcome = m3:swing(g, gemCell[1], gemCell[2], gemCell[3], standing, 1, random)
		check("a gem cube breaks and gives a gem", outcome.ok and outcome.broke and outcome.item ~= nil and Gems.byId[outcome.item.g] ~= nil)
		local held = 0
		for _ in g.items do
			held += 1
		end
		check("the gem is in the backpack and found", held == 1 and g.found[outcome.item.g] == true)
		m3:destroy()
		-- a full backpack: the cube stays, the gem stays in it
		local full = newData()
		full.shovel = 5
		for i = 1, 20 do
			full.items[tostring(i)] = { g = "Quartz", s = "Normal" }
		end
		full.nextId = 21
		local m4 = Mine.new(2, 99, 5, workspaceInstance)
		m4:ensure(1)
		local refused = m4:swing(full, gemCell[1], gemCell[2], gemCell[3], standing, 1, random)
		check("a full backpack refuses a gem cube", not refused.ok and refused.reason == "full")
		check("the cube is still there", m4.blocks[gemCell[2] * 64 + gemCell[1] * 8 + gemCell[3]] ~= nil)
		-- sell, then it works, and it's the same gem
		local rolled = m4.items[gemCell[2] * 64 + gemCell[1] * 8 + gemCell[3]]
		full.items = {}
		local after = m4:swing(full, gemCell[1], gemCell[2], gemCell[3], standing, 5, random)
		check("then it breaks, giving the gem that was rolled", after.broke and after.item == rolled)
		m4:destroy()
	end
	-- teleport to where they last dug: nothing yet for a fresh mine; and the spot is open
	local fresh = Mine.new(4, 1, 8, workspaceInstance)
	check("no depth spot before any digging", fresh:depthSpot() == nil)
	fresh:ensure(1)
	local d = newData()
	d.shovel = 5
	fresh:swing(d, 3, 1, 3, Layout.plotCenter(4) + Vector3.new(0, 3, 0), 1, random)
	local spot = fresh:depthSpot()
	check("the depth spot is the dug cube", spot ~= nil and (spot - Layout.cellCenter(4, 3, 1, 3)).Magnitude < 1)
	fresh:destroy()
	mine:destroy()
end

-- the services build the world
do
	local PlotService = Loader.require(Server.Services.PlotService)
	local TownService = Loader.require(Server.Services.TownService)
	PlotService.init()
	local sold, shopped = 0, 0
	TownService.init(function()
		sold += 1
	end, function()
		shopped += 1
	end)
	-- the stands' prompts do their job
	local town0 = workspaceInstance:FindFirstChild("Town")
	triggerPrompt(town0.SellStand:FindFirstChildOfClass("ProximityPrompt"), {})
	triggerPrompt(town0.ShopStand:FindFirstChildOfClass("ProximityPrompt"), {})
	check("the Sell prompt sells and the Shop prompt opens the shop", sold == 1 and shopped == 1)
	local plots = workspaceInstance:FindFirstChild("Plots")
	check("a plot each", plots ~= nil and #plots:GetChildren() == Game.MAX_PLAYERS)
	local town = workspaceInstance:FindFirstChild("Town")
	check("the town is there", town ~= nil and town:FindFirstChild("SellStand") ~= nil and town:FindFirstChild("ShopStand") ~= nil and town:FindFirstChild("Spawn") ~= nil)
	check("a road to every plot", #(function()
		local roads = {}
		for _, d in town:GetChildren() do
			if d.Name == "Road" then
				table.insert(roads, d)
			end
		end
		return roads
	end)() == Game.MAX_PLAYERS)
	-- players get plots, one each, and free them
	local alice, bob = { DisplayName = "Alice" }, { DisplayName = "Bob" }
	local a, b = PlotService.assign(alice), PlotService.assign(bob)
	check("different plots", a ~= nil and b ~= nil and a ~= b and PlotService.assign(alice) == a)
	PlotService.release(alice)
	check("a freed plot is used again", PlotService.assign({ DisplayName = "Cara" }) == a)
end

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	process.exit(1)
end
