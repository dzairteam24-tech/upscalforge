--!strict
-- The course on the server: builds it, puts each runner at the start of their furthest stage, sets how fast they
-- walk, and checks what their phone says happened (an orb picked up, a wall reached, a stage run through)
-- against where their character really is, before the rules (Logic/Progress) pay for it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CourseConfig = require(Shared.Config.Course)
local Economy = require(Shared.Logic.Economy)
local Format = require(Shared.Logic.Format)
local Layout = require(Shared.Logic.Layout)
local Net = require(Shared.Net)
local Progress = require(Shared.Logic.Progress)
local Speed = require(Shared.Logic.Speed)
local SpeedConfig = require(Shared.Config.Speed)
local Stage = require(Shared.Logic.Stage)

local CourseBuilder = require(script.Parent.Parent.CourseBuilder)
local DataService = require(script.Parent.DataService)

local CourseService = {}

local REACH_SLACK = 14 -- studs on top of the magnet's reach (the phone is a little ahead of the server)
local WALL_NEAR = 26 -- how close to its wall a runner must be to smash it
local GROUP = "Runners"

export type Run = { stage: number, got: { [number]: boolean }, started: number, finished: boolean }
local runs: { [Player]: Run } = {}
local lastCrash: { [Player]: number } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end
CourseService.rootOf = rootOf

-- Where they are: the stage and how far along it (nil if no character)
local function whereIs(player: Player): (number?, number?, Vector3?)
	local root = rootOf(player)
	if not root then
		return nil, nil, nil
	end
	local position = root.CFrame.Position
	local k, d = Layout.fromZ(position.Z)
	return k, d, position
end

local function notify(player: Player, text: string, kind: string)
	Net.event("Notify"):FireClient(player, text, kind)
end

-- A fresh run of a stage: its orbs are all back
function CourseService.startRun(player: Player, stage: number): Run
	local run = { stage = stage, got = {}, started = os.clock(), finished = false }
	runs[player] = run
	return run
end

function CourseService.run(player: Player): Run?
	return runs[player]
end

-- Moves them to the start of a stage (their furthest if not said) and starts a run of it
function CourseService.teleport(player: Player, stage: number?)
	local data = DataService.get(player)
	if not data then
		return
	end
	local k = math.clamp(stage or Progress.frontier(data), 1, Progress.frontier(data))
	local character = player.Character
	if character then
		character:PivotTo(CFrame.lookAt(Layout.spawn(k), Layout.spawn(k) + Vector3.new(0, 0, -1)))
	end
	CourseService.startRun(player, k)
	Net.event("Teleported"):FireClient(player, k)
end

-- How fast they walk: from their speed stat
function CourseService.applySpeed(player: Player)
	local data = DataService.get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if data and humanoid then
		humanoid.WalkSpeed = Speed.walk(Progress.stat(data))
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = SpeedConfig.JUMP_HEIGHT
	end
end

-- An orb: the run's stage, not picked up already in this run, and near enough to where they really are
function CourseService.collect(player: Player, stage: any, index: any): boolean
	local data = DataService.get(player)
	if not data or type(stage) ~= "number" or type(index) ~= "number" then
		return false
	end
	if stage ~= math.floor(stage) or stage < 1 or stage > Progress.frontier(data) then
		return false
	end
	local orb = Stage.generate(stage).orbs[index]
	if not orb then
		return false
	end
	local _, _, position = whereIs(player)
	if not position then
		return false
	end
	local at = Layout.toWorld(stage, orb.x, orb.d) + Vector3.new(0, orb.y, 0)
	if (position - at).Magnitude > Progress.magnet(data) + REACH_SLACK then
		return false
	end
	local run = runs[player]
	if not run or run.stage ~= stage then
		run = CourseService.startRun(player, stage) -- (they ran on into the next stage)
	end
	if run.got[index] then
		return false
	end
	run.got[index] = true
	Progress.pickup(data, os.time(), stage)
	DataService.push(player)
	return true
end

-- The wall of their furthest stage: fast enough, and right there
function CourseService.smash(player: Player, stage: any): boolean
	local data = DataService.get(player)
	if not data or type(stage) ~= "number" or stage ~= data.stage or stage > Economy.STAGES then
		return false
	end
	local k, d = whereIs(player)
	local length = Economy.stageLength(stage)
	if k ~= stage or not d or d < length - WALL_NEAR or d > length + CourseConfig.WALL_THICK + 8 then
		return false
	end
	if not Progress.canSmash(data, stage) then
		notify(player, ("This wall needs %s speed. You have %s."):format(Format.short(Economy.needs(stage)), Format.short(Progress.stat(data))), "bad")
		return false
	end
	local coins = Progress.smash(data, stage, os.time()) :: number
	Net.event("Smashed"):FireClient(player, stage, coins)
	if data.stage > Economy.STAGES then
		notify(player, "You beat the whole course! Rebirth to run it again, faster.", "gold")
	end
	DataService.push(player)
	return true
end

-- Ran right through a stage they had smashed before: a bonus, once a run, and not quicker than anyone could
function CourseService.finish(player: Player, stage: any): boolean
	local data = DataService.get(player)
	local run = runs[player]
	if not data or not run or type(stage) ~= "number" or run.stage ~= stage or run.finished or stage >= data.stage then
		return false
	end
	local k, d = whereIs(player)
	local length = Economy.stageLength(stage)
	local atEnd = (k == stage and d ~= nil and d >= length - 10) or (k == stage + 1 and d ~= nil and d < 40)
	if not atEnd then
		return false
	end
	if os.clock() - run.started < length / SpeedConfig.WALK_MAX * 0.9 then
		return false
	end
	run.finished = true
	local coins = Progress.finish(data, stage, os.time())
	notify(player, ("Stage %d run: +%s coins"):format(stage, Format.short(coins)), "gold")
	DataService.push(player)
	return true
end

function CourseService.init()
	CourseBuilder.build(workspace)
	-- runners pass through each other
	pcall(function()
		PhysicsService:RegisterCollisionGroup(GROUP)
		PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
	end)

	Net.event("RunStart").OnServerEvent:Connect(function(player, stage)
		local data = DataService.get(player)
		if data and type(stage) == "number" and stage == math.floor(stage) and stage >= 1 and stage <= Progress.frontier(data) then
			CourseService.startRun(player, stage)
		end
	end)
	Net.event("Collect").OnServerEvent:Connect(CourseService.collect)
	Net.event("Smash").OnServerEvent:Connect(CourseService.smash)
	Net.event("Finish").OnServerEvent:Connect(CourseService.finish)
	Net.event("Crash").OnServerEvent:Connect(function(player)
		local data = DataService.get(player)
		if data and os.clock() - (lastCrash[player] or 0) > 0.5 then
			lastCrash[player] = os.clock()
			data.stats.crashes += 1
		end
	end)
	Net.event("Restart").OnServerEvent:Connect(function(player)
		CourseService.teleport(player)
	end)

	DataService.onPushed(function(player)
		CourseService.applySpeed(player)
	end)
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			for _, p in character:GetDescendants() do
				if p:IsA("BasePart") then
					p.CollisionGroup = GROUP
				end
			end
			character.DescendantAdded:Connect(function(p)
				if p:IsA("BasePart") then
					p.CollisionGroup = GROUP
				end
			end)
			task.defer(function()
				CourseService.applySpeed(player)
				if DataService.get(player) then
					CourseService.teleport(player)
				end
			end)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	-- once their data is in: to their furthest stage
	DataService.onLoaded(function(player)
		if player.Character then
			CourseService.applySpeed(player)
			CourseService.teleport(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		runs[player] = nil
		lastCrash[player] = nil
	end)
end

return CourseService
