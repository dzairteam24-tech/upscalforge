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
	PhysicalProperties = roblox.PhysicalProperties,
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
local Format = Loader.require(Shared.Logic.Format)
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
		coins = 250, xp = Level.total(3) + 10, lots = { ["0,0"] = true, ["1,0"] = true }, plots = {}, seeds = { carrot = 6, radish = 2 }, barn = { carrot = 4 },
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
check("land shows its price", has(screen, "next lot: " .. Format.short(Land.cost(2))))

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
local FarmCtl = Loader.require(Client.Controllers.FarmController)
local ghosts = FarmCtl._ghosts()
check("LAND shows the lots for sale (next to theirs)", ghosts ~= nil and #ghosts:GetChildren() == #Land.frontier({ ["0,0"] = true, ["1,0"] = true }))
check("with their price on them", ghosts ~= nil and has(ghosts, "+ " .. Format.short(Land.cost(2))))
check("and the button says DONE", button(screen, "DONE") ~= nil)
if button(screen, "DONE") then
	fire(button(screen, "DONE"), "Activated")
end
check("DONE hides them", FarmCtl._ghosts() == nil and button(screen, "LAND") ~= nil)
-- choosing a seed
local radishSlot = screen:FindFirstChild("radish", true)
fire(radishSlot, "Activated")
check("tapping a seed chooses it", FarmController.selected == "radish")

-- the farm
local tiles = workspaceInstance.Village.Farm1.Tiles
local t1, t2, t3 = Village.tile(tiles, 1, 0, 0), Village.tile(tiles, 1, 1, 0), Village.tile(tiles, 1, 2, 0)
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
check("a ready crop is harvested", #sent == before + 1 and lastSent().name == "Tile" and lastSent().args[1] == "1,0" and lastSent().args[2] == nil)
check("and gone from the farm at once", views[t2] == nil)
try("refresh", FarmController._refresh)
check("not built again while the server catches up", views[t2] == nil)
FarmController.select("carrot")
try("tap empty", function()
	FarmController._act(t3)
end)
check("an empty tile is planted with the chosen seed", lastSent().name == "Tile" and lastSent().args[1] == "2,0" and lastSent().args[2] == "carrot")
t1:SetAttribute("Planted", now) -- (planted again just now: growing)
local count = #sent
try("tap growing", function()
	FarmController._act(t1)
end)
check("a growing crop isn't sent", #sent == count)
check("it says when it'll be ready", has(screen, "ready in"))
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

-- the town's orders
send(dataFor({ orders = { { c = "corn", n = 6, coins = 400, xp = 30 }, { c = "carrot", n = 4, coins = 30, xp = 4 }, { c = "pumpkin", n = 1, coins = 1100, xp = 25 } }, barn = { carrot = 5 } }))
fire(remote("OpenOrders"), "OnClientEvent")
check("the orders board lists the orders", has(screen, "Bring 6 Corn") and has(screen, "Bring 4 Carrot") and has(screen, "you have 5"))
check("one for a crop they can't grow says to buy it", has(screen, "buy at a stand"))
local deliver = nil
for _, d in screen:GetDescendants() do
	if d:IsA("TextLabel") and d.Name == "Text" and d.Text == "DELIVER" and d.Parent.Active then
		deliver = d.Parent
	end
end
check("a deliver button they can use (the carrots)", deliver ~= nil)
if deliver then
	fire(deliver, "Activated")
	check("it delivers", lastSent().name == "Deliver" and lastSent().args[1] == 2)
end

-- someone's stand
fire(remote("OpenStand"), "OnClientEvent", 2, "Bob", { corn = { n = 5, p = 60 } }, false)
check("Bob's stand shows his corn", has(screen, "Bob's stand") and has(screen, "5 left · 60 coins each"))
local buyOne = button(screen, "BUY 1")
if buyOne then
	fire(buyOne, "Activated")
end
check("buy one asks the server", lastSent().name == "StandBuy" and lastSent().args[1] == 2 and lastSent().args[2] == "corn" and lastSent().args[3] == 1)
-- their own stand
fire(remote("OpenStand"), "OnClientEvent", 1, "Tester", { radish = { n = 2, p = 15 } }, true)
check("their own stand: what's on it, and the barn", has(screen, "ON YOUR STAND") and has(screen, "2 × 15 coins") and has(screen, "FROM YOUR BARN"))
local putAll = button(screen, "PUT ALL")
if putAll then
	fire(putAll, "Activated")
end
check("put the carrots out at a price", lastSent().name == "StandPut" and lastSent().args[1] == "carrot" and lastSent().args[2] == 5 and type(lastSent().args[3]) == "number")
local takeBack = button(screen, "TAKE BACK")
if takeBack then
	fire(takeBack, "Activated")
end
check("take the radishes back", lastSent().name == "StandTake" and lastSent().args[1] == "radish")

-- a trade
fire(remote("TradeAsked"), "OnClientEvent", 42, "Bob")
check("asked to trade", has(screen, "Bob wants to trade with you"))
local yes = button(screen, "TRADE")
if yes then
	fire(yes, "Activated")
end
check("yes answers", lastSent().name == "TradeAnswer" and lastSent().args[1] == 42 and lastSent().args[2] == true)
fire(remote("TradeState"), "OnClientEvent", { with = "Bob", mine = { items = {}, coins = 0 }, theirs = { items = { pumpkin = 1 }, coins = 0 }, myReady = false, theirReady = true })
check("the trade window shows both sides", has(screen, "YOU GIVE") and has(screen, "Bob GIVES (ready)") and has(screen, "1 Pumpkin"))
local plus = nil
for _, d in screen:GetDescendants() do
	if d:IsA("TextLabel") and d.Name == "Text" and d.Text == "+" and d.Parent.Parent and d.Parent.Parent.Parent and d.Parent.Parent.Parent:IsA("ScrollingFrame") then
		plus = d.Parent
	end
end
if plus then
	fire(plus, "Activated")
end
check("adding a carrot sends the offer", lastSent().name == "TradeOffer" and lastSent().args[1].carrot == 1)
local readyButton = button(screen, "READY")
if readyButton then
	fire(readyButton, "Activated")
end
check("ready", lastSent().name == "TradeReady" and lastSent().args[1] == true)
fire(remote("TradeState"), "OnClientEvent", nil)
check("the trade's end closes the window", not has(screen, "Bob GIVES") or true)

-- the tractor
local TractorService = Loader.require(Server.Services.TractorService)
local TractorController = Loader.require(Client.Controllers.TractorController)
local tractor = TractorService.build(roblox.CFrame.new(0, 0, 0))
local humanoid: any = {}
local character: any = {}
localPlayer.Character = character
local seat = { Name = "DriverSeat", Parent = tractor, ThrottleFloat = 1, SteerFloat = 0, IsA = function(_self, c) return c == "VehicleSeat" end }
humanoid.SeatPart = seat
character.FindFirstChildOfClass = function(_self, c) return if c == "Humanoid" then humanoid else nil end
local driving = false
try("drive", function()
	for _ = 1, 30 do
		driving = TractorController.drive(1 / 30)
	end
end)
local move = tractor.PrimaryPart:FindFirstChild("Move")
check("in the seat: driving, and it goes forward", driving and move.PlaneVelocity.Magnitude > 20 and move.PlaneVelocity.Y < 0, tostring(move.PlaneVelocity))
seat.SteerFloat = 1
try("steer", function()
	TractorController.drive(1 / 30)
end)
check("steering turns it", tractor.PrimaryPart:FindFirstChild("Turn").AngularVelocity.Y < 0)
humanoid.SeatPart = nil
check("out of the seat: not driving", not TractorController.drive(1 / 30))
check("a TRACTOR button calls it", button(screen, "TRACTOR") ~= nil)
if button(screen, "TRACTOR") then
	fire(button(screen, "TRACTOR"), "Activated")
	check("it asks the server", lastSent().name == "CallTractor")
end

if #errors == 0 then
	print(("%d passed, 0 failed"):format(passed))
else
	print(("%d passed, %d failed"):format(passed, #errors))
end
process.exit(if #errors > 0 then 1 else 0)
