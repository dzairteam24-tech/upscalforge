-- Brick Farm's client with real Roblox instances (through Lune): builds the screen as Main does, feeds it a
-- player's data, opens the windows and presses the buttons, then runs the farm: crops are built from their tiles,
-- grow a stage (and pop), planting and harvesting by tapping send the right thing. Catches wrong property names
-- and logic errors that only show when the client runs. Run from the repo root:  lune run tests/brickfarm_ui.luau

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Loader = require("./loader")

local Shared = Loader.root("brickfarm/shared", "Shared")
local Client = Loader.root("brickfarm/client", "Client")
local Server = Loader.root("brickfarm/server", "Server")

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
	return { Connect = function() return { Disconnect = function() end } end }
end

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
Loader.transform = function(path, source)
	if string.find(path, "brickfarm/server", 1, true) then
		return source
	end
	source = source:gsub("([%w_%.%(%)\"]+)%.([%w]+):Connect%(", function(target, event)
		return ("__connect(%s, %q, "):format(target, event)
	end)
	source = source:gsub("workspace%.CurrentCamera", "__camera")
	source = source:gsub("workspace:GetServerTimeNow%(%)", "__now()")
	source = source:gsub("workspace:WaitForChild%(", "__wait(")
	return source
end

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
local replicatedStorage = {
	WaitForChild = function(_self, name)
		if name == "Shared" then
			return Shared
		end
		return { WaitForChild = function(_s, n) return remote(n) end }
	end,
}

local playerGui = roblox.Instance.new("Folder")
local localPlayer: any = { UserId = 7, Name = "Tester", WaitForChild = function() return playerGui end, Character = nil }
local runService = { RenderStepped = "RenderStepped", IsServer = function() return false end, IsStudio = function() return true end }
local userInput = { InputBegan = "InputBegan", InputChanged = "InputChanged", InputEnded = "InputEnded" }
local dataModel = roblox.Instance.new("DataModel")
local workspaceInstance = dataModel:GetService("Workspace")
local lighting = dataModel:GetService("Lighting")
local function service(name: string): any
	if name == "ReplicatedStorage" then
		return replicatedStorage
	elseif name == "Players" then
		return { LocalPlayer = localPlayer }
	elseif name == "TweenService" then
		return { Create = function() return { Play = function() end } end }
	elseif name == "RunService" then
		return runService
	elseif name == "UserInputService" then
		return userInput
	elseif name == "SoundService" then
		return { PlayLocalSound = function() end }
	elseif name == "Lighting" then
		return lighting
	end
	error("service not stubbed: " .. name)
end

local now = 100000
local camera = { CFrame = roblox.CFrame.new(0, 40, 0) }
Loader.extraEnv = {
	game = { GetService = function(_self, name) return service(name) end },
	workspace = workspaceInstance,
	task = task,
	TweenInfo = { new = function() return {} end },
	__camera = camera,
	__now = function() return now end,
	__wait = function(name) return workspaceInstance:FindFirstChild(name) end,
	__connect = function(target, event, fn)
		table.insert(hooks, { target = target, event = event, fn = fn })
		return { Disconnect = function() end }
	end,
}

local function try(what: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		print("ERROR " .. what .. ": " .. tostring(err))
		table.insert(errors, what .. ": " .. tostring(err))
	end
end

-- the village, as the server builds it
local Village = Loader.require(Server.Village)
try("Village.build", function()
	Village.build(workspaceInstance)
end)

local Snapshot = Loader.require(Shared.Logic.Snapshot)
local Crops = Loader.require(Shared.Config.Crops)
local Land = Loader.require(Shared.Logic.Land)
local Level = Loader.require(Shared.Logic.Level)

try("Main", function()
	Loader.require(Client["Main.client"])
end)
if #errors > 0 then
	process.exit(1)
end
local FarmController = Loader.require(Client.Controllers.FarmController)
local screen = playerGui:FindFirstChild("BrickFarm")
check("the screen is made", screen ~= nil)

local function dataFor(overrides: any?): any
	local data: any = {
		coins = 250, xp = Level.total(3) + 10, tiles = 8, plots = {}, seeds = { carrot = 6, radish = 2 }, barn = { carrot = 4 },
		stats = { planted = 0, harvested = 0, sold = 0, earned = 0 }, receipts = {}, guide = 0, lastSeen = 0,
	}
	for k, v in overrides or {} do
		data[k] = v
	end
	return data
end
local function send(data: any)
	fire(remote("Data"), "OnClientEvent", Snapshot.of(data, 1))
end
send(dataFor())

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
local function button(root: any, text: string): any
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") and d.Name == "Text" and d.Text == text and d.Parent:IsA("TextButton") then
			return d.Parent
		end
	end
	return nil
end
local function lastSent(): any
	return sent[#sent]
end

check("coins show", has(screen, "250"))
check("the level shows", has(screen, "LEVEL 3"))
check("the guide's first hint", has(screen, "Tap a brown tile"))
check("the seed bar shows the seeds they have", screen:FindFirstChild("carrot", true) ~= nil and screen:FindFirstChild("carrot", true).Visible and not screen:FindFirstChild("tomato", true).Visible)
check("the barn shows how much is in it", has(screen, "4"))
check("land shows its price", has(screen, "+1 tile: " .. Land.cost(9)))

-- the windows and buttons
local seedsButton = button(screen, "SEEDS")
check("a SEEDS button", seedsButton ~= nil)
if seedsButton then
	fire(seedsButton, "Activated")
	check("SEEDS opens the shop", has(screen, "grows in 30s"))
end
local buy10 = button(screen, tostring(Crops.byKey.carrot.seed * 10))
check("a buy-10 carrot button", buy10 ~= nil)
if buy10 then
	fire(buy10, "Activated")
	check("it asks the server", lastSent().name == "BuySeeds" and lastSent().args[1] == "carrot" and lastSent().args[2] == 10)
end
check("locked seeds say their level", has(screen, "unlocks at level"))
local barnButton = button(screen, "BARN")
if barnButton then
	fire(barnButton, "Activated")
end
check("the barn lists the carrots", has(screen, "4 × " .. Crops.byKey.carrot.sell .. " coins"))
local sellAll = button(screen, "SELL ALL · " .. (4 * Crops.byKey.carrot.sell) .. " COINS")
check("sell all, with the total", sellAll ~= nil)
if sellAll then
	fire(sellAll, "Activated")
	check("it sells", lastSent().name == "Sell" and lastSent().args[1] == "all")
end
local land = button(screen, "LAND")
if land then
	fire(land, "Activated")
end
check("LAND asks for land", lastSent().name == "Expand")
-- choosing a seed
local radishSlot = screen:FindFirstChild("radish", true)
fire(radishSlot, "Activated")
check("tapping a seed chooses it", FarmController.selected == "radish")

-- the farm
local tiles = workspaceInstance.Village.Farm1.Tiles
local t1, t2, t3 = tiles.Tile1, tiles.Tile2, tiles.Tile3
t1:SetAttribute("Owned", true)
t2:SetAttribute("Owned", true)
t3:SetAttribute("Owned", true)
-- a carrot planted just now, a radish nearly ready
t1:SetAttribute("Crop", "carrot")
t1:SetAttribute("Planted", now)
t2:SetAttribute("Crop", "radish")
t2:SetAttribute("Planted", now - Crops.byKey.radish.grow * 0.9)
try("refresh", FarmController._refresh)
try("animate", FarmController._animate)
local views = FarmController._views
check("the carrot is built", views[t1] ~= nil and views[t1].stage == 1 and #views[t1].model:GetChildren() > 0)
check("the radish too, nearly ready", views[t2] ~= nil and views[t2].stage == 3)
local brick = views[t1].model:GetChildren()[1]
check("its bricks sit on the tile", math.abs(brick.CFrame.Position.X - t1.CFrame.Position.X) < 4 and brick.CFrame.Position.Y > t1.CFrame.Position.Y)
-- time passes: the radish is ready, rebuilt (it pops)
now += Crops.byKey.radish.grow
try("refresh", FarmController._refresh)
check("the radish grew to ready", views[t2].stage == 4)
-- tapping: harvest the ready radish, plant on the empty tile, the growing carrot says how long
local before = #sent
try("tap ready", function()
	FarmController._act(t2)
end)
check("a ready crop is harvested", #sent == before + 1 and lastSent().name == "Tile" and lastSent().args[1] == 2 and lastSent().args[2] == nil)
check("and gone from the farm at once", views[t2] == nil)
try("refresh", FarmController._refresh)
check("not built again while the server catches up", views[t2] == nil)
FarmController.select("carrot")
try("tap empty", function()
	FarmController._act(t3)
end)
check("an empty tile is planted with the chosen seed", lastSent().name == "Tile" and lastSent().args[1] == 3 and lastSent().args[2] == "carrot")
t1:SetAttribute("Planted", now) -- (planted again just now: growing)
local count = #sent
try("tap growing", function()
	FarmController._act(t1)
end)
check("a growing crop isn't sent", #sent == count)
check("it says when it'll be ready", has(screen, "ready in"))
try("tap not owned", function()
	FarmController._act(tiles.Tile20)
end)
check("land they don't have says how to get it", has(screen, "LAND button"))
-- the server's harvest message: the "+N" effect and a level up banner
fire(remote("Harvested"), "OnClientEvent", 2, "radish", 2, 4)
fire(remote("LevelUp"), "OnClientEvent", 4, { "corn" })
check("a level up banner names the new seeds", has(screen, "LEVEL 4!") and has(screen, "Corn"))
-- the harvested crop gone on the server: it stays gone
t2:SetAttribute("Crop", "")
try("refresh", FarmController._refresh)
check("an empty tile has no crop", views[t2] == nil)
-- the guide moves on
send(dataFor({ stats = { planted = 1, harvested = 0, sold = 0, earned = 0 } }))
check("the guide's next hint", has(screen, "tap it to harvest"))

if #errors == 0 then
	print(("%d passed, 0 failed"):format(passed))
else
	print(("%d passed, %d failed"):format(passed, #errors))
end
process.exit(if #errors > 0 then 1 else 0)
