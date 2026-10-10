--!strict
-- Egg Heist (Config/Heist, Logic/Heist): on weekends, every 15 minutes, a golden Heist Egg drops in the town
-- square. A player grabs it and has to carry it home to their garden; anyone close enough can steal it on the
-- way. Bringing it home wins eggs; if nobody does before the round ends, it cracks. In Studio the rounds run
-- every day, for testing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HeistConfig = require(Shared.Config.Heist)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Heist = require(Shared.Logic.Heist)
local Layout = require(Shared.Logic.Layout)

local DataService = require(script.Parent.DataService)
local IslandService = require(script.Parent.IslandService)

local HeistService = {}

local ALWAYS = RunService:IsStudio()

local egg: Part? = nil
local prompt: ProximityPrompt? = nil
local carrier: Player? = nil
local guardUntil = 0
local roundStart = -1
local warned = -1

local function everyone(text: string, kind: string)
	for _, player in Players:GetPlayers() do
		IslandService.notify(player, text, kind)
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Whether a player is carrying the Heist Egg
function HeistService.isCarrier(player: Player): boolean
	return carrier == player
end

local function setCarrier(player: Player?)
	carrier = player
	guardUntil = os.clock() + HeistConfig.STEAL_GUARD
	if egg then
		egg:SetAttribute("Carrier", if player then player.UserId else 0)
	end
	if prompt then
		prompt.ActionText = if player then "Steal" else "Grab"
		prompt.ObjectText = if player then ("%s's Heist Egg"):format(player.DisplayName) else "Heist Egg"
	end
end

local function endRound(winner: Player?)
	if egg then
		egg:Destroy()
	end
	egg, prompt, carrier = nil, nil, nil
	if not winner then
		everyone("🥚 Nobody brought the Heist Egg home... it cracked!", "info")
		return
	end
	local data = DataService.get(winner)
	if data then
		local tier = IslandService.bestTier(data)
		local key = tostring(tier)
		data.eggs[key] = (data.eggs[key] or 0) + HeistConfig.REWARD_EGGS
		IslandService.push(winner)
		local prize = Hatch.egg(tier)
		everyone(("🥚 %s brought the Heist Egg home and won %d× %s!"):format(winner.DisplayName, HeistConfig.REWARD_EGGS, if prize then prize.name else "eggs"), "rare")
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
	part.Position = Layout.CENTER + Vector3.new(0, 3, -14)
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
		local current = egg
		if player == carrier or not current or player:GetAttribute("WildEgg") then
			return
		end
		local root = rootOf(player)
		if not root or (root.Position - current.Position).Magnitude > HeistConfig.STEAL_RANGE + 4 then
			return
		end
		if carrier and os.clock() < guardUntil then
			IslandService.notify(player, "Too soon! Try again in a moment", "error")
			return
		end
		local victim = carrier
		setCarrier(player)
		if victim then
			IslandService.notify(victim, ("%s stole your Heist Egg!"):format(player.DisplayName), "error")
			IslandService.notify(player, "You stole the Heist Egg! Run home! 🏃", "success")
		else
			IslandService.notify(player, "You've got the Heist Egg! Carry it home to your garden!", "success")
		end
	end)
	part.Parent = workspace
	egg, prompt = part, p
	everyone("🥚 EGG HEIST! A Heist Egg dropped by the fountain: carry it home to your garden!", "rare")
end

-- The schedule, once a second: the warning, the start and the end
local function schedule()
	local now = os.time()
	local on, start = Heist.round(now, ALWAYS)
	local nextStart = Heist.nextRound(now, ALWAYS)
	if not on and nextStart - now <= HeistConfig.WARNING and warned ~= nextStart then
		warned = nextStart
		everyone(("🥚 Egg Heist in %s! Get ready by the fountain"):format(Format.time(nextStart - now)), "info")
	end
	if on and not egg and roundStart ~= start then
		startRound(start)
	elseif not on and egg then
		endRound(nil)
	end
end

-- Puts the egg down where it is (its carrier left, fell or was knocked out)
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
	local holder = carrier
	if not part or not holder then
		return
	end
	local root = rootOf(holder)
	local humanoid = holder.Character and holder.Character:FindFirstChildOfClass("Humanoid")
	if not holder.Parent or not root or not humanoid or humanoid.Health <= 0 then
		drop()
		return
	end
	part.Position = root.Position + Vector3.new(0, 5.5, 0)
	local home = IslandService.islandOf(holder)
	if home then
		local center = Layout.garden(home).Position
		if (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(center.X, 0, center.Z)).Magnitude <= HeistConfig.HOME_RANGE then
			endRound(holder)
		end
	end
end

-- A bat knocked the Heist Egg out of its carrier's hands (GearService)
function HeistService.knock(player: Player)
	if player == carrier then
		drop()
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
