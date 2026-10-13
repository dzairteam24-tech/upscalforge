-- Gem Dig's client with real Roblox instances (through Lune): builds the whole screen as Main does, feeds it a
-- player's data, opens every window, presses the buttons, and drives the DIG button, to catch wrong property names
-- and logic errors that only show when the UI runs. Run from the repo root:  lune run tests/gemdig_ui.luau

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Loader = require("./loader")

local Shared = Loader.root("gemdig/shared", "Shared")
local Client = Loader.root("gemdig/client", "Client")

local errors: { string } = {}
local passed = 0
local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		print("FAIL: " .. name .. (if detail then " (" .. detail .. ")" else ""))
		table.insert(errors, name)
	end
end

local function signal()
	return {
		Connect = function()
			return { Disconnect = function() end }
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
	source = source:gsub("([%w_]+):Play%(%)", "__play(%1)")
	source = source:gsub("workspace%.CurrentCamera", "__camera")
	source = source:gsub("workspace:Raycast%(", "__raycast(")
	source = source:gsub("Instance%.new%(\"Highlight\"%)", "__highlight()")
	return source
end

-- remotes: record what the client sends
local sent: { { name: string, args: { any } } } = {}
local remotes = {}
local function remote(name: string)
	if not remotes[name] then
		remotes[name] = {
			Name = name,
			FireServer = function(_self, ...)
				table.insert(sent, { name = name, args = { ... } })
			end,
			OnClientEvent = signal(),
		}
	end
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
local attributes = { Plot = 1 }
local character: any = nil
local localPlayer = {
	UserId = 7,
	Name = "Tester",
	GetAttribute = function(_self, name)
		return attributes[name]
	end,
	WaitForChild = function()
		return playerGui
	end,
	Character = nil :: any,
}

local userInput = { InputBegan = signal(), InputChanged = signal(), InputEnded = signal(), GetMouseLocation = function() return roblox.Vector2.new(640, 360) end }
local runService = { Heartbeat = signal(), RenderStepped = signal(), IsServer = function() return false end, IsStudio = function() return true end }
local function service(name: string): any
	if name == "ReplicatedStorage" then
		return replicatedStorage
	elseif name == "Players" then
		return { LocalPlayer = localPlayer, GetPlayers = function() return {} end }
	elseif name == "TweenService" then
		return { Create = function() return { Play = function() end } end }
	elseif name == "RunService" then
		return runService
	elseif name == "UserInputService" then
		return userInput
	elseif name == "GuiService" then
		return { GetGuiInset = function() return roblox.Vector2.new(0, 36) end }
	elseif name == "Debris" then
		return { AddItem = function() end }
	elseif name == "SoundService" then
		return roblox.Instance.new("Folder")
	end
	error("service not stubbed: " .. name)
end

local dataModel = roblox.Instance.new("DataModel")
local workspaceInstance = dataModel:GetService("Workspace")
local cameraLook = roblox.Vector3.new(0, -1, 0)
local rayHit: any = nil -- what the next raycast finds
local rays: { any } = {}

Loader.extraEnv = {
	game = { GetService = function(_self, name) return service(name) end },
	workspace = workspaceInstance,
	task = task,
	typeof = roblox.typeof or typeof,
	warn = function(...)
		print("warn:", ...)
	end,
	RaycastParams = { new = function() return {} end },
	TweenInfo = { new = function() return {} end },
	__camera = {
		CFrame = { LookVector = nil :: any },
		ViewportPointToRay = function()
			return { Origin = roblox.Vector3.zero, Direction = roblox.Vector3.new(0, 0, -1) }
		end,
	},
	__raycast = function(origin, direction)
		table.insert(rays, { origin = origin, direction = direction })
		return if rayHit then { Instance = rayHit } else nil
	end,
	__highlight = function()
		return {} -- (a plain table: Lune can't make a Highlight that takes properties)
	end,
	__play = function() end,
	__connect = function(target, event, fn)
		table.insert(hooks, { target = target, event = event, fn = fn })
		return { Disconnect = function() end }
	end,
}
-- the camera looks along `cameraLook`
Loader.extraEnv.__camera.CFrame = setmetatable({}, { __index = function(_self, key) if key == "LookVector" then return cameraLook end return nil end })

local function try(what: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		print("ERROR " .. what .. ": " .. tostring(err))
		table.insert(errors, what .. ": " .. tostring(err))
	end
end

local Store = Loader.require(Client.Store)
local Snapshot = Loader.require(Shared.Logic.Snapshot)
local Gear = Loader.require(Shared.Config.Gear)
Store.init()
local screen = roblox.Instance.new("ScreenGui")
screen.Parent = playerGui

local UI = Client.UI
local windows: any = {}
for _, name in { "BagWindow", "ShopWindow", "StoreWindow", "RebirthWindow", "DailyWindow", "OfflineWindow" } do
	try(name .. ".new", function()
		windows[name] = Loader.require(UI[name]).new(screen)
	end)
end
local opened = { bag = 0, shop = 0, store = 0, rebirth = 0, daily = 0 }
try("Hud.init", function()
	Loader.require(UI.Hud).init(screen, {
		bag = function() opened.bag += 1 end,
		shop = function() opened.shop += 1 end,
		store = function() opened.store += 1 end,
		rebirth = function() opened.rebirth += 1 end,
		daily = function() opened.daily += 1 end,
	})
end)
local storeOpens = 0
try("DigController.init", function()
	Loader.require(Client.Controllers.DigController).init(screen, function()
		storeOpens += 1
	end)
end)
try("Guide.init", function()
	Loader.require(Client.Controllers.Guide).init(screen)
end)
try("Effects.init", function()
	Loader.require(Client.Effects).init()
end)
if #errors > 0 then
	process.exit(1)
end

-- A player's data, as the server would send it
local function dataFor(overrides: any?): any
	local data: any = {
		coins = 12345, shovel = 2, pack = 2, items = { ["1"] = { g = "Ruby", s = "Big", m = "Golden" }, ["2"] = { g = "Quartz", s = "Normal" }, ["3"] = { g = "Quartz", s = "Normal" } },
		nextId = 4, found = { Quartz = true, Ruby = true }, stats = { dug = 40, sold = 3, earned = 500 }, deepest = 12, seed = 1, lastSeen = os.time(),
		rebirths = 1, checkpoint = 10, passes = {}, boostUntil = os.time() + 600, daily = { last = 0, streak = 2 }, receipts = {},
	}
	for k, v in overrides or {} do
		data[k] = v
	end
	return data
end
local function send(data: any)
	fire(remote("Data"), "OnClientEvent", Snapshot.of(data, os.time()))
end
send(dataFor())
check("the client has its data", Store.data ~= nil and Store.data.coins == 12345 and Store.data.rebirths == 1)

-- every window opens
for name, w in windows do
	try("open " .. name, function()
		w.open()
		check(name .. " opens", w.frame.Visible)
		w.close()
		check(name .. " closes", not w.frame.Visible)
	end)
end

-- the Bag lists the gems, grouped, with the multiplier applied
local function texts(root: any): { string }
	local list = {}
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			table.insert(list, d.Text)
		end
	end
	return list
end
local function has(root: any, needle: string): boolean
	for _, t in texts(root) do
		if string.find(t, needle, 1, true) then
			return true
		end
	end
	return false
end
check("the Bag shows the golden big ruby", has(windows.BagWindow.frame, "Golden Big Ruby"))
check("and the multiplier in its heading", has(windows.BagWindow.frame, "coins x"))
check("the catalog shows what's found and what's not", has(windows.BagWindow.frame, "Catalog  2 / 6") and has(windows.BagWindow.frame, "???"))
check("the Shop shows what each shovel digs to", has(windows.ShopWindow.frame, "digs down to layer 16") and has(windows.ShopWindow.frame, "In use"))
check("the Store lists passes and products", has(windows.StoreWindow.frame, "2x Coins") and has(windows.StoreWindow.frame, "Coin Pack L") and has(windows.StoreWindow.frame, "(test: free)"))

-- buttons
local function button(root: any, text: string): any
	for _, d in root:GetDescendants() do
		if d:IsA("TextButton") and d.Text == text then
			return d
		end
	end
	return nil
end
local function sentCount(): number
	return #sent
end
local function lastSent(): any
	return sent[#sent]
end
for _, case in {
	{ "Town", "Teleport", "surface" },
	{ "My Mine", "Teleport", "plot" },
	{ "Dig Down", "Teleport", "depth" },
	{ "New Mine", "ResetMine", nil },
} do
	local b = button(screen, case[1])
	check("a " .. case[1] .. " button", b ~= nil)
	if b then
		local before = sentCount()
		fire(b, "Activated")
		check(case[1] .. " sends " .. case[2], sentCount() == before + 1 and lastSent().name == case[2] and lastSent().args[1] == case[3])
	end
end
for _, case in { { "Bag", "bag" }, { "Shop", "shop" }, { "Store", "store" }, { "Rebirth", "rebirth" }, { "Daily", "daily" } } do
	local b = button(screen, case[1])
	check("a " .. case[1] .. " button", b ~= nil)
	if b then
		fire(b, "Activated")
		check(case[1] .. " opens its window", opened[case[2]] == 1)
	end
end

-- the Store: buying a pass asks the server; an owned one says Owned
do
	local buy = button(windows.StoreWindow.frame, "R$ 399")
	check("a 2x Coins buy button", buy ~= nil)
	if buy then
		fire(buy, "Activated")
		check("it asks the server for the pass", lastSent().name == "BuyRobux" and lastSent().args[1] == "pass" and lastSent().args[2] == "Coins2")
	end
	send(dataFor({ passes = { Coins2 = true } }))
	check("an owned pass shows Owned", has(windows.StoreWindow.frame, "Owned") and button(windows.StoreWindow.frame, "R$ 399") == nil)
	local boost = button(windows.StoreWindow.frame, "R$ 79")
	check("the boost shows its time while active", boost == nil and has(windows.StoreWindow.frame, "Active "))
end

-- the Shop: the next shovel is buyable, the one after is locked
do
	send(dataFor({ coins = 100000 }))
	local buy = button(windows.ShopWindow.frame, "Buy  " .. Gear.SHOVELS[3].price)
	check("a buy button for the next shovel", buy ~= nil)
	if buy then
		fire(buy, "Activated")
		check("it asks for shovel 3", lastSent().name == "Buy" and lastSent().args[1] == "shovel" and lastSent().args[2] == 3)
	end
	check("later ones are locked", button(windows.ShopWindow.frame, "Locked") ~= nil)
end

-- Rebirth: nothing happens while it can't; when it can, a confirm first
do
	send(dataFor())
	check("not ready: the reason is shown", has(windows.RebirthWindow.frame, "Reach layer"))
	local b = button(windows.RebirthWindow.frame, "Rebirth")
	local before = sentCount()
	fire(b, "Activated")
	check("pressing it does nothing yet", sentCount() == before)
	send(dataFor({ deepest = 33, coins = 5000000 }))
	check("ready: it says so", has(windows.RebirthWindow.frame, "Ready!"))
	b = button(windows.RebirthWindow.frame, "Rebirth")
	fire(b, "Activated")
	check("the first press asks to confirm", b.Text == "Tap again to confirm" and sentCount() == before)
	fire(b, "Activated")
	check("the second sends Rebirth and closes", lastSent().name == "Rebirth" and not windows.RebirthWindow.frame.Visible)
end

-- Daily: claims only when waiting
do
	send(dataFor())
	local claim = button(windows.DailyWindow.frame, "Claim")
	check("a claim button", claim ~= nil)
	local before = sentCount()
	fire(claim, "Activated")
	check("claiming sends Daily", sentCount() == before + 1 and lastSent().name == "Daily")
	send(dataFor({ daily = { last = math.floor(os.time() / 86400), streak = 3 } }))
	local waiting = button(windows.DailyWindow.frame, "Come back tomorrow")
	check("after claiming: come back tomorrow", waiting ~= nil)
	before = sentCount()
	fire(waiting, "Activated")
	check("and pressing it sends nothing", sentCount() == before)
end

-- the drone's welcome back
do
	fire(remote("Offline"), "OnClientEvent", 5000, 2 * 3600, true)
	check("the welcome-back window opens with the coins", windows.OfflineWindow.frame.Visible and has(windows.OfflineWindow.frame, "+5000 coins"))
	check("and tells how to raise the cap", has(windows.OfflineWindow.frame, "Long Offline Miner"))
	windows.OfflineWindow.close()
end

-- DIG: the button, looking down, finds the cube under the player and asks the server to dig it
do
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Position = roblox.Vector3.new(0, 3, 0)
	local model = roblox.Instance.new("Model")
	root.Parent = model
	localPlayer.Character = model
	local block = roblox.Instance.new("Part")
	block.Name = "Block"
	block.Position = roblox.Vector3.new(0, -3, 0)
	block:SetAttribute("Owner", 7)
	block:SetAttribute("X", 3)
	block:SetAttribute("L", 2)
	block:SetAttribute("Z", 3)
	rayHit = block
	cameraLook = roblox.Vector3.new(0, -1, 0)
	local dig = button(screen, "DIG")
	check("a DIG button", dig ~= nil)
	local before = sentCount()
	fire(runService, "Heartbeat", 0.016)
	check("not pressed: nothing is dug", sentCount() == before)
	fire(dig, "InputBegan", { UserInputType = roblox.Enum.UserInputType.MouseButton1 })
	fire(runService, "Heartbeat", 0.016)
	check("pressed, looking down: it digs the cube under him", sentCount() == before + 1 and lastSent().name == "Dig" and lastSent().args[1] == 3 and lastSent().args[2] == 2 and lastSent().args[3] == 3)
	check("the first ray went down", rays[#rays].direction.Y < 0)
	-- the shovel's cooldown paces it: straight away again, nothing more
	fire(runService, "Heartbeat", 0.016)
	check("not faster than the shovel swings", sentCount() == before + 1)
	task.wait(0.5)
	fire(runService, "Heartbeat", 0.016)
	check("then again", sentCount() == before + 2)
	-- looking ahead: the first ray goes forward
	cameraLook = roblox.Vector3.new(0, 0, -1)
	rays = {}
	task.wait(0.5)
	fire(runService, "Heartbeat", 0.016)
	check("looking ahead it digs in front", rays[1] ~= nil and math.abs(rays[1].direction.Z) > 0.5 * 9)
	fire(dig, "InputEnded", { UserInputType = roblox.Enum.UserInputType.MouseButton1 })
	local after = sentCount()
	task.wait(0.5)
	fire(runService, "Heartbeat", 0.016)
	check("released: it stops", sentCount() == after)
	-- someone else's cube is never dug
	block:SetAttribute("Owner", 99)
	fire(dig, "InputBegan", { UserInputType = roblox.Enum.UserInputType.MouseButton1 })
	task.wait(0.5)
	fire(runService, "Heartbeat", 0.016)
	check("a cube of another player's mine is ignored", sentCount() == after)
	fire(dig, "InputEnded", { UserInputType = roblox.Enum.UserInputType.MouseButton1 })
	block:SetAttribute("Owner", 7)
	-- Auto without the pass opens the Store
	local auto = button(screen, "Auto (pass)")
	check("an Auto button that asks for the pass", auto ~= nil)
	if auto then
		fire(auto, "Activated")
		check("tapping it opens the Store", storeOpens == 1)
	end
	-- with the pass it switches on and digs by itself
	send(dataFor({ passes = { AutoDig = true } }))
	auto = button(screen, "Auto: off")
	check("with the pass it says off", auto ~= nil)
	if auto then
		fire(auto, "Activated")
		check("and ON after a tap", auto.Text == "Auto: ON")
		local n = sentCount()
		task.wait(0.5)
		fire(runService, "Heartbeat", 0.016)
		check("Auto digs without holding anything", sentCount() == n + 1)
		fire(auto, "Activated")
		check("tapping again turns it off", auto.Text == "Auto: off")
	end
end

-- the first-minutes guide
do
	local function guideLine(): string
		for _, d in screen:GetChildren() do
			if d:IsA("TextLabel") and d.TextSize ~= nil and d.Visible and d.Position.Y.Offset == 56 then
				return d.Text
			end
		end
		return ""
	end
	send(dataFor({ stats = { dug = 0, sold = 0, earned = 0 }, items = {}, shovel = 1, pack = 1, coins = 0, rebirths = 0 }))
	task.wait(0.6)
	check("a new player is told to dig", string.find(guideLine(), "hold DIG", 1, true) ~= nil, guideLine())
	send(dataFor({ stats = { dug = 8, sold = 0, earned = 0 }, items = { ["1"] = { g = "Quartz", s = "Normal" }, ["2"] = { g = "Quartz", s = "Normal" }, ["3"] = { g = "Quartz", s = "Normal" }, ["4"] = { g = "Quartz", s = "Normal" }, ["5"] = { g = "Quartz", s = "Normal" }, ["6"] = { g = "Quartz", s = "Normal" } }, shovel = 1, pack = 1, coins = 0, rebirths = 0 }))
	task.wait(0.6)
	check("with a filling backpack: go and sell", string.find(guideLine(), "Sell stand", 1, true) ~= nil, guideLine())
	send(dataFor({ stats = { dug = 30, sold = 1, earned = 60 }, items = {}, shovel = 1, pack = 1, coins = 40, rebirths = 0 }))
	task.wait(0.6)
	check("after the first sale: save up for the shovel", string.find(guideLine(), "Stone Shovel", 1, true) ~= nil, guideLine())
	send(dataFor({ stats = { dug = 60, sold = 3, earned = 300 }, items = {}, shovel = 2, pack = 1, coins = 0, rebirths = 0 }))
	task.wait(0.6)
	check("after the first shovel: no more guide", guideLine() == "", guideLine())
end

-- messages
do
	fire(remote("Notify"), "OnClientEvent", "+ Ruby (40 coins)", "Uncommon")
	check("a message shows up", has(screen, "+ Ruby (40 coins)"))
end

if #errors > 0 then
	for _, err in errors do
		print("ERROR " .. err)
	end
	process.exit(1)
end
print(("%d passed, 0 failed"):format(passed))
process.exit(0)
