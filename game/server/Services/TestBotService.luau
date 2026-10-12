--!strict
-- Test bots, in Studio only (Config/Steal TEST_BOTS; never in the published game): characters that play a little
-- by themselves so one person can try the stealing alone. Each one goes into the Wild, takes a real egg from a
-- nest (WildService) and runs it off toward the square. Hit one with the bat and it's knocked down, stunned, and
-- drops the egg: grab it and take it home, it's yours. When a player near them carries an egg home, they chase
-- them and swing their own bat (StealService). They have no garden or coins.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StealConfig = require(Shared.Config.Steal)
local Layout = require(Shared.Logic.Layout)

local HeistService = require(script.Parent.HeistService)
local StealService = require(script.Parent.StealService)
local WildService = require(script.Parent.WildService)

local TestBotService = {}

local WALK = 20 -- studs a second (a new player walks 24)
local CARRY_WALK = 16 -- with an egg
local HUNT_RANGE = 45 -- how near a player carrying an egg home must be for a bot to go after them
local SWING_EVERY = 1.2 -- seconds between a bot's swings

type Bot = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	bat: Tool?,
	state: string, -- "wild" (going for an egg), "carry" (running off with one), "down" (knocked down)
	egg: BasePart?, -- the nest's egg it's going for
	carried: BasePart?, -- the egg it carries
	goal: Vector3?,
	until_: number, -- (os.clock(): while down, till then; while resting, till then)
	lastSwing: number,
}

local bots: { Bot } = {}
local rng = Random.new()

local function spawnSpot(): Vector3
	local angle = rng:NextNumber() * 2 * math.pi
	return Layout.SQUARE_CENTER + Vector3.new(math.cos(angle) * 20, 4, math.sin(angle) * 20)
end

local function makeBot(n: number): Bot?
	local ok, model = pcall(function()
		local look = Instance.new("HumanoidDescription")
		return Players:CreateHumanoidModelFromDescription(look, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("TestBotService: couldn't make a bot: " .. tostring(model))
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		model:Destroy()
		return nil
	end
	model.Name = "TestBot" .. n
	humanoid.DisplayName = "🤖 Bot " .. n
	humanoid.WalkSpeed = WALK
	model:PivotTo(CFrame.new(spawnSpot()))
	model.Parent = workspace
	model:AddTag("TestBot")
	pcall(function()
		root:SetNetworkOwner(nil) -- (the server moves it: knockbacks included)
	end)
	local bat = StealService.makeBat()
	bat.Parent = model
	pcall(function()
		humanoid:EquipTool(bat)
	end)
	return { model = model, humanoid = humanoid, root = root, bat = bat, state = "wild", egg = nil, carried = nil, goal = nil, until_ = 0, lastSwing = 0 }
end

-- A full egg in the Wild, by luck
local function pickEgg(): BasePart?
	local full: { BasePart } = {}
	for _, egg in CollectionService:GetTagged("WildEgg") do
		if egg:IsA("BasePart") and egg.Transparency < 1 then
			table.insert(full, egg)
		end
	end
	return if #full > 0 then full[rng:NextInteger(1, #full)] else nil
end

-- The nearest player carrying an egg home, out of any garden and near enough to chase
local function prey(from: Vector3): BasePart?
	local best, bestDistance = nil, HUNT_RANGE
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local carrying = player:GetAttribute("WildEgg") == true or HeistService.isCarrier(player)
		if root and carrying and Layout.gardenAt(root.Position) == nil then
			local distance = (root.Position - from).Magnitude
			if distance < bestDistance then
				best, bestDistance = root, distance
			end
		end
	end
	return best
end

-- A bot was hit by a bat (StealService): pushed back; knocked down, it lies stunned and drops its egg
local function hit(model: Model, push: Vector3, hard: boolean)
	for _, bot in bots do
		if bot.model == model then
			bot.root.AssemblyLinearVelocity = push
			if hard then
				if bot.carried then
					WildService.botDrop(bot.carried, bot.root.Position)
					bot.carried = nil
				end
				bot.humanoid.PlatformStand = true
				bot.state = "down"
				bot.until_ = os.clock() + StealConfig.STUN
			end
			return
		end
	end
end

local function think(bot: Bot)
	local now = os.clock()
	local root, humanoid = bot.root, bot.humanoid
	if humanoid.Health <= 0 or root.Position.Y < -40 then
		-- (fell off, or died: back to the square)
		humanoid.Health = humanoid.MaxHealth
		bot.model:PivotTo(CFrame.new(spawnSpot()))
		bot.state = "wild"
		return
	end
	if bot.state == "down" then
		if now < bot.until_ then
			return
		end
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		bot.state, bot.egg = "wild", nil
		return
	end
	if now < bot.until_ then
		return -- (resting a moment)
	end
	-- Someone carrying an egg home nearby: after them, bat swinging
	if not bot.carried then
		local target = prey(root.Position)
		if target then
			humanoid.WalkSpeed = WALK
			humanoid:MoveTo(target.Position)
			if (target.Position - root.Position).Magnitude <= StealConfig.REACH - 1 and now - bot.lastSwing >= SWING_EVERY then
				bot.lastSwing = now
				root.CFrame = CFrame.lookAt(root.Position, Vector3.new(target.Position.X, root.Position.Y, target.Position.Z))
				StealService.botSwing(bot.model, bot.bat)
			end
			return
		end
	end
	if bot.state == "carry" then
		local goal = bot.goal or Layout.SQUARE_CENTER
		humanoid.WalkSpeed = CARRY_WALK
		humanoid:MoveTo(goal)
		if (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(goal.X, 0, goal.Z)).Magnitude < 8 then
			-- (got away with it)
			if bot.carried then
				WildService.botKeep(bot.carried)
				bot.carried = nil
			end
			bot.state, bot.until_ = "wild", now + 3
		end
		return
	end
	-- Off to the Wild for an egg
	local egg = bot.egg
	if not egg or egg.Transparency >= 1 or not egg.Parent then
		egg = pickEgg()
		bot.egg = egg
	end
	if not egg then
		bot.until_ = now + 2
		return
	end
	humanoid.WalkSpeed = WALK
	humanoid:MoveTo(egg.Position)
	if (egg.Position - root.Position).Magnitude < 7 then
		local carried = WildService.botTake(egg)
		bot.egg = nil
		if carried then
			bot.carried = carried
			bot.state = "carry"
			local angle = rng:NextNumber() * 2 * math.pi
			bot.goal = Layout.SQUARE_CENTER + Vector3.new(math.cos(angle) * 30, 0, math.sin(angle) * 30)
		end
	end
end

function TestBotService.init()
	if not RunService:IsStudio() or StealConfig.TEST_BOTS <= 0 then
		return
	end
	StealService.botHit = hit
	task.delay(3, function()
		for n = 1, StealConfig.TEST_BOTS do
			local bot = makeBot(n)
			if bot then
				table.insert(bots, bot)
			end
		end
		-- (a carried egg rides over its bot's head)
		RunService.Heartbeat:Connect(function()
			for _, bot in bots do
				local carried = bot.carried
				if carried then
					carried.CFrame = CFrame.new(bot.root.Position + Vector3.new(0, 4, 0))
				end
			end
		end)
		while true do
			for _, bot in bots do
				local ok, err = pcall(think, bot)
				if not ok then
					warn("TestBotService: " .. tostring(err))
				end
			end
			task.wait(0.25)
		end
	end)
end

return TestBotService
