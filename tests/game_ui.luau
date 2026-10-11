-- Builds the whole screen (game/client UI, as Main does) with real Roblox instances through Lune, opens every
-- window and every Bag tab with a player's data, and presses the HUD's buttons, to catch wrong properties and
-- errors that only show when the UI runs. Run from the repo root:  lune run tests/game_ui.luau

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Loader = require("./loader")

local Shared = Loader.root("game/shared", "Shared")
local Client = Loader.root("game/client", "Client")

local errors: { string } = {}

local function signal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
		Wait = function()
			return coroutine.yield()
		end,
	}
end

-- Lune's instances have no events: each `x.Event:Connect(fn)` is kept here instead, to fire by hand
type Hook = { target: any, event: string, fn: (...any) -> () }
local hooks: { Hook } = {}
local function fire(target: any, event: string, ...: any)
	for _, hook in hooks do
		if hook.target == target and hook.event == event then
			local ok, err = pcall(hook.fn, ...)
			if not ok then
				print(("ERROR %s.%s: %s"):format(tostring(target), event, tostring(err)))
				table.insert(errors, ("%s.%s: %s"):format(tostring(target), event, tostring(err)))
			end
		end
	end
end
Loader.transform = function(_path, source)
	source = source:gsub("([%w_%.%(%)\"]+)%.([%w]+):Connect%(", function(target, event)
		return ("__connect(%s, %q, "):format(target, event)
	end)
	source = source:gsub('Instance%.new%("BindableEvent"%)', "__bindable()")
	source = source:gsub("([%w_%.]+):GetPivot%(%)", "__pivot(%1)")
	source = source:gsub("([%w_]+):Play%(%)", "__play(%1)")
	source = source:gsub("([%w_%.]+):PivotTo%(", "__pivotTo(%1, ")
	return source
end

local remotes = {}
local function remote(name)
	remotes[name] = remotes[name] or { Name = name, FireServer = function() end, OnClientEvent = signal() }
	return remotes[name]
end
local remotesFolder = {
	WaitForChild = function(_self, name)
		return remote(name)
	end,
}
local replicatedStorage = {
	WaitForChild = function(_self, name)
		if name == "Shared" then
			return Shared
		end
		return remotesFolder
	end,
	FindFirstChild = function()
		return nil
	end,
}

local playerGui = roblox.Instance.new("Folder")
local attributes = { Coins = 12345, Rate = 10, Speed = 120, Island = 1 }
local localPlayer = {
	UserId = 1,
	Name = "Tester",
	GetAttribute = function(_self, name)
		return attributes[name]
	end,
	WaitForChild = function()
		return playerGui
	end,
	GetAttributeChangedSignal = function()
		return signal()
	end,
}

local dataModel = roblox.Instance.new("DataModel")
local workspaceInstance = dataModel:GetService("Workspace")
local fakeWorkspace = setmetatable({
	GetServerTimeNow = function()
		return os.time()
	end,
	GetAttribute = function()
		return nil
	end,
	CurrentCamera = { ViewportSize = roblox.Vector2.new(1280, 720), CFrame = roblox.CFrame.new() },
}, {
	__index = function(_self, key)
		return (workspaceInstance :: any)[key]
	end,
})

local function service(name: string): any
	if name == "ReplicatedStorage" then
		return replicatedStorage
	elseif name == "Players" then
		return { LocalPlayer = localPlayer, GetPlayers = function() return {} end }
	elseif name == "TweenService" then
		return { Create = function() return { Play = function() end, Completed = signal() } end }
	elseif name == "RunService" then
		return { Heartbeat = signal(), Stepped = signal(), RenderStepped = signal(), IsServer = function() return false end, IsStudio = function() return false end }
	elseif name == "CollectionService" then
		return { GetTagged = function() return {} end, GetInstanceAddedSignal = function() return signal() end, GetInstanceRemovedSignal = function() return signal() end }
	elseif name == "SoundService" then
		return roblox.Instance.new("Folder")
	end
	error("service not stubbed: " .. name)
end

Loader.extraEnv = {
	game = { GetService = function(_self, name) return service(name) end },
	workspace = fakeWorkspace,
	task = task,
	typeof = roblox.typeof or typeof,
	warn = function(...)
		print("warn:", ...)
	end,
	Random = {
		new = function()
			return { NextNumber = function(_self, a, b) return (a or 0) + ((b or 1) - (a or 0)) * math.random() end }
		end,
	},
	TweenInfo = { new = function() return {} end },
	__pivot = function()
		return roblox.CFrame.new()
	end,
	__pivotTo = function() end,
	__play = function() end,
	__connect = function(target, event, fn)
		table.insert(hooks, { target = target, event = event, fn = fn })
		return { Disconnect = function() end }
	end,
	__bindable = function()
		local list = {}
		return {
			Event = { Connect = function(_self, fn) table.insert(list, fn) end },
			Fire = function(_self, ...)
				for _, fn in list do
					fn(...)
				end
			end,
		}
	end,
}

local function try(what: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		print("ERROR " .. what .. ": " .. tostring(err))
		table.insert(errors, what .. ": " .. tostring(err))
	end
end

local Store = Loader.require(Client.Store)
local UI = Client.UI
local Theme = Loader.require(UI.Theme)
local Windows = Loader.require(UI.Windows)
Store.init()
local gui = roblox.Instance.new("ScreenGui")
gui.Parent = playerGui
local root
try("root", function()
	root = Theme.root(gui)
end)
assert(gui.ZIndexBehavior == roblox.Enum.ZIndexBehavior.Sibling, "frames draw over their parents (a window never hides its content)")
for _, name in { "HUD", "GrowingEggs", "ShopWindow", "BagWindow", "IndexWindow", "FuseWindow", "TrailWindow", "MutateWindow", "StoreWindow", "DailyWindow", "FoodWindow", "GearWindow", "Notify", "Reveal" } do
	try(name .. ".mount", function()
		Loader.require(UI[name]).mount(root)
	end)
end

-- A player with eggs, creatures (one placed, one mutated and snapped) and room for more
Store.data = {
	coins = 12345,
	eggs = { ["1"] = 2, ["3"] = 1 },
	golden = { ["2"] = 1 },
	creatures = { a = { s = "Cat", m = "Normal" }, b = { s = "Fox", m = "Golden", g = "Mega" }, c = { s = "Bee", m = "Neon" } },
	placed = { "a" },
	incubators = 3,
	machines = 0,
	incubating = { ["1"] = { tier = 1, start = os.time(), x = 0, z = 0 } },
	pens = 3,
	storage = 1,
	pasture = 1,
	shop = { window = -1, bought = {} },
	daily = { day = -1, progress = {}, claimed = false },
	food = {},
	fedUntil = 0,
	bat = 1,
	traps = 0,
	seat = "",
	seats = { Cloud = true },
	treadmill = 1,
	index = { Dog = true, Cat = true, Bunny = true, Bear = true, Fox = true },
	indexClaimed = {},
	trails = { Green = true },
	trail = "Green",
}
for _, name in { "Bag", "Shop", "Index", "Fuse", "Trails", "Mutate", "Store", "Daily", "Food", "Gear" } do
	try("open " .. name, function()
		assert(Windows.open(name), name .. " is registered")
	end)
end
-- Every Bag tab, by pressing it
if #errors > 0 then
	process.exit(1)
end
local bag = (root :: any):FindFirstChild("🎒 Bag")
assert(bag, "the Bag window")
local tabs = {}
for _, button in (bag:FindFirstChild("Tabs") :: any):GetChildren() do
	if button:IsA("TextButton") then
		table.insert(tabs, button)
	end
end
assert(#tabs == 3, "three tabs")
for _, button in tabs do
	try("Bag tab " .. button.Text, function()
		fire(button, "Activated")
	end)
end
-- The HUD's Bag button opens and closes the Bag
local bagButton
for _, d in (root :: any):GetDescendants() do
	if d:IsA("TextLabel") and d.Text == "Bag" and d.Parent and d.Parent:IsA("TextButton") then
		bagButton = d.Parent
	end
end
assert(bagButton, "a Bag button on the HUD")
bag.Visible = false
fire(bagButton, "Activated")
assert(bag.Visible, "the Bag button opens the Bag")
-- A hatch reveal
try("reveal", function()
	Loader.require(UI.Reveal).show("Cat", "Golden", nil)
end)
task.wait(0.5)

if #errors > 0 then
	for _, err in errors do
		print("ERROR " .. err)
	end
	process.exit(1)
end
print("ui test passed")
process.exit(0)
