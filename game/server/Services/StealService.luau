--!strict
-- The bat, and what it knocks loose. Everything a player carries outside their garden (the eggs in their hotbar,
-- the creatures not in the garden or the barn, an egg from the Wild or the Heist) can be stolen: two bat hits
-- on the same player knock what's in their hands out (or, with empty hands, something they carry). It lies on the
-- ground and anyone can grab it, the owner too: it goes into the grabber's hotbar, and they have to take it home to
-- be safe. Nobody takes it in a minute, it goes back to its owner. Nothing happens inside any garden.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Ball = require(Shared.Ball)
local StealConfig = require(Shared.Config.Steal)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Net = require(Shared.Net)
local Layout = require(Shared.Logic.Layout)

local DataService = require(script.Parent.DataService)
local HeistService = require(script.Parent.HeistService)
local IslandService = require(script.Parent.IslandService)
local WildService = require(script.Parent.WildService)

local StealService = {}

type Data = DataService.Data
type Creature = DataService.Creature

-- Something on the ground: an egg (tier, golden) or a creature, whose owner lost it
type Drop = { owner: Player, tier: number?, size: string?, golden: boolean?, creature: Creature?, model: Model, expires: number }
local drops: { [Model]: Drop } = {}

local rng = Random.new()
local lastSwing: { [Player]: number } = {}
local combo: { [Player]: { target: Player, hits: number, expires: number } } = {}

local function rootOf(player: Player): BasePart?
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function inGarden(position: Vector3): boolean
	return Layout.gardenAt(position) ~= nil
end

---------------------------------------------------------------------------------------------------------------
-- What is carried

-- What the player has in their hands, or else something they carry (picked at random)
type Loot = { creature: string?, key: string?, golden: boolean? }
local function lootOf(player: Player, data: Data): Loot?
	local character = player.Character
	if character then
		for _, tool in character:GetChildren() do
			if tool:IsA("Tool") then
				local id = tool:GetAttribute("CreatureId")
				if type(id) == "string" and data.creatures[id] and not data.stored[id] and not table.find(data.placed, id) then
					return { creature = id }
				end
				local kind = tool:GetAttribute("EggKind")
				if type(kind) == "string" then
					local golden = string.sub(kind, 1, 1) == "g"
					local key = if golden then string.sub(kind, 2) else kind
					local bag = if golden then data.golden else data.eggs
					if Hatch.parse(key) and (bag[key] or 0) > 0 then
						return { key = key, golden = golden }
					end
				end
			end
		end
	end
	-- (empty hands: any one thing they carry)
	local all: { Loot } = {}
	for id in data.creatures do
		if not data.stored[id] and not table.find(data.placed, id) then
			table.insert(all, { creature = id })
		end
	end
	for _, golden in { false, true } do
		for key, count in (if golden then data.golden else data.eggs) do
			if count > 0 and Hatch.parse(key) then
				table.insert(all, { key = key, golden = golden })
			end
		end
	end
	return if #all > 0 then all[rng:NextInteger(1, #all)] else nil
end

---------------------------------------------------------------------------------------------------------------
-- On the ground

local function title(drop: Drop): string
	if drop.creature then
		return drop.creature.s
	end
	return if drop.tier then Hatch.name(drop.tier, drop.size, drop.golden) else "Egg"
end

-- Hands the drop to a player (a thief, or its owner back), into their hotbar. False when there's no room.
local function give(drop: Drop, taker: Player): boolean
	local data = DataService.get(taker)
	if not data then
		return false
	end
	if drop.creature then
		local count = 0
		for _ in data.creatures do
			count += 1
		end
		if count >= IslandService.storage(data) then
			IslandService.notify(taker, "Your barn is full: sell some creatures or grow it", "error")
			return false
		end
		local id = tostring(data.nextId)
		data.nextId += 1
		data.creatures[id] = { s = drop.creature.s, m = drop.creature.m, g = drop.creature.g, w = drop.creature.w }
	elseif drop.tier then
		local bag = if drop.golden then data.golden else data.eggs
		local key = Hatch.key(drop.tier, drop.size)
		bag[key] = (bag[key] or 0) + 1
	end
	IslandService.push(taker)
	return true
end

local function remove(drop: Drop)
	drops[drop.model] = nil
	drop.model:Destroy()
end

-- Back to its owner (nobody took it in time, or they left)
local function sendHome(drop: Drop)
	if not drops[drop.model] then
		return
	end
	remove(drop)
	if drop.owner.Parent and give(drop, drop.owner) then
		IslandService.notify(drop.owner, ("Your %s came back"):format(title(drop)), "info")
	end
end

local function grab(taker: Player, drop: Drop)
	local root = rootOf(taker)
	if not drops[drop.model] or not root or (root.CFrame.Position - drop.model:GetPivot().Position).Magnitude > StealConfig.GRAB_RANGE + 4 then
		return
	end
	if inGarden(root.CFrame.Position) and taker ~= drop.owner then
		return
	end
	if not give(drop, taker) then
		return
	end
	remove(drop)
	if taker ~= drop.owner and drop.owner.Parent then
		IslandService.notify(drop.owner, ("😱 %s stole your %s!"):format(taker.DisplayName, title(drop)), "error")
	end
end

-- Puts what was knocked out on the ground where the victim stands
local function lay(drop: Drop, at: Vector3)
	local frame = CFrame.new(at.X, 1.4, at.Z)
	local model: Model
	local body: BasePart
	if drop.creature then
		model, body = Ball.build(drop.creature.s, frame, true)
	else
		local egg = if drop.tier then Hatch.egg(drop.tier) else nil
		model = Instance.new("Model")
		body = Instance.new("Part")
		body.Name = "Body"
		body.Shape = Enum.PartType.Ball
		body.Size = Vector3.one * 3 * Hatch.size(drop.size).scale
		body.CFrame = frame
		body.Anchored = true
		body.CanCollide = false
		body.Color = if drop.golden then Color3.fromRGB(255, 205, 70) elseif egg then egg.color else Color3.new(1, 1, 1)
		body.Material = if drop.golden then Enum.Material.Neon else Enum.Material.SmoothPlastic
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(1, 1.3, 1)
		mesh.Parent = body
		body.Parent = model
		model.PrimaryPart = body
	end
	model.Name = "Dropped"
	drop.model = model
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Grab"
	prompt.ObjectText = title(drop)
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = StealConfig.GRAB_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	prompt.Triggered:Connect(function(taker)
		grab(taker, drop)
	end)
	model.Parent = workspace
	drops[model] = drop
end

---------------------------------------------------------------------------------------------------------------
-- The bat

-- Knocks what the victim carries out of their hands
local function knock(victim: Player)
	local root = rootOf(victim)
	local data = DataService.get(victim)
	if not root or not data then
		return
	end
	if HeistService.isCarrier(victim) then
		HeistService.knock(victim)
		IslandService.notify(victim, "💥 Knocked out of your hands! Grab it back!", "error")
		return
	end
	if victim:GetAttribute("WildEgg") == true then
		WildService.knock(victim)
		return
	end
	local loot = lootOf(victim, data)
	if not loot then
		return
	end
	local drop: Drop
	if loot.creature then
		local creature = data.creatures[loot.creature]
		data.creatures[loot.creature] = nil
		drop = { owner = victim, creature = { s = creature.s, m = creature.m, g = creature.g, w = creature.w }, model = Instance.new("Model"), expires = os.clock() + StealConfig.DROP_TIME }
	else
		local key = loot.key :: string
		local bag = if loot.golden then data.golden else data.eggs
		bag[key] = if (bag[key] or 0) > 1 then bag[key] - 1 else nil
		local tier, size = Hatch.parse(key)
		drop = { owner = victim, tier = tier, size = size, golden = loot.golden, model = Instance.new("Model"), expires = os.clock() + StealConfig.DROP_TIME }
	end
	lay(drop, root.CFrame.Position)
	IslandService.notify(victim, ("💥 Your %s was knocked out of your hands! Grab it back!"):format(title(drop)), "error")
	IslandService.push(victim) -- (its tool goes away)
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
	tool.ToolTip = "Hit someone carrying eggs or creatures twice to knock them out of their hands (not in a garden)"
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
	-- Whoever leaves gets what's on the ground back first (before their data is saved: this starts before DataService)
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player], combo[player] = nil, nil
		for _, drop in drops do
			if drop.owner == player then
				sendHome(drop)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for _, drop in drops do
				if now >= drop.expires then
					sendHome(drop)
				end
			end
		end
	end)
end

return StealService
