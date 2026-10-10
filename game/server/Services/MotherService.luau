--!strict
-- The Mother Cube (Config/Mother, Logic/Mother): once an hour a giant hungry cube lands over the square, and
-- everyone in the server feeds it together, with food from their trough or a snack bought on the spot. Full
-- before it leaves, it lays an egg for each player who fed it: one of the best tier they've hatched, or with
-- a chance that grows with what they gave, a Legendary Egg. In Studio it comes every 5 minutes, for testing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FoodConfig = require(Shared.Config.Food)
local MotherConfig = require(Shared.Config.Mother)
local Earn = require(Shared.Logic.Earn)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Layout = require(Shared.Logic.Layout)
local Mother = require(Shared.Logic.Mother)

local DailyService = require(script.Parent.DailyService)
local DataService = require(script.Parent.DataService)
local IslandService = require(script.Parent.IslandService)

local MotherService = {}

local STUDIO = RunService:IsStudio()
local LEGENDARY = 11

local cube: Part? = nil
local visit = -1 -- when the current (or last) visit started
local warned = -1
local points = 0
local goal = 0
local fed: { [Player]: number } = {} -- points each player gave this visit
local lastFeed: { [Player]: number } = {}
local rng = Random.new()

local function everyone(text: string, kind: string)
	for _, player in Players:GetPlayers() do
		IslandService.notify(player, text, kind)
	end
end

local function feed(player: Player)
	local data = DataService.get(player)
	local current = cube
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not data or not current or points >= goal or not root then
		return
	end
	if os.clock() - (lastFeed[player] or 0) < 0.4 then
		return
	end
	lastFeed[player] = os.clock()
	if (root.Position - current.Position).Magnitude > MotherConfig.REACH + 4 then
		return
	end
	-- The smallest food they hold, or a snack
	local gave = 0
	local what = ""
	for _, food in FoodConfig.LIST do
		if (data.food[food.id] or 0) > 0 then
			data.food[food.id] -= 1
			gave = MotherConfig.FOOD_POINTS[food.id] or 1
			what = food.icon
			break
		end
	end
	if gave == 0 then
		local price = Mother.snackPrice(Earn.islandRate(data.creatures, data.placed))
		if data.coins < price then
			IslandService.notify(player, ("A snack costs 🪙 %s: or bring food from the Food Shop"):format(Format.abbrev(price)), "error")
			return
		end
		data.coins -= price
		gave = 1
		what = "🍪"
	end
	points += gave
	fed[player] = (fed[player] or 0) + gave
	DailyService.add(player, "mother")
	current:SetAttribute("Points", points)
	IslandService.notify(player, ("%s +%d! You gave %d · Legendary chance %d%%"):format(what, gave, fed[player], math.floor(Mother.legendaryChance(fed[player]) * 100)), "success")
	IslandService.render(player)
	IslandService.push(player)
	if points >= goal then
		-- Full: an egg for everyone who fed it
		for feeder, given in fed do
			local feederData = DataService.get(feeder)
			if feeder.Parent and feederData then
				local tier = if rng:NextNumber() < Mother.legendaryChance(given) then LEGENDARY else IslandService.bestTier(feederData)
				local key = tostring(tier)
				feederData.eggs[key] = (feederData.eggs[key] or 0) + 1
				local egg = Hatch.egg(tier)
				IslandService.notify(feeder, ("👑 The Mother Cube laid you a %s!"):format(if egg then egg.name else "egg"), if tier == LEGENDARY then "rare" else "success")
				if tier == LEGENDARY then
					everyone(("👑 %s got a LEGENDARY EGG from the Mother Cube!"):format(feeder.DisplayName), "rare")
				end
				IslandService.push(feeder)
			end
		end
		everyone("👑 The Mother Cube is full and happy! Thank you, everyone 💛", "rare")
		current:SetAttribute("Full", true)
		task.delay(4, function()
			if cube == current then
				current:Destroy()
				cube = nil
			end
		end)
	end
end

local function land(start: number)
	visit = start
	points = 0
	goal = Mother.goal(#Players:GetPlayers())
	fed = {}
	local part = Instance.new("Part")
	part.Name = "MotherCube"
	part.Size = Vector3.one * MotherConfig.SIZE
	part.Color = Color3.fromRGB(255, 196, 120)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.Position = Layout.CENTER + Vector3.new(0, MotherConfig.HEIGHT, 0)
	part:SetAttribute("Points", 0)
	part:SetAttribute("Goal", goal)
	part:SetAttribute("Ends", start + MotherConfig.LASTS)
	part:SetAttribute("Full", false)
	part:AddTag("MotherCube")
	local light = Instance.new("PointLight")
	light.Color = part.Color
	light.Range = 24
	light.Brightness = 1.5
	light.Parent = part
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Feed"
	prompt.ObjectText = "Mother Cube"
	prompt.MaxActivationDistance = MotherConfig.REACH
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(feed)
	part.Parent = workspace
	cube = part
	everyone(("👑 The MOTHER CUBE landed in the square! Feed it together (%d needed) for eggs!"):format(goal), "rare")
end

local function leave()
	local current = cube
	cube = nil
	if current and not current:GetAttribute("Full") then
		current:Destroy()
		everyone("😢 The Mother Cube left hungry... next time!", "info")
	elseif current then
		current:Destroy()
	end
end

local function tick()
	local now = os.time()
	local on, start = Mother.at(now, STUDIO)
	if on and start ~= visit then
		land(start)
	elseif not on and cube then
		leave()
	end
	local nextVisit = Mother.nextVisit(now, STUDIO)
	if not on and nextVisit - now <= MotherConfig.WARNING and warned ~= nextVisit then
		warned = nextVisit
		everyone(("👑 The Mother Cube lands in the square in %s!"):format(Format.time(nextVisit - now)), "info")
	end
end

function MotherService.init()
	Players.PlayerRemoving:Connect(function(player)
		fed[player] = nil
		lastFeed[player] = nil
	end)
	task.spawn(function()
		while true do
			tick()
			task.wait(1)
		end
	end)
end

return MotherService
