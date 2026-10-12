--!strict
-- The bat. Only an egg on its way home can be stolen: one carried from the Wild (or the Heist Egg). Two bat hits
-- on its carrier knock it out of their hands, onto the ground, and anyone can grab it (WildService, HeistService)
-- and has to run it home in turn. Once it's in its taker's garden it's theirs and safe for good: in their hotbar,
-- to set down and hatch, or in their barn. Every hit pushes the one hit back, whatever they carry; nothing
-- happens inside any garden.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StealConfig = require(Shared.Config.Steal)
local Net = require(Shared.Net)
local Layout = require(Shared.Logic.Layout)

local HeistService = require(script.Parent.HeistService)
local IslandService = require(script.Parent.IslandService)
local WildService = require(script.Parent.WildService)

local StealService = {}

local lastSwing: { [Player]: number } = {}
local combo: { [Player]: { target: Player, hits: number, expires: number } } = {}

local function rootOf(player: Player): BasePart?
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function inGarden(position: Vector3): boolean
	return Layout.gardenAt(position) ~= nil
end

---------------------------------------------------------------------------------------------------------------
-- The bat

-- Knocks the egg its carrier is taking home out of their hands (only that egg: what's home is safe)
local function knock(victim: Player)
	if HeistService.isCarrier(victim) then
		HeistService.knock(victim)
		IslandService.notify(victim, "💥 Knocked out of your hands! Grab it back!", "error")
	elseif victim:GetAttribute("WildEgg") == true then
		WildService.knock(victim)
	end
end

local function swing(player: Player, tool: Tool?)
	local now = os.clock()
	if now - (lastSwing[player] or 0) < StealConfig.COOLDOWN then
		return
	end
	lastSwing[player] = now
	-- (the swing everyone sees and hears: the bat swept forward and back)
	local swinger = rootOf(player)
	if swinger then
		IslandService.fx("Swing", swinger.CFrame.Position)
	end
	if tool then
		local rest = tool.Grip
		tool.Grip = rest * CFrame.Angles(math.rad(-80), 0, 0)
		task.delay(0.18, function()
			if tool.Parent then
				tool.Grip = rest
			end
		end)
	end
	local root = rootOf(player)
	if not root or inGarden(root.CFrame.Position) then
		return
	end
	-- The nearest other player in front of them
	local target: Player? = nil
	local best = StealConfig.REACH
	for _, other in Players:GetPlayers() do
		local otherRoot = if other ~= player then rootOf(other) else nil
		if otherRoot then
			local offset = otherRoot.CFrame.Position - root.CFrame.Position
			local distance = offset.Magnitude
			if distance < best and distance > 0.01 and root.CFrame.LookVector:Dot(offset.Unit) > 0.2 then
				target, best = other, distance
			end
		end
	end
	local targetRoot = if target then rootOf(target) else nil
	if not target or not targetRoot or inGarden(targetRoot.CFrame.Position) then
		return
	end
	local run = combo[player]
	if not run or run.target ~= target or now > run.expires then
		run = { target = target, hits = 0, expires = now }
		combo[player] = run
	end
	run.hits += 1
	run.expires = now + StealConfig.COMBO_WINDOW
	local hard = run.hits >= StealConfig.HITS
	-- (the one hit flies back, on their own screen: their character is theirs to move; the knock-out hit harder)
	local away = targetRoot.CFrame.Position - root.CFrame.Position
	away = Vector3.new(away.X, 0, away.Z)
	away = if away.Magnitude > 0.01 then away.Unit else root.CFrame.LookVector
	local push = away * (if hard then StealConfig.KNOCK_PUSH else StealConfig.HIT_PUSH) + Vector3.new(0, if hard then 30 else 18, 0)
	Net.event("Knocked"):FireClient(target, push, hard)
	if target.Character then
		Net.event("HitMark"):FireClient(player, target.Character, math.min(run.hits, StealConfig.HITS), StealConfig.HITS)
	end
	IslandService.fx(if hard then "Knock" else "Hit", targetRoot.CFrame.Position)
	if hard then
		combo[player] = nil
		knock(target)
	end
end

local function giveBat(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	local character = player.Character
	if backpack:FindFirstChild("Bat") or (character and character:FindFirstChild("Bat")) then
		return
	end
	local tool = Instance.new("Tool")
	tool.Name = "Bat"
	tool.CanBeDropped = false
	tool.ToolTip = "Hit someone carrying an egg home from the Wild twice to knock it out of their hands (not in a garden)"
	tool.GripForward, tool.GripPos, tool.GripRight, tool.GripUp = Vector3.new(-1, 0, 0), Vector3.new(0, 0, -0.2), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1)
	-- A baseball bat, from the hand up (+Z): a taped grip with a knob, a thin neck widening to a long barrel
	-- with a red band, a rounded end
	-- (the hand holds an unseen block along the bat; the round pieces are welded to it)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.42, 0.42, 1.9)
	handle.CFrame = CFrame.identity
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	local along = CFrame.Angles(0, math.rad(90), 0) -- (a cylinder's axis along the bat)
	local function piece(name: string, length: number, width: number, z: number, color: Color3, material: Enum.Material, ball: boolean?)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = if ball then Enum.PartType.Ball else Enum.PartType.Cylinder
		p.Size = if ball then Vector3.one * width else Vector3.new(length, width, width)
		p.CFrame = CFrame.new(0, 0, z) * along
		p.Color = color
		p.Material = material
		p.CanCollide = false
		p.CanQuery = false
		p.Massless = true
		p.Parent = tool
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
	end
	local wood, light = Color3.fromRGB(214, 160, 96), Color3.fromRGB(232, 186, 120)
	piece("Grip", 1.9, 0.42, 0, Color3.fromRGB(34, 32, 40), Enum.Material.Fabric) -- (taped)
	piece("Knob", 0.25, 0.7, -1.05, Color3.fromRGB(34, 32, 40), Enum.Material.Fabric)
	piece("Neck", 1.2, 0.5, 1.5, wood, Enum.Material.Wood)
	piece("Taper", 0.7, 0.68, 2.4, wood, Enum.Material.Wood)
	piece("Barrel", 2.4, 0.86, 3.9, light, Enum.Material.Wood)
	piece("Band", 0.22, 0.9, 3.0, Color3.fromRGB(214, 52, 52), Enum.Material.SmoothPlastic)
	piece("End", 0, 0.86, 5.1, light, Enum.Material.Wood, true)
	tool.Activated:Connect(function()
		swing(player, tool)
	end)
	tool.Parent = backpack
end

function StealService.init()
	local function setUp(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(0.3) -- (the backpack is made again with each spawn)
			giveBat(player)
		end)
		task.defer(giveBat, player)
	end
	for _, player in Players:GetPlayers() do
		setUp(player)
	end
	Players.PlayerAdded:Connect(setUp)
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player], combo[player] = nil, nil
	end)
end

return StealService
