-- Cubedash's client with real Roblox instances (through Lune): builds the screen as Main does, feeds it a player's
-- data, opens every window and presses the buttons, then runs the course frame by frame: the stages around the
-- runner are built, an orb is picked up, an obstacle is hit, a wall holds and then breaks. Catches wrong property
-- names and logic errors that only show when the client runs. Run from the repo root:  lune run tests/cubedash_ui.luau

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Loader = require("./loader")

local Shared = Loader.root("cubedash/shared", "Shared")
local Client = Loader.root("cubedash/client", "Client")

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

-- Lune's instances have no events: each `x.Event:Connect(fn)` is kept here, to fire by hand
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
	source = source:gsub("workspace%.CurrentCamera", "__camera")
	-- (Lune's parts can't report their velocity)
	source = source:gsub("local vel = rootPart%.AssemblyLinearVelocity", "local vel = __vel")
	source = source:gsub("workspace:GetServerTimeNow%(%)", "__now()")
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
	FindFirstChild = function()
		return nil
	end,
}

local playerGui = roblox.Instance.new("Folder")
local localPlayer: any = { UserId = 7, Name = "Tester", WaitForChild = function() return playerGui end, Character = nil, CharacterAdded = "CharacterAdded" }
local renderSteps: { (number) -> () } = {}
local runService = {
	Heartbeat = "Heartbeat",
	RenderStepped = "RenderStepped",
	IsServer = function() return false end,
	IsStudio = function() return true end,
	BindToRenderStep = function(_self, _name, _priority, fn) table.insert(renderSteps, fn) end,
}
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
		return { TouchEnabled = false, KeyboardEnabled = true }
	elseif name == "SoundService" then
		return { PlayLocalSound = function() end }
	end
	error("service not stubbed: " .. name)
end

local dataModel = roblox.Instance.new("DataModel")
local workspaceInstance = dataModel:GetService("Workspace")
local now = 1000
local camera = { FieldOfView = 70, ViewportSize = roblox.Vector2.new(1280, 720), CFrame = roblox.CFrame.new() }
Loader.extraEnv = {
	game = { GetService = function(_self, name) return service(name) end },
	workspace = workspaceInstance,
	task = task,
	typeof = roblox.typeof or typeof,
	TweenInfo = { new = function() return {} end },
	__camera = camera,
	__now = function() return now end,
	__vel = roblox.Vector3.new(0, 0, -30),
	__play = function() end,
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

local Snapshot = Loader.require(Shared.Logic.Snapshot)
local Stage = Loader.require(Shared.Logic.Stage)
local Layout = Loader.require(Shared.Logic.Layout)
local Economy = Loader.require(Shared.Logic.Economy)
local Obstacles = Loader.require(Shared.Logic.Obstacles)

-- Main, as the game runs it
try("Main", function()
	Loader.require(Client["Main.client"])
end)
if #errors > 0 then
	process.exit(1)
end
local screen = playerGui:FindFirstChild("Cubedash")
check("the screen is made", screen ~= nil)

local function dataFor(overrides: any?): any
	local data: any = {
		coins = 5000, speed = 0, stage = 1, upgrades = { orb = 2 }, rebirths = 0, passes = {}, boostUntil = 0,
		stats = { orbs = 0, smashes = 0, crashes = 0, runs = 0 }, daily = { last = 0, streak = 2 }, receipts = {}, guide = 0, lastSeen = os.time(),
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

check("the speed shows", has(screen, "10"))
check("the wall shows what it needs", has(screen, "WALL 1 NEEDS " .. Economy.needs(1)))
check("the guide's first hint", has(screen, "Grab the glowing orbs"))
-- the windows
for _, case in { { "UPGRADES", "Orb Power" }, { "STORE", "2x Speed" }, { "DAILY", "DAY 7" } } do
	local b = button(screen, case[1])
	check("a " .. case[1] .. " button", b ~= nil)
	if b then
		fire(b, "Activated")
		check(case[1] .. " opens a window with " .. case[2], has(screen, case[2]))
	end
end
do
	local orbLevel = button(screen, Economy.upgradeCost(Economy.upgrade("orb"), 2) .. " coins")
	check("Orb Power's next level, priced", orbLevel ~= nil)
	if orbLevel then
		fire(orbLevel, "Activated")
		check("buying it asks the server", lastSent().name == "Buy" and lastSent().args[1] == "orb")
	end
	local pass = button(screen, "R$ 399")
	check("the 2x Speed pass button", pass ~= nil)
	if pass then
		fire(pass, "Activated")
		check("it asks the server", lastSent().name == "BuyRobux" and lastSent().args[2] == "Orbs2")
	end
	send(dataFor({ passes = { Orbs2 = true } }))
	check("owned shows OWNED", button(screen, "OWNED") ~= nil)
	local claim = button(screen, "CLAIM")
	check("a claim button", claim ~= nil)
	if claim then
		fire(claim, "Activated")
		check("it claims", lastSent().name == "Daily")
	end
	local restart = button(screen, "RESTART")
	if restart then
		fire(restart, "Activated")
	end
	check("restart asks the server", lastSent().name == "Restart")
end
check("rebirth hidden before the course is beaten", button(screen, "REBIRTH") == nil or not button(screen, "REBIRTH").Visible)

-- the runner
local character = { GetDescendants = function() return {} end }
local root = roblox.Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Size = roblox.Vector3.new(2, 2, 1)
local humanoid = { HipHeight = 2, WalkSpeed = 20 }
character.FindFirstChild = function(_self, n) return if n == "HumanoidRootPart" then root else nil end
character.WaitForChild = function(_self, n) return if n == "HumanoidRootPart" then root elseif n == "Humanoid" then humanoid else nil end
character.PivotTo = function(_self, cf)
	root.CFrame = cf
end
localPlayer.Character = character
fire(localPlayer, "CharacterAdded", character)
task.wait(0.05)
local function standAt(stage: number, x: number, d: number, feet: number?)
	root.CFrame = roblox.CFrame.new(Layout.toWorld(stage, x, d) + roblox.Vector3.new(0, 3 + (feet or 0), 0))
end
local function frame()
	fire(runService, "RenderStepped", 1 / 60)
	for _, fn in renderSteps do
		local ok, err = pcall(fn, 1 / 60)
		if not ok then
			print("ERROR render step: " .. tostring(err))
			table.insert(errors, tostring(err))
		end
	end
end
local function sentNamed(name: string): { any }
	local list = {}
	for _, s in sent do
		if s.name == name then
			table.insert(list, s)
		end
	end
	return list
end

standAt(1, 0, 5)
frame()
local local1 = workspaceInstance:FindFirstChild("Local1")
check("stage 1 is built on this screen", local1 ~= nil and local1:FindFirstChild("Obstacles") ~= nil and local1:FindFirstChild("Wall") ~= nil)
check("with its orbs", local1 and #local1.Orbs:GetChildren() == #Stage.generate(1).orbs)
check("a fresh run of it", #sentNamed("RunStart") >= 1 and sentNamed("RunStart")[#sentNamed("RunStart")].args[1] == 1)
check("stage 2 isn't (not reached)", workspaceInstance:FindFirstChild("Local2") == nil)
-- an orb
local orb = Stage.generate(1).orbs[1]
standAt(1, orb.x, orb.d, orb.y - 3)
frame()
local got = #sentNamed("Collect")
check("the orb (and any in the magnet's reach), picked up", got >= 1 and sentNamed("Collect")[1].args[2] == 1 and sentNamed("Collect")[1].args[1] == 1)
frame()
check("and not again", #sentNamed("Collect") == got)
-- an obstacle: a moment the first laser is on
local laser
for _, o in Stage.generate(1).obstacles do
	if o.kind == "laser" and not laser then
		laser = o
	end
end
check("stage 1 has a laser", laser ~= nil)
if laser then
	now = 2000
	while not Obstacles.laserOn(laser, now) do
		now += 0.05
	end
	task.wait(1.3) -- (past the safe moment after starting)
	standAt(1, 0, laser.d)
	frame()
	check("the laser crashes them", #sentNamed("Crash") == 1 and sentNamed("Crash")[1].args[2] == "laser")
	task.wait(0.7)
	check("and they start again at the stage's start (no checkpoint yet)", math.abs(Layout.fromZ(root.CFrame.Position.Z) - 1) < 1e-9 and select(2, Layout.fromZ(root.CFrame.Position.Z)) < 10)
	check("with a fresh run", sentNamed("RunStart")[#sentNamed("RunStart")].args[1] == 1)
end
-- a checkpoint
task.wait(1.3)
local cp = Stage.checkpoint(1, 1)
now = 5000
standAt(1, 0, cp + 2, 30) -- (high in the air, clear of anything)
frame()
check("checkpoint 1 is passed", has(screen, "CHECKPOINT"))
-- the wall: not fast enough
local length = Economy.stageLength(1)
standAt(1, 0, length - 5, 30)
frame()
check("not fast enough: told so", has(screen, "NOT FAST ENOUGH"))
check("the wall is still there", local1:FindFirstChild("Wall") ~= nil)
-- fast enough
send(dataFor({ speed = Economy.needs(1) }))
task.wait(2.5)
standAt(1, 0, length - 5, 30)
frame()
check("fast enough: SMASH", #sentNamed("Smash") == 1 and has(screen, "SMASH!"))
local wall = local1:FindFirstChild("Wall")
local flying = wall ~= nil
if wall then
	for _, cube in wall:GetChildren() do
		if cube.Anchored then
			flying = false
		end
	end
end
check("the wall's cubes fly", flying)
fire(remote("Smashed"), "OnClientEvent", 1, 25)
send(dataFor({ speed = Economy.needs(1), stage = 2 }))
standAt(2, 0, 10, 30)
frame()
check("stage 2 is built once reached", workspaceInstance:FindFirstChild("Local2") ~= nil and workspaceInstance:FindFirstChild("Local2"):FindFirstChild("Wall") ~= nil)
check("a run of stage 2", sentNamed("RunStart")[#sentNamed("RunStart")].args[1] == 2)
check("the view widened or stayed in range", camera.FieldOfView >= 70 and camera.FieldOfView <= 108)

-- the course beaten: rebirth shows
send(dataFor({ stage = Economy.STAGES + 1, coins = Economy.rebirthCost(0) }))
check("rebirth shows once the course is beaten", button(screen, "REBIRTH") ~= nil and button(screen, "REBIRTH").Visible)
check("the wall label says so", has(screen, "COURSE BEATEN"))

if #errors == 0 then
	print(("%d passed, 0 failed"):format(passed))
else
	print(("%d passed, %d failed"):format(passed, #errors))
end
process.exit(if #errors > 0 then 1 else 0)
