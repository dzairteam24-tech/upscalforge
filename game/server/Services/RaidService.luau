--!strict
-- Raid Time (Config/Raid, Logic/Raid): every garden's laser gate opens at the same moment, on the clock, for a
-- minute every ten. While they're open, a player can walk into someone else's garden and carry off the egg in
-- one of their incubators: never the safe one, never from a new player, and never a hatched creature. The thief
-- walks slowly with it; the owner gets it back by catching them; if the thief isn't home before the gates shut
-- (or leaves, or falls), the egg goes back. Brought home, the egg keeps its incubation time in the thief's
-- garden.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RaidConfig = require(Shared.Config.Raid)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Layout = require(Shared.Logic.Layout)
local Raid = require(Shared.Logic.Raid)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local IslandService = require(script.Parent.IslandService)

local RaidService = {}

type Carry = { owner: Player, slot: number, tier: number, start: number, part: Part }
local carrying: { [Player]: Carry } = {}
local open = false
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

local function setSpeed(player: Player, speed: number?)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = speed or 16
	end
end

local function setGates(isOpen: boolean)
	local world = workspace:FindFirstChild("World")
	if not world then
		return
	end
	for _, garden in world:GetChildren() do
		local gate = garden:FindFirstChild("Gate")
		if gate and gate:IsA("BasePart") then
			gate:SetAttribute("Open", isOpen)
			gate.CanCollide = not isOpen
			gate.Transparency = if isOpen then 0.9 else 0.45
		end
	end
end

-- Ends a carry: the egg goes to the thief's garden (`stolen`) or stays with its owner
local function finish(thief: Player, stolen: boolean)
	local carry = carrying[thief]
	if not carry then
		return
	end
	carrying[thief] = nil
	carry.part:Destroy()
	setSpeed(thief, nil)
	local marks = IslandService.carried[carry.owner]
	if marks then
		marks[carry.slot] = nil
	end
	local ownerData = DataService.get(carry.owner)
	local thiefData = DataService.get(thief)
	if stolen and ownerData and thiefData then
		local key = tostring(carry.slot)
		local egg = ownerData.incubating[key]
		if egg and egg.start == carry.start and egg.tier == carry.tier then
			ownerData.incubating[key] = nil
			-- Into a free incubator of the thief's, keeping its time; or into their bag
			local placed = false
			for slot = 1, thiefData.incubators do
				if not thiefData.incubating[tostring(slot)] then
					thiefData.incubating[tostring(slot)] = { tier = egg.tier, start = egg.start }
					placed = true
					break
				end
			end
			if not placed then
				local tierKey = tostring(egg.tier)
				thiefData.eggs[tierKey] = (thiefData.eggs[tierKey] or 0) + 1
			end
			local name = (Hatch.egg(egg.tier) or { name = "egg" }).name
			IslandService.notify(thief, ("You stole a %s! 🥚"):format(name), "success")
			IslandService.notify(carry.owner, ("%s stole your %s!"):format(thief.DisplayName, name), "error")
			IslandService.render(thief)
			IslandService.push(thief)
			IslandService.push(carry.owner)
		end
	end
	IslandService.render(carry.owner)
end

local function steal(thief: Player, index: any, slot: any)
	if not open or type(index) ~= "number" or type(slot) ~= "number" or carrying[thief] then
		return
	end
	local owner = IslandService.ownerOf(index)
	local home = IslandService.islandOf(thief)
	local ownerData = owner and DataService.get(owner)
	if not owner or not ownerData or owner == thief or not home then
		return
	end
	if slot == RaidConfig.SAFE_SLOT then
		IslandService.notify(thief, "That's the safe incubator: it can't be robbed", "error")
		return
	end
	if os.time() - ownerData.firstPlayed < RaidConfig.NEW_PLAYER_SAFE then
		IslandService.notify(thief, ("%s is new here: their garden is safe for now"):format(owner.DisplayName), "error")
		return
	end
	local egg = ownerData.incubating[tostring(slot)]
	local marks = IslandService.carried[owner] or {}
	if not egg or marks[slot] then
		return
	end
	local root = rootOf(thief)
	if not root or (root.Position - Layout.incubator(index, slot)).Magnitude > RaidConfig.STEAL_RANGE + 3 then
		return
	end
	-- Pick it up: it rides over the thief's head, and they slow down
	local part = Instance.new("Part")
	part.Name = "StolenEgg"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(3, 3, 3)
	part.Color = (Hatch.egg(egg.tier) or { color = Color3.new(1, 1, 1) }).color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = part
	part.Position = root.Position + Vector3.new(0, 5, 0)
	part.Parent = workspace
	marks[slot] = true
	IslandService.carried[owner] = marks
	carrying[thief] = { owner = owner, slot = slot, tier = egg.tier, start = egg.start, part = part }
	setSpeed(thief, RaidConfig.THIEF_SPEED)
	IslandService.render(owner)
	IslandService.notify(thief, "Got it! Run home before the gates shut! 🏃", "success")
	IslandService.notify(owner, ("🚨 %s is stealing your egg! Catch them!"):format(thief.DisplayName), "error")
end

-- Food from someone's trough, one at a time and once a raid from each garden: it goes straight into the
-- thief's own trough
local foodTaken: { [Player]: { [number]: number } } = {}
local function stealFood(thief: Player, index: any)
	if not open or type(index) ~= "number" then
		return
	end
	local owner = IslandService.ownerOf(index)
	local ownerData = owner and DataService.get(owner)
	local thiefData = DataService.get(thief)
	if not owner or not ownerData or not thiefData or owner == thief then
		return
	end
	local _, raid = Raid.at(os.time())
	local taken = foodTaken[thief] or {}
	foodTaken[thief] = taken
	if taken[index] == raid then
		IslandService.notify(thief, "You already took food from this trough this raid", "error")
		return
	end
	if os.time() - ownerData.firstPlayed < RaidConfig.NEW_PLAYER_SAFE then
		IslandService.notify(thief, ("%s is new here: their garden is safe for now"):format(owner.DisplayName), "error")
		return
	end
	local root = rootOf(thief)
	if not root or (root.Position - Layout.garden(index):PointToWorldSpace(Layout.TROUGH)).Magnitude > RaidConfig.STEAL_RANGE + 3 then
		return
	end
	local food = IslandService.bestFood(ownerData)
	if not food then
		IslandService.notify(thief, "The trough is empty", "error")
		return
	end
	taken[index] = raid
	ownerData.food[food.id] -= 1
	thiefData.food[food.id] = (thiefData.food[food.id] or 0) + 1
	IslandService.notify(thief, ("You took %s %s from %s's trough!"):format(food.icon, food.name, owner.DisplayName), "success")
	IslandService.notify(owner, ("%s took %s %s from your trough!"):format(thief.DisplayName, food.icon, food.name), "error")
	IslandService.render(owner)
	IslandService.render(thief)
	IslandService.push(owner)
	IslandService.push(thief)
end

-- Every frame: the eggs ride with their thieves, who are caught, get home, or lose it
local function follow()
	for thief, carry in carrying do
		local root = rootOf(thief)
		local humanoid = thief.Character and thief.Character:FindFirstChildOfClass("Humanoid")
		if not thief.Parent or not root or not humanoid or humanoid.Health <= 0 or not carry.owner.Parent then
			finish(thief, false)
			continue
		end
		carry.part.Position = root.Position + Vector3.new(0, 5, 0)
		-- Caught by the owner
		local ownerRoot = rootOf(carry.owner)
		if ownerRoot and (ownerRoot.Position - root.Position).Magnitude <= RaidConfig.CATCH_RANGE then
			IslandService.notify(carry.owner, "You caught the thief and got your egg back! 💪", "success")
			IslandService.notify(thief, ("%s caught you! The egg went back"):format(carry.owner.DisplayName), "error")
			finish(thief, false)
			continue
		end
		-- Home
		if Layout.gardenAt(root.Position) == IslandService.islandOf(thief) then
			finish(thief, true)
		end
	end
end

-- The schedule, once a second: the warning, the gates opening and shutting
local function schedule()
	local now = os.time()
	local isOpen, changes = Raid.at(now)
	if not isOpen and changes - now <= RaidConfig.WARNING and warned ~= changes then
		warned = changes
		everyone(("🚨 Raid Time in %s! Guard your garden"):format(Format.time(changes - now)), "info")
	end
	if isOpen ~= open then
		open = isOpen
		setGates(isOpen)
		if isOpen then
			everyone("🚨 RAID TIME! Every gate is open for a minute", "rare")
		else
			for thief in carrying do
				IslandService.notify(thief, "The gates shut before you got home: the egg went back", "error")
				finish(thief, false)
			end
			everyone("🔒 The gates are shut again", "info")
		end
	end
end

function RaidService.init()
	Net.event("StealEgg").OnServerEvent:Connect(steal)
	Net.event("StealFood").OnServerEvent:Connect(stealFood)
	Players.PlayerRemoving:Connect(function(player)
		finish(player, false)
		for thief, carry in carrying do
			if carry.owner == player then
				finish(thief, false)
			end
		end
		IslandService.carried[player] = nil
		foodTaken[player] = nil
	end)
	RunService.Heartbeat:Connect(follow)
	setGates(false)
	task.spawn(function()
		while true do
			schedule()
			task.wait(1)
		end
	end)
end

return RaidService
