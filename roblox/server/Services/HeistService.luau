--!strict
-- Egg Heist (Config/Heist, Logic/Heist): on weekends, every 15 minutes, a golden Heist Egg drops on the Egg
-- Garden's lawn. A player grabs it and has to carry it home to their Nest island (NestService); anyone close
-- enough can steal it on the way. Bringing it home wins gems and a rare egg; if nobody does before the round
-- ends, it cracks. In Studio the rounds run all week, for testing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HeistConfig = require(Shared.Config.Heist)
local Heist = require(Shared.Logic.Heist)
local Inventory = require(Shared.Logic.Inventory)
local Format = require(Shared.Logic.Format)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local NestService = require(script.Parent.NestService)
local WorldBuilder = require(script.Parent.WorldBuilder)

local HeistService = {}

local ALWAYS = RunService:IsStudio()

local egg: Part? = nil
local prompt: ProximityPrompt? = nil
local carrier: Player? = nil
local guardUntil = 0
local roundStart = -1
local warned = -1

local function dropSpot(): Vector3
	return WorldBuilder.gardenCenter() + Vector3.new(0, 3, 32)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function setCarrier(player: Player?)
	if carrier then
		carrier:SetAttribute("HeistCarrier", nil)
	end
	carrier = player
	guardUntil = os.clock() + HeistConfig.STEAL_GUARD
	if egg then
		egg:SetAttribute("Carrier", if player then player.UserId else 0)
	end
	if prompt then
		prompt.ActionText = if player then "Steal" else "Grab"
		prompt.ObjectText = if player then ("%s's Heist Egg"):format(player.DisplayName) else "Heist Egg"
	end
	if player then
		player:SetAttribute("HeistCarrier", true)
	end
end

local function endRound(winner: Player?)
	if egg then
		egg:Destroy()
	end
	egg, prompt = nil, nil
	if carrier then
		carrier:SetAttribute("HeistCarrier", nil)
	end
	carrier = nil
	if winner then
		local data = DataService.get(winner)
		if data then
			data.gems += HeistConfig.REWARD_GEMS
			-- The prize egg: the winner's best tier, lucky and rare (skipped if their storage is full)
			local best = 1
			for key, open in data.unlockedZones do
				local id = tonumber(key)
				if open and id and id > best then
					best = id
				end
			end
			if Inventory.count(data) < GameService.capacity(winner) then
				GameService.hatchPaid(winner, best, HeistConfig.REWARD_LUCK, HeistConfig.REWARD_MIN_VARIANT)
			end
			GameService.progress(winner, "Heist", 1)
			GameService.markDirty(winner)
			GameService.refresh(winner)
		end
		GameService.notifyAll(("🥚 %s brought the Heist Egg home! +%d 💎 and a rare egg"):format(winner.DisplayName, HeistConfig.REWARD_GEMS), "rare")
	else
		GameService.notifyAll("🥚 Nobody brought the Heist Egg home... it cracked!", "info")
	end
end

local function startRound(start: number)
	roundStart = start
	local part = Instance.new("Part")
	part.Name = "HeistEgg"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(4, 4, 4)
	part.Color = Color3.fromRGB(255, 200, 60)
	part.Material = Enum.Material.Foil
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.Position = dropSpot()
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = part
	local light = Instance.new("PointLight")
	light.Color = part.Color
	light.Range = 14
	light.Brightness = 1.5
	light.Parent = part
	part:SetAttribute("Ends", start + HeistConfig.ROUND)
	part:SetAttribute("Carrier", 0)
	part:AddTag("HeistEgg")
	local p = Instance.new("ProximityPrompt")
	p.ActionText = "Grab"
	p.ObjectText = "Heist Egg"
	p.MaxActivationDistance = HeistConfig.STEAL_RANGE
	p.HoldDuration = 0.4
	p.RequiresLineOfSight = false
	p.Parent = part
	p.Triggered:Connect(function(player)
		if player == carrier or not egg then
			return
		end
		local root = rootOf(player)
		if not root or (root.Position - (egg :: Part).Position).Magnitude > HeistConfig.STEAL_RANGE + 4 then
			return
		end
		if carrier and os.clock() < guardUntil then
			GameService.notify(player, "Too soon! Try again in a moment", "error")
			return
		end
		local victim = carrier
		setCarrier(player)
		if victim then
			GameService.notify(victim, ("%s stole your Heist Egg!"):format(player.DisplayName), "error")
			GameService.notify(player, "You stole the Heist Egg! Run to your Nest! 🏃", "success")
		else
			GameService.notify(player, "You've got the Heist Egg! Bring it to your Nest island!", "success")
		end
	end)
	part.Parent = workspace
	egg, prompt = part, p
	GameService.notifyAll("🥚 EGG HEIST! A Heist Egg dropped in the Egg Garden: bring it to your Nest!", "rare")
end

-- The schedule, once a second: the warning, the start and the end
local function schedule()
	local now = os.time()
	local on, start = Heist.round(now, ALWAYS)
	-- A minute's warning
	local nextStart = Heist.nextRound(now, ALWAYS)
	if not on and nextStart - now <= HeistConfig.WARNING and warned ~= nextStart then
		warned = nextStart
		GameService.notifyAll(("🥚 Egg Heist in %s! Get ready in the Egg Garden"):format(Format.time(nextStart - now)), "info")
	end
	if on and not egg and roundStart ~= start then
		startRound(start)
	elseif not on and egg then
		endRound(nil)
	end
end

-- Puts the egg down on the ground where it is (its carrier left, fell or was knocked out)
local function drop()
	local part = egg
	setCarrier(nil)
	if part then
		part.Position = Vector3.new(part.Position.X, 3, part.Position.Z)
	end
end

-- Every frame: the egg rides above its carrier's head, and wins when it gets home
local function follow()
	local part = egg
	if not part then
		return
	end
	local holder = carrier
	if holder then
		local root = rootOf(holder)
		local humanoid = holder.Character and holder.Character:FindFirstChildOfClass("Humanoid")
		if not holder.Parent or not root or not humanoid or humanoid.Health <= 0 then
			drop()
			return
		end
		part.Position = root.Position + Vector3.new(0, 5.5, 0)
		-- Home? (the middle of the carrier's own island)
		local plot = NestService.plotOf(holder)
		if plot then
			local home = WorldBuilder.nestPlot(plot)
			if (Vector3.new(root.Position.X, 0, root.Position.Z) - home).Magnitude <= HeistConfig.HOME_RANGE then
				endRound(holder)
			end
		end
	end
end

function HeistService.init()
	Players.PlayerRemoving:Connect(function(player)
		if player == carrier then
			drop()
		end
	end)
	RunService.Heartbeat:Connect(follow)
	task.spawn(function()
		while true do
			schedule()
			task.wait(1)
		end
	end)
end

return HeistService
