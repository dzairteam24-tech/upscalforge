--!strict
-- The course on this phone: each nearby stage's obstacles (moved every frame from the server's clock, so they are
-- where everyone else sees them), its orbs and the wall of cubes at its end. Checks the runner against the
-- obstacles (Logic/Obstacles), picks up orbs, smashes walls, and puts a crashed runner back at their checkpoint.
-- The server checks every pickup and smash against where the character really is.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CourseConfig = require(Shared.Config.Course)
local Economy = require(Shared.Logic.Economy)
local Layout = require(Shared.Logic.Layout)
local Net = require(Shared.Net)
local Obstacles = require(Shared.Logic.Obstacles)
local Progress = require(Shared.Logic.Progress)
local Rng = require(Shared.Logic.Rng)
local Speed = require(Shared.Logic.Speed)
local Stage = require(Shared.Logic.Stage)

local Effects = require(script.Parent.Effects)
local Store = require(script.Parent.Parent.Store)

local CourseController = {}

local LOCAL = Players.LocalPlayer
local W = CourseConfig.WIDTH
local CUBE = W / 8 -- the wall's cubes
local FALL_HIGH = 20 -- how high a falling cube waits
local DARK = Color3.fromRGB(16, 18, 30)
local SAFE_AFTER = 1.2 -- seconds a runner can't crash after starting again

-- what the controller tells the screen (Hud)
CourseController.onBanner = nil :: ((title: string, sub: string?, color: Color3?) -> ())?
CourseController.onProgress = nil :: ((stage: number, share: number, checkpoint: number) -> ())?
CourseController.onWallNear = nil :: ((needs: number, stat: number) -> ())?

type ObstacleView = { o: Obstacles.Obstacle, model: Model, parts: { [string]: BasePart } }
type StageView = {
	stage: number,
	folder: Folder,
	obstacles: { ObstacleView },
	orbs: { [number]: BasePart },
	wall: Model?,
}

local views: { [number]: StageView } = {}
local root: BasePart? = nil
local humanoid: Humanoid? = nil

-- the run: which stage, which orbs are gone, the last checkpoint passed
local run = { stage = 0, got = {} :: { [number]: boolean }, checkpoint = 0, finished = false, wallTold = false }
local safeUntil = 0
local crashing = false
local pendingSmash: { stage: number, at: number }? = nil
local predicted = 0 -- speed picked up that the server hasn't confirmed yet

local function theme(stage: number): CourseConfig.Theme
	return CourseConfig.THEMES[(stage - 1) % #CourseConfig.THEMES + 1]
end

local function stat(): number
	local data = Store.data
	return if data then data.stat + predicted else 0
end

local function newPart(parent: Instance, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Neon
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- The obstacle models (the maths that decides a crash is Logic/Obstacles; these only show it)
local function buildObstacle(parent: Instance, stage: number, o: Obstacles.Obstacle): ObstacleView
	local t = theme(stage)
	local model = Instance.new("Model")
	model.Name = o.kind
	local parts: { [string]: BasePart } = {}
	local z = Layout.startZ(stage) - o.d
	if o.kind == "sweeper" then
		local w = o.w :: number
		parts.body = newPart(model, Vector3.new(w, 7, Obstacles.SWEEPER_THICK * 2), DARK, Enum.Material.Glass)
		parts.body.Transparency = 0.15
		parts.top = newPart(model, Vector3.new(w + 0.2, 0.5, Obstacles.SWEEPER_THICK * 2 + 0.2), t.accent2)
		parts.bottom = newPart(model, Vector3.new(w + 0.2, 0.4, Obstacles.SWEEPER_THICK * 2 + 0.2), t.accent2)
		-- the rail it slides on, high over the lane
		local rail = newPart(model, Vector3.new(W + 4, 0.4, 0.4), t.accent2)
		rail.Transparency = 0.6
		rail.CFrame = CFrame.new(0, 7.6, z)
	elseif o.kind == "spinner" then
		local post = newPart(model, Vector3.new(4, 2.4, 2.4), DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
		post.CFrame = CFrame.new(o.x or 0, 1.4, z) * CFrame.Angles(0, 0, math.pi / 2)
		parts.arm = newPart(model, Vector3.new(o.R :: number, Obstacles.SPINNER_TOP, Obstacles.SPINNER_THICK * 2), t.accent)
		parts.cap = newPart(model, Vector3.new(1.4, 3.4, 3.4), t.accent2, Enum.Material.Neon, Enum.PartType.Cylinder)
		parts.cap.CFrame = CFrame.new(o.x or 0, 3, z) * CFrame.Angles(0, 0, math.pi / 2)
	elseif o.kind == "laser" then
		for _, side in { -1, 1 } do
			local post = newPart(model, Vector3.new(1.2, 4, 1.2), DARK, Enum.Material.Metal)
			post.CFrame = CFrame.new(side * (W / 2 - 0.6), 2, z)
		end
		parts.beam = newPart(model, Vector3.new(W - 1.2, 0.35, 0.35), Color3.fromRGB(255, 40, 80))
		parts.beam.CFrame = CFrame.new(0, 1.3, z)
		parts.glow = newPart(model, Vector3.new(W - 1.2, 1.4, 1.2), Color3.fromRGB(255, 40, 80))
		parts.glow.CFrame = CFrame.new(0, 1.3, z)
	elseif o.kind == "falling" then
		local size = o.size :: number
		parts.cube = newPart(model, Vector3.new(size, size, size), DARK, Enum.Material.Glass)
		parts.cube.Transparency = 0.05
		parts.edge = newPart(model, Vector3.new(size + 0.2, 0.5, size + 0.2), t.accent)
		parts.mark = newPart(model, Vector3.new(size, 0.06, size), t.accent)
		parts.mark.CFrame = CFrame.new(o.x or 0, 0.04, z)
	elseif o.kind == "pendulum" then
		local beam = newPart(model, Vector3.new(W + 4, 1, 1), DARK, Enum.Material.Metal)
		beam.CFrame = CFrame.new(0, Obstacles.PENDULUM_PIVOT + 0.5, z)
		parts.rod = newPart(model, Vector3.new(0.5, o.len :: number, 0.5), Color3.fromRGB(120, 130, 160), Enum.Material.Metal)
		parts.ball = newPart(model, Vector3.new(Obstacles.PENDULUM_BOB * 2, Obstacles.PENDULUM_BOB * 2, Obstacles.PENDULUM_BOB * 2), t.accent2, Enum.Material.Neon, Enum.PartType.Ball)
	end
	model.Parent = parent
	return { o = o, model = model, parts = parts }
end

-- Puts an obstacle where it is at time t
local function moveObstacle(view: ObstacleView, stage: number, t: number)
	local o, parts = view.o, view.parts
	local z = Layout.startZ(stage) - o.d
	if o.kind == "sweeper" then
		local x = Obstacles.sweeperX(o, t)
		parts.body.CFrame = CFrame.new(x, 3.5, z)
		parts.top.CFrame = CFrame.new(x, 7, z)
		parts.bottom.CFrame = CFrame.new(x, 0.2, z)
	elseif o.kind == "spinner" then
		local theta = Obstacles.spinnerAngle(o, t)
		local dir = Vector3.new(math.cos(theta), 0, -math.sin(theta)) -- (d runs along -Z)
		local pivot = Vector3.new(o.x or 0, Obstacles.SPINNER_TOP / 2, z)
		parts.arm.CFrame = CFrame.fromMatrix(pivot + dir * ((o.R :: number) / 2), dir, Vector3.yAxis)
	elseif o.kind == "laser" then
		local on = Obstacles.laserOn(o, t)
		local soon = not on and Obstacles.laserOn(o, t + 0.35)
		parts.beam.Transparency = if on then 0 elseif soon then (if (t * 20) % 2 < 1 then 0.2 else 0.7) else 0.8
		parts.glow.Transparency = if on then 0.7 else 1
	elseif o.kind == "falling" then
		local p = Obstacles.fallPhase(o, t)
		local size = o.size :: number
		local lift
		if p < Obstacles.FALL_FROM then
			local f = p / Obstacles.FALL_FROM
			lift = FALL_HIGH * (1 - f * f * f)
		elseif p <= Obstacles.FALL_TO then
			lift = 0
		else
			local g = (p - Obstacles.FALL_TO) / (1 - Obstacles.FALL_TO)
			lift = FALL_HIGH * g ^ 1.5
		end
		local y = size / 2 + lift
		parts.cube.CFrame = CFrame.new(o.x or 0, y, z)
		parts.edge.CFrame = CFrame.new(o.x or 0, y - size / 2 + 0.25, z)
		-- the mark on the floor brightens as it comes down
		parts.mark.Transparency = if lift == 0 then 0.2 else 0.5 + 0.5 * math.clamp(lift / FALL_HIGH, 0, 1)
	elseif o.kind == "pendulum" then
		local bx, by = Obstacles.pendulumBob(o, t)
		local pivot = Vector3.new(o.x or 0, Obstacles.PENDULUM_PIVOT, z)
		local ball = Vector3.new(bx, by, z)
		parts.ball.CFrame = CFrame.new(ball)
		parts.rod.CFrame = CFrame.lookAt((pivot + ball) / 2, ball) * CFrame.Angles(math.pi / 2, 0, 0)
	end
end

-- An orb: a bright core in a soft shell
local function buildOrb(parent: Instance, stage: number, index: number, orb: Stage.Orb): BasePart
	local t = theme(stage)
	local core = newPart(parent, Vector3.new(1.3, 1.3, 1.3), Color3.new(1, 1, 1), Enum.Material.Neon, Enum.PartType.Ball)
	core.Name = "Orb" .. index
	core.CFrame = CFrame.new(Layout.toWorld(stage, orb.x, orb.d) + Vector3.new(0, orb.y, 0))
	local shell = newPart(core, Vector3.new(2.4, 2.4, 2.4), t.accent2, Enum.Material.Neon, Enum.PartType.Ball)
	shell.Name = "Shell"
	shell.Transparency = 0.55
	shell.CFrame = core.CFrame
	return core
end

local function buildOrbs(view: StageView)
	for _, p in view.orbs do
		p:Destroy()
	end
	table.clear(view.orbs)
	local folder = view.folder:FindFirstChild("Orbs") or Instance.new("Folder")
	folder.Name = "Orbs"
	folder.Parent = view.folder
	for i, orb in Stage.generate(view.stage).orbs do
		if not (run.stage == view.stage and run.got[i]) then
			view.orbs[i] = buildOrb(folder, view.stage, i, orb)
		end
	end
end

-- The wall of cubes at the end of a stage
local function buildWall(view: StageView)
	if view.wall then
		view.wall:Destroy()
	end
	local t = theme(view.stage)
	local model = Instance.new("Model")
	model.Name = "Wall"
	local zFace = Layout.startZ(view.stage) - Economy.stageLength(view.stage)
	local rng = Rng.new(view.stage * 77)
	local rows = math.floor(CourseConfig.WALL_HEIGHT / CUBE)
	for row = 0, rows - 1 do
		for col = 0, 7 do
			for layer = 0, 1 do
				local glow = Rng.float(rng) < 0.32
				local color = if glow then (if Rng.float(rng) < 0.5 then t.accent else t.accent2) else t.floor:Lerp(t.accent, 0.12)
				local cube = newPart(model, Vector3.new(CUBE - 0.15, CUBE - 0.15, CourseConfig.WALL_THICK / 2 - 0.15), color, if glow then Enum.Material.Neon else Enum.Material.Glass)
				cube.CFrame = CFrame.new(-W / 2 + CUBE * (col + 0.5), CUBE * (row + 0.5), zFace - CourseConfig.WALL_THICK / 4 - layer * CourseConfig.WALL_THICK / 2)
				cube.CanCollide = true -- (it really stops them)
			end
		end
	end
	model.Parent = view.folder
	view.wall = model
end

-- Bursts the wall into flying cubes
local function burstWall(view: StageView)
	local wall = view.wall
	if not wall then
		return
	end
	view.wall = nil
	local from = if root then root.CFrame.Position else wall:GetPivot().Position
	for _, cube in wall:GetChildren() do
		if cube:IsA("BasePart") then
			cube.CanCollide = false
			cube.Anchored = false
			local away = (cube.CFrame.Position - from) * Vector3.new(1, 0, 1)
			local push = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, -1)
			cube.AssemblyLinearVelocity = push * math.random(45, 110) + Vector3.new(math.random(-20, 20), math.random(15, 55), -math.random(30, 80))
			cube.AssemblyAngularVelocity = Vector3.new(math.random(-12, 12), math.random(-12, 12), math.random(-12, 12))
			task.delay(1.2 + math.random() * 0.8, function()
				TweenService:Create(cube, TweenInfo.new(0.6), { Transparency = 1, Size = cube.Size * 0.3 }):Play()
			end)
		end
	end
	task.delay(3, function()
		wall:Destroy()
	end)
end

local function buildStage(stage: number): StageView
	local folder = Instance.new("Folder")
	folder.Name = "Local" .. stage
	local view: StageView = { stage = stage, folder = folder, obstacles = {}, orbs = {}, wall = nil }
	local obstacleFolder = Instance.new("Folder")
	obstacleFolder.Name = "Obstacles"
	obstacleFolder.Parent = folder
	for _, o in Stage.generate(stage).obstacles do
		table.insert(view.obstacles, buildObstacle(obstacleFolder, stage, o))
	end
	buildOrbs(view)
	local data = Store.data
	if data and data.stage <= stage then
		buildWall(view)
	end
	folder.Parent = workspace
	return view
end

-- Keeps the stages around the runner built (the one they're on, the one before and the one after)
local function keepBuilt(current: number)
	local data = Store.data
	if not data then
		return
	end
	local last = math.min(Progress.frontier(data), CourseConfig.STAGES)
	for k, view in views do
		if math.abs(k - current) > 1 or k > last then
			view.folder:Destroy()
			views[k] = nil
		end
	end
	for k = math.max(1, current - 1), math.min(last, current + 1) do
		if not views[k] then
			views[k] = buildStage(k)
		end
	end
end

-- A fresh run of a stage: its orbs are back
local function startRun(stage: number)
	run.stage = stage
	run.got = {}
	run.checkpoint = 0
	run.finished = false
	run.wallTold = false
	Net.event("RunStart"):FireServer(stage)
	local view = views[stage]
	if view then
		buildOrbs(view)
	end
end

local function placeAt(stage: number, d: number)
	local character = LOCAL.Character
	if not character then
		return
	end
	local at = Layout.toWorld(stage, 0, d) + Vector3.new(0, 4, 0)
	character:PivotTo(CFrame.lookAt(at, at + Vector3.new(0, 0, -1)))
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	safeUntil = os.clock() + SAFE_AFTER
end

-- Hit an obstacle: burst into cubes, start again at the last checkpoint (or the stage's start)
local function crash(stage: number, kind: string)
	if crashing or not root then
		return
	end
	crashing = true
	Net.event("Crash"):FireServer(stage, kind)
	Effects.shatter(root.CFrame.Position, theme(stage).accent)
	Effects.shake(0.6, 0.35)
	local character = LOCAL.Character
	if character then
		for _, p in character:GetDescendants() do
			if p:IsA("BasePart") or p:IsA("Decal") then
				(p :: any).LocalTransparencyModifier = 1
			end
		end
	end
	if humanoid then
		humanoid.WalkSpeed = 0
	end
	task.delay(0.55, function()
		local back = if run.checkpoint > 0 then Stage.checkpoint(stage, run.checkpoint) else 6
		if run.checkpoint == 0 then
			startRun(stage)
		end
		placeAt(stage, back)
		if character then
			for _, p in character:GetDescendants() do
				if p:IsA("BasePart") or p:IsA("Decal") then
					(p :: any).LocalTransparencyModifier = 0
				end
			end
		end
		if humanoid and Store.data then
			humanoid.WalkSpeed = Speed.walk(Store.data.stat)
		end
		crashing = false
	end)
end

local function collect(view: StageView, index: number, orb: BasePart)
	view.orbs[index] = nil
	run.got[index] = true
	Net.event("Collect"):FireServer(view.stage, index)
	local data = Store.data
	local gain = if data then Progress.orbValue(data, view.stage) else 1
	predicted += gain
	Effects.pickup(orb, root, gain)
end

-- Every frame: obstacles move, orbs fly in, the runner is checked
local function step()
	local data = Store.data
	if not data or not root then
		return
	end
	local position = root.CFrame.Position
	local stage, d = Layout.fromZ(position.Z)
	stage = math.min(stage, CourseConfig.STAGES)
	keepBuilt(stage)
	local t = workspace:GetServerTimeNow()

	-- a new stage, entered from its start: a fresh run
	if stage ~= run.stage and d < 80 then
		startRun(stage)
		if CourseController.onBanner then
			CourseController.onBanner("STAGE " .. stage, string.upper(theme(stage).name), theme(stage).accent)
		end
	end

	for k, view in views do
		local near = math.abs(k - stage) <= 1
		if near then
			for _, ov in view.obstacles do
				local oz = Layout.startZ(k) - ov.o.d
				if math.abs(oz - position.Z) < 260 then
					moveObstacle(ov, k, t)
				end
			end
		end
	end

	local view = views[stage]
	if not view then
		return
	end
	local length = Economy.stageLength(stage)
	local x = position.X
	local feet = position.Y - (if humanoid then humanoid.HipHeight + root.Size.Y / 2 else 3)
	-- obstacles
	if not crashing and os.clock() > safeUntil and stage == run.stage then
		for _, ov in view.obstacles do
			local o = ov.o
			if math.abs(o.d - d) < 16 and Obstacles.hit(o, t, x, feet, d, Obstacles.BODY) then
				crash(stage, o.kind)
				break
			end
		end
	end
	-- orbs: close enough fly in; the rest turn slowly
	local reach = data.magnet
	local orbs = Stage.generate(stage).orbs
	for index, part in view.orbs do
		local orb = orbs[index]
		if math.abs(orb.d - d) < 60 then
			local at = Layout.toWorld(stage, orb.x, orb.d) + Vector3.new(0, orb.y + 0.4 * math.sin(t * 3 + index), 0)
			if (at - position).Magnitude <= reach + 1.5 and stage == run.stage and not crashing then
				collect(view, index, part)
			else
				part.CFrame = CFrame.new(at)
				local shell = part:FindFirstChild("Shell") :: BasePart?
				if shell then
					shell.CFrame = part.CFrame
				end
			end
		end
	end
	-- checkpoints
	for i = 2, 1, -1 do
		if run.checkpoint < i and d >= Stage.checkpoint(stage, i) and stage == run.stage then
			run.checkpoint = i
			Effects.checkpoint()
			if CourseController.onBanner then
				CourseController.onBanner("CHECKPOINT", nil, theme(stage).accent2)
			end
			break
		end
	end
	if CourseController.onProgress then
		CourseController.onProgress(stage, math.clamp(d / length, 0, 1), run.checkpoint)
	end
	-- the wall
	if data.stage == stage and view.wall and not pendingSmash then
		if d >= length - 7 then
			local needs = data.needs :: number
			if stat() >= needs then
				pendingSmash = { stage = stage, at = os.clock() }
				Net.event("Smash"):FireServer(stage)
				burstWall(view)
				Effects.smash(Layout.toWorld(stage, 0, length) + Vector3.new(0, 8, 0), theme(stage).accent)
				if CourseController.onBanner then
					CourseController.onBanner("SMASH!", "STAGE " .. stage .. " CLEAR", theme(stage).accent)
				end
			elseif not run.wallTold then
				run.wallTold = true
				if CourseController.onWallNear then
					CourseController.onWallNear(needs, stat())
				end
				Effects.shake(0.25, 0.2)
				-- (not fast enough: back to the start, where the orbs are waiting again)
				task.delay(2.2, function()
					local now = Store.data
					if now and now.stage == stage and run.stage == stage and not crashing then
						startRun(stage)
						placeAt(stage, 6)
					end
				end)
			end
		end
	elseif data.stage > stage and not run.finished and d >= length - 6 and stage == run.stage then
		run.finished = true
		Net.event("Finish"):FireServer(stage)
	end
	-- a smash the server never agreed to: put the wall back
	if pendingSmash and os.clock() - pendingSmash.at > 3 then
		local k = pendingSmash.stage
		pendingSmash = nil
		if data.stage == k and views[k] then
			buildWall(views[k])
			startRun(k)
			placeAt(k, 6)
		end
	end
end

local function onCharacter(character: Model)
	root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	crashing = false
	safeUntil = os.clock() + SAFE_AFTER
	Effects.attach(character)
end

function CourseController.init()
	Store.onChanged(function()
		predicted = 0
		local data = Store.data
		-- a wall smashed (here or by a purchase): gone; a wall back (rebirth): built
		for k, view in views do
			if data.stage > k and view.wall and not pendingSmash then
				burstWall(view)
			elseif data.stage <= k and not view.wall then
				buildWall(view)
			end
		end
	end)
	Net.event("Smashed").OnClientEvent:Connect(function(stage: number, coins: number)
		if pendingSmash and pendingSmash.stage == stage then
			pendingSmash = nil
		end
		Effects.coins(coins)
	end)
	Net.event("Teleported").OnClientEvent:Connect(function(stage: number)
		run.stage = 0 -- (the next frame starts a fresh run there)
		safeUntil = os.clock() + SAFE_AFTER
		local view = views[stage]
		if view then
			buildOrbs(view)
		end
	end)
	LOCAL.CharacterAdded:Connect(onCharacter)
	if LOCAL.Character then
		task.spawn(onCharacter, LOCAL.Character)
	end
	RunService.RenderStepped:Connect(step)
end

-- Back to the start of their furthest stage
function CourseController.restart()
	Net.event("Restart"):FireServer()
end

return CourseController
