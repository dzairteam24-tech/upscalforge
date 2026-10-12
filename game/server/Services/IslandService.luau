--!strict
-- The heart of the game. Each player in the server gets one of the islands (WorldService) while they play.
-- On it, incubators hatch eggs in real time, even while the player is away; an egg that finishes in a special
-- weather (Logic/Weather) hatches at least that mutation. Hatched creatures live on the island and earn coins
-- every second, and for up to OFFLINE_HOURS while their owner is away. Nobody else can come in: a garden is
-- never robbed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared.Config.Creatures)
local DailyConfig = require(Shared.Config.Daily)
local FoodConfig = require(Shared.Config.Food)
local IslandConfig = require(Shared.Config.Island)
local MutateConfig = require(Shared.Config.Mutate)
local Mutations = require(Shared.Config.Mutations)
local SnapConfig = require(Shared.Config.Snap)
local WildConfig = require(Shared.Config.Wild)
local Earn = require(Shared.Logic.Earn)
local Food = require(Shared.Logic.Food)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Index = require(Shared.Logic.Index)
local Layout = require(Shared.Logic.Layout)
local Mutate = require(Shared.Logic.Mutate)
local Night = require(Shared.Logic.Night)
local Snap = require(Shared.Logic.Snap)
local Weather = require(Shared.Logic.Weather)
local PetModel = require(Shared.PetModel)
local Nest = require(Shared.Nest)
local EggModel = require(Shared.EggModel)
local EggSizes = require(Shared.Config.EggSizes)
local Mystery = require(Shared.Config.Mystery)
local Net = require(Shared.Net)

local DailyService = require(script.Parent.DailyService)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)

type Data = DataService.Data

local IslandService = {}

local REACH = 14 -- how close to an incubator a player has to stand to use it

local owners: { [number]: Player } = {}
local fast: { [Player]: boolean } = {} -- (the Fast Hatch game pass: RobuxService)
local friendsIn: { [Player]: number } = {} -- (friends in this server)
local islandOf: { [Player]: number } = {}
local rng = Random.new()

-- Told when a player's speed (data.power) changed here (WildService sets it: their walk follows)
function IslandService.powerChanged(_player: Player) end
-- Set by CarryService: the creatures in the inventory (hotbar) made again
function IslandService.toolsChanged(_player: Player, _data: Data) end

function IslandService.notify(player: Player, text: string, kind: string?)
	Net.event("Notify"):FireClient(player, text, kind or "info")
end

-- An effect in the world, for everyone near it (client Effects: "Hatch", "SetEgg", "Steal", "Home")
function IslandService.fx(kind: string, at: Vector3, color: Color3?)
	Net.event("Fx"):FireAllClients(kind, at, color)
end

-- A big moment for one player, in big letters across their screen ("🏃 RUN!", "🏠 HOME SAFE!")
function IslandService.banner(player: Player, text: string, color: Color3?)
	Net.event("Banner"):FireClient(player, text, color)
end

-- The eggs the player holds, in their inventory (hotbar): a tool for each kind, an egg in the hand; using it sets
-- one down in their garden (setEgg)
local setEggFrom: (Player, string, boolean) -> ()
local function eggTools(player: Player, data: Data)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return -- (they come when it does: assign)
	end
	local have: { [string]: Tool } = {}
	local holders: { Instance } = { backpack }
	if player.Character then
		table.insert(holders, player.Character)
	end
	for _, holder in holders do
		for _, tool in holder:GetChildren() do
			local kind = tool:GetAttribute("EggKind")
			if tool:IsA("Tool") and type(kind) == "string" then
				have[kind] = tool
			end
		end
	end
	for _, golden in { true, false } do
		local held = if golden then data.golden else data.eggs
		for _, key in Hatch.sortedKeys(held) do -- (best first)
			local tier, size, species = Hatch.parse(key)
			local kind = (if golden then "g" else "") .. key
			local count = held[key] or 0
			local tool = have[kind]
			have[kind] = nil
			local egg = if tier then Hatch.egg(tier) else nil
			if count <= 0 or not egg or not tier then
				if tool then
					tool:Destroy()
				end
				continue
			end
			if not tool then
				local created = Instance.new("Tool")
				created:SetAttribute("EggKind", kind)
				created.CanBeDropped = false
				created.Grip = CFrame.new(0, -0.2, 0)
				local handle = Instance.new("Part")
				handle.Name = "Handle"
				handle.Shape = Enum.PartType.Ball
				handle.Size = Vector3.one * EggSizes.BASE * 0.8 * Hatch.size(size).scale
				handle.Color = if golden then Color3.fromRGB(255, 205, 70) else egg.color
				handle.Material = if golden then Enum.Material.Neon else Enum.Material.SmoothPlastic
				handle.CanCollide = false
				handle.Massless = true
				local mesh = Instance.new("SpecialMesh")
				mesh.MeshType = Enum.MeshType.Sphere
				mesh.Scale = Vector3.new(1, 1.3, 1)
				mesh.Parent = handle
				EggModel.dress(handle, egg.color, golden, species)
				handle.Parent = created
				created.Activated:Connect(function()
					setEggFrom(player, key, golden)
				end)
				created.Parent = backpack
				tool = created
			end
			local t = tool :: Tool
			t.Name = ("%s ×%d"):format(Hatch.name(tier, size, golden, species), count)
			if size ~= "Normal" then
				t.ToolTip = ("⚖️ %s: a %s creature"):format(size, Hatch.size(size).creature)
			end
			if size == "Normal" then
				t.ToolTip = "Click to set it down in your garden"
			end
		end
	end
	for _, leftover in have do
		leftover:Destroy()
	end
end

-- Sends the player their data (the client shows it; the server's copy is the truth)
function IslandService.push(player: Player)
	local data = DataService.get(player)
	if data then
		local ok, err = pcall(function()
			eggTools(player, data)
			IslandService.toolsChanged(player, data)
		end)
		if not ok then
			warn("[Island] Couldn't give the egg tools", player.Name, err)
		end
		Net.event("Data"):FireClient(player, data, islandOf[player])
		player:SetAttribute("Coins", data.coins)
		player:SetAttribute("FedUntil", data.fedUntil)
	end
end

-- Eggs hatch twice as fast for the owner of the Fast Hatch pass (RobuxService says who)
function IslandService.setFast(player: Player, on: boolean)
	if on then
		fast[player] = true
	else
		fast[player] = nil
	end
	player:SetAttribute("FastHatch", on) -- (the screen's egg timers: GrowingEggs)
	IslandService.render(player)
end

local function hatchTime(player: Player?, tier: number, slot: number): number
	local seconds = Hatch.secondsIn(tier, slot)
	return if player and fast[player] then math.floor(seconds / 2) else seconds
end

-- Every egg in the player's garden ready to hatch now (the Hatch All product: RobuxService)
function IslandService.hatchAll(player: Player): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	local now = os.time()
	for key, egg in data.incubating do
		egg.start = now - hatchTime(player, egg.tier, tonumber(key) or 1) - 1
	end
	IslandService.render(player)
	IslandService.push(player)
	return true
end

-- Friends in the same server boost each other's coins (Config/Island FRIEND_BOOST)
local function countFriends()
	local everyone = Players:GetPlayers()
	for _, player in everyone do
		local count = 0
		for _, other in everyone do
			if other ~= player then
				local ok, yes = pcall(function()
					return player:IsFriendsWith(other.UserId)
				end)
				if ok and yes then
					count += 1
				end
			end
		end
		friendsIn[player] = math.min(count, IslandConfig.FRIEND_MAX)
		player:SetAttribute("FriendBoost", math.floor(friendsIn[player] * IslandConfig.FRIEND_BOOST * 100 + 0.5))
	end
end

function IslandService.islandOf(player: Player): number?
	return islandOf[player]
end

-- Whether the player stands in their own garden (where an egg they bring from the Wild is theirs and safe, and
-- the barn and the incubators only work there)
function IslandService.inOwnGarden(player: Player): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and islandOf[player] ~= nil and Layout.gardenAt(root.CFrame.Position) == islandOf[player]
end

-- Puts an egg the player holds in their hand (its tool from the inventory), as one from the Wild arrives home
function IslandService.holdEgg(player: Player, key: string, golden: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not humanoid or not backpack then
		return
	end
	local kind = (if golden then "g" else "") .. key
	for _, tool in backpack:GetChildren() do
		if tool:IsA("Tool") and tool:GetAttribute("EggKind") == kind then
			humanoid:EquipTool(tool)
			return
		end
	end
end

-- Who has a garden, or nil when it's free
function IslandService.ownerOf(index: number): Player?
	return owners[index]
end

-- The furthest egg tier a player has had: their "level" for prizes
function IslandService.bestTier(data: Data): number
	local best = 1
	for _, creature in data.creatures do
		local species = Creatures.byId[creature.s]
		if species and species.tier <= 10 and species.tier > best and Hatch.open(species.tier) then
			best = species.tier
		end
	end
	return best
end

-- How many creatures the player's barn holds
function IslandService.storage(data: Data): number
	return IslandConfig.STORAGE[math.clamp(data.storage, 1, #IslandConfig.STORAGE)]
end

-- The best food the player holds (the longest-lasting), if any
function IslandService.bestFood(data: Data): FoodConfig.Food?
	for i = #FoodConfig.LIST, 1, -1 do
		local food = FoodConfig.LIST[i]
		if (data.food[food.id] or 0) > 0 then
			return food
		end
	end
	return nil
end

-- Adds a hatched creature (into the inventory: CarryService); nil when the player's storage is full
function IslandService.addCreature(player: Player, data: Data, species: string, mutation: string, size: string?): string?
	local count = 0
	for _ in data.creatures do
		count += 1
	end
	if count >= IslandService.storage(data) then
		IslandService.notify(player, "Your storage is full: sell some creatures or grow your barn", "error")
		return nil
	end
	local id = tostring(data.nextId)
	data.nextId += 1
	data.creatures[id] = { s = species, m = mutation, w = if size and size ~= "Normal" then size else nil }
	data.stats.hatched += 1
	if not data.index[species] then
		data.index[species] = true
		local reward = Index.creatureReward(species)
		data.coins += reward.coins
		data.power += reward.power
		IslandService.powerChanged(player)
		IslandService.notify(player, ("📖 New in your Index: %s! +🪙 %s +⚡ %s"):format(species, Format.abbrev(reward.coins), Format.abbrev(reward.power)), "success")
	end
	return id
end

---------------------------------------------------------------------------------------------------------------
-- Drawing an island

-- What each garden shows now (its pasture's level and its creatures), so a redraw only rebuilds what changed:
-- rebuilding every creature on each coin or egg action was the heaviest thing the server did
local drawnLevel: { [number]: number } = {}
local drawnCreatures: { [number]: string } = {}

local function creaturesKey(data: Data?): string
	if not data then
		return ""
	end
	local keys = {}
	for _, id in data.placed do
		local creature = data.creatures[id]
		if creature then
			table.insert(keys, ("%s:%s:%s:%s:%s"):format(id, creature.s, creature.m, creature.g or "", creature.w or ""))
		end
	end
	return table.concat(keys, ",")
end

local drawnEggs: { [number]: string } = {}

local function eggsOnGround(data: Data?): string
	if not data then
		return ""
	end
	local keys = {}
	for key, egg in data.incubating do
		table.insert(keys, ("%s:%d:%d"):format(key, egg.tier, egg.start))
	end
	table.sort(keys)
	return table.concat(keys, ",")
end

local function render(index: number, player: Player?, data: Data?)
	local island = WorldService.island(index)
	if not island then
		return
	end
	island:SetAttribute("Owner", if player then player.UserId else 0)
	-- The pasture as far as the owner has grown it
	local level = if data then data.pasture else 1
	island:SetAttribute("Pasture", level)
	-- (the incubators and the barn always at its back edge)
	local back = island:FindFirstChild("Back")
	if back then
		local shift = Layout.backShift(level).Z
		local was = back:GetAttribute("Shift")
		local delta = shift - (if type(was) == "number" then was else 0)
		if delta ~= 0 then
			local move = Layout.garden(index):VectorToWorldSpace(Vector3.new(0, 0, delta))
			for _, p in back:GetDescendants() do
				if p:IsA("BasePart") then
					p.CFrame += move
				end
			end
			back:SetAttribute("Shift", shift)
		end
	end
	local growing: { Instance } = if drawnLevel[index] == level then {} else island:GetDescendants()
	for _, d in growing do
		local grow = d:GetAttribute("Grow")
		if type(grow) == "number" and d:IsA("Model") then
			local shown = if d:GetAttribute("Only") then grow == level else grow <= level
			for _, p in d:GetDescendants() do
				if p:IsA("BasePart") then
					local look = p:GetAttribute("Look")
					p.Transparency = if shown and type(look) == "number" then look else 1
					p.CanCollide = shown and p:GetAttribute("Solid") == true
				end
			end
		end
	end
	-- The trough shows how much food the owner holds and how long the creatures are fed
	local trough = island:FindFirstChild("Trough")
	if trough then
		local count = 0
		if data then
			for _, n in data.food do
				count += n
			end
		end
		trough:SetAttribute("Owner", if player then player.UserId else 0)
		trough:SetAttribute("Food", count)
		trough:SetAttribute("FedUntil", if data then data.fedUntil else 0)
	end
	local sign = island:FindFirstChild("OwnerSign")
	local text = sign and sign:FindFirstChild("Text", true)
	if text and text:IsA("TextLabel") then
		text.Text = if player then ("🥚 %s's Nest"):format(player.DisplayName) else "Free garden"
	end
	-- The owner's avatar and name over the garden
	local banner = island:FindFirstChild("OwnerBanner")
	local card = banner and banner:FindFirstChild("Card")
	if card and card:IsA("BillboardGui") then
		card.Enabled = player ~= nil
		local face = card:FindFirstChild("Avatar")
		local owner = card:FindFirstChild("Owner")
		if player and face and face:IsA("ImageLabel") and owner and owner:IsA("TextLabel") then
			face.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(player.UserId)
			owner.Text = player.DisplayName
		end
	end
	-- The eggs set down on the grass: a pad for each (rebuilt only when they change)
	local eggsFolder = island:FindFirstChild("Eggs")
	local eggsKey = eggsOnGround(data)
	if eggsFolder and drawnEggs[index] ~= eggsKey then
		drawnEggs[index] = eggsKey
		eggsFolder:ClearAllChildren()
		if data then
			for key, egg in data.incubating do
				local slot = tonumber(key)
				if slot and not Hatch.isMachine(slot) then
					local pad = Instance.new("Part")
					pad.Name = "Incubator"
					pad.Anchored = true
					pad.CanCollide = false
					pad.CanTouch = false
					pad.Transparency = 1
					pad.Size = Vector3.new(Layout.NEST_SIZE - 1, 0.2, Layout.NEST_SIZE - 1)
					pad.CFrame = Layout.garden(index) * CFrame.new(egg.x or Layout.START_SPOT.X, 0.45, egg.z or Layout.START_SPOT.Z)
					pad:SetAttribute("Island", index)
					pad:SetAttribute("Slot", slot)
					local prompt = Instance.new("ProximityPrompt")
					prompt.ActionText = "Check"
					prompt.ObjectText = "Egg"
					prompt.MaxActivationDistance = 9
					prompt.RequiresLineOfSight = false
					prompt.Enabled = false -- GardenClient turns on the owner's
					prompt:SetAttribute("Island", index)
					prompt:SetAttribute("Slot", slot)
					prompt.Parent = pad
					Nest.build(pad, pad.CFrame, egg.tier, EggSizes.NEST) -- (in its egg's look)
					pad.Parent = eggsFolder
					pad:AddTag("Incubator")
				end
			end
		end
	end
	for _, pad in island:GetDescendants() do
		local slot = pad:GetAttribute("Slot")
		if type(slot) ~= "number" or not pad:IsA("BasePart") then
			continue
		end
		local egg = if data then data.incubating[tostring(slot)] else nil
		pad:SetAttribute("Owner", if player then player.UserId else 0)
		if Hatch.isMachine(slot) then
			-- An incubator at the back: bought one by one
			local k = slot - IslandConfig.MACHINE_SLOT
			pad:SetAttribute("Open", if data then k <= data.machines else false)
			pad:SetAttribute("Price", if data and k == data.machines + 1 then IslandConfig.MACHINE_PRICES[k] or 0 else 0)
		else
			pad:SetAttribute("Open", true)
			pad:SetAttribute("Price", 0)
		end
		pad:SetAttribute("Tier", if egg then egg.tier else 0)
		pad:SetAttribute("Golden", egg ~= nil and egg.m ~= nil)
		pad:SetAttribute("EggSize", if egg then Hatch.size(egg.w).scale else 1) -- (GardenClient draws it that big...)
		pad:SetAttribute("Species", if egg then egg.s or "" else "") -- (...looking like the creature in it)
		pad:SetAttribute("Start", if egg then egg.start else 0)
		pad:SetAttribute("Duration", if egg then hatchTime(player, egg.tier, slot) else 0)
	end
	-- The creatures living there
	drawnLevel[index] = level
	local folder = island:FindFirstChild("Creatures")
	local key = creaturesKey(data)
	if folder and drawnCreatures[index] ~= key then
		drawnCreatures[index] = key
		folder:ClearAllChildren()
		if data then
			for slot, id in data.placed do
				local creature = data.creatures[id]
				if not creature then
					continue
				end
				local at = Layout.pen(index, slot)
				local grade = if creature.g then SnapConfig.byId[creature.g] else nil
				local built = PetModel.build({ s = creature.s, v = creature.m, z = if grade then grade.size else Hatch.size(creature.w).creature })
				local facing = Layout.facing(at, at + Layout.garden(index).LookVector)
				PetModel.place(built, facing * CFrame.new(0, built.height / 2, 0))
				for _, p in built.parts do
					p.Anchored = true
					p.CanCollide = false
					p.CanQuery = false
				end
				built.model:SetAttribute("Earn", Earn.rate(creature))
				built.model:SetAttribute("Island", index)
				built.model:SetAttribute("Height", built.height)
				built.model:SetAttribute("Spot", at) -- (where it stands: its body's middle is Height / 2 over it)
				built.model:SetAttribute("Mutation", creature.m)
				built.model:SetAttribute("Species", creature.s)
				built.model:SetAttribute("Grade", creature.g or "")
				built.model:SetAttribute("EggSize", creature.w or "") -- (its name tag says Big, Huge...)
				built.model:AddTag("IslandCreature")
				built.model.Parent = folder
			end
		end
	end
end

function IslandService.render(player: Player)
	local index = islandOf[player]
	if index then
		render(index, player, DataService.get(player))
	end
end

---------------------------------------------------------------------------------------------------------------
-- Joining and leaving

local function assign(player: Player, data: Data)
	-- Coins the island earned while its owner was away
	if data.lastSeen > 0 then
		local away = os.time() - data.lastSeen
		local rate = Earn.islandRate(data.creatures, data.placed)
		local coins = Earn.offline(rate, away) + Food.offlineBonus(rate, data.lastSeen, data.fedUntil, os.time())
		if coins > 0 then
			data.coins += coins
			data.stats.earned += coins
			task.delay(3, IslandService.notify, player, ("Welcome back! Your creatures earned 🪙 %s while you were away"):format(Format.abbrev(coins)), "success")
		end
	end
	for index = 1, IslandConfig.ISLANDS do
		if not owners[index] then
			owners[index] = player
			islandOf[player] = index
			player:SetAttribute("Island", index)
			render(index, player, data)
			break
		end
	end
	-- A new player's first egg is already set down in their garden, and hatches fast
	if not data.starter then
		data.starter = true
		if data.nextId == 1 and not data.incubating["1"] then
			data.incubating["1"] = { tier = 1, start = os.time() - (Hatch.seconds(1) - IslandConfig.STARTER_HATCH), x = Layout.START_SPOT.X, z = Layout.START_SPOT.Z }
			IslandService.render(player)
			task.delay(3, IslandService.notify, player, "🥚 Your first egg is hatching in your garden!", "success")
		end
	end
	IslandService.push(player)
	-- Their eggs in the inventory, every time it's made again (on each spawn, the backpack starts empty)
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			task.wait(0.2)
			IslandService.push(player)
		end
	end)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		IslandService.push(player)
	end)
	-- Start on the island
	task.spawn(function()
		local character = player.Character or player.CharacterAdded:Wait()
		local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		if root then
			IslandService.sendHome(player)
		end
	end)
end

-- Puts a player just inside their garden's gate
function IslandService.sendHome(player: Player)
	local index = islandOf[player]
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and index then
		root.CFrame = Layout.home(index) * CFrame.new(0, 4, 0)
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

local function release(player: Player)
	local index = islandOf[player]
	if index then
		owners[index] = nil
		islandOf[player] = nil
		render(index, nil, nil)
	end
end

---------------------------------------------------------------------------------------------------------------
-- Actions

local function nearPad(player: Player, slot: number): boolean
	local index = islandOf[player]
	local island = index and WorldService.island(index)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not island or not root then
		return false
	end
	for _, pad in island:GetDescendants() do
		if pad:IsA("BasePart") and pad:GetAttribute("Slot") == slot then
			return (root.Position - pad.Position).Magnitude <= REACH
		end
	end
	return false
end

local busy: { [Player]: number } = {}
local function throttle(player: Player): boolean
	local now = os.clock()
	if now - (busy[player] or 0) < 0.3 then
		return false
	end
	busy[player] = now
	return true
end

-- Takes the best egg the player holds (a Golden one first): its tier, and the least mutation it hatches; nil
-- when they have none
local function takeEgg(data: Data): (number?, string?, string?, string?)
	-- (the best key in a bag: by tier, then by size)
	local function best(eggs: { [string]: number }): string?
		local found, foundTier, foundWeight = nil, 0, 0
		for key, count in eggs do
			local tier, size = Hatch.parse(key)
			local weight = Hatch.size(size).weight
			if tier and count > 0 and (tier > foundTier or (tier == foundTier and weight > foundWeight)) then
				found, foundTier, foundWeight = key, tier, weight
			end
		end
		return found
	end
	local golden = best(data.golden)
	if golden then
		data.golden[golden] -= 1
		local tier, size, species = Hatch.parse(golden)
		return tier, WildConfig.GOLDEN_MUTATION, size, species
	end
	local key = best(data.eggs)
	if not key then
		return nil, nil, nil, nil
	end
	data.eggs[key] -= 1
	local tier, size, species = Hatch.parse(key)
	return tier, nil, size, species
end

-- How many eggs the player has set down on the grass
local function eggsDown(data: Data): number
	local count = 0
	for key in data.incubating do
		local slot = tonumber(key)
		if slot and not Hatch.isMachine(slot) then
			count += 1
		end
	end
	return count
end

-- Sets an egg the player holds (the one in their hand: its tool) down on the grass just in front of them, like
-- in Steal an Egg
local function setEgg(player: Player, key: string, golden: boolean)
	local tier, size, species = Hatch.parse(key)
	local data = DataService.get(player)
	local index = islandOf[player]
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not data or not index or not root or not tier or not throttle(player) then
		return
	end
	local frame = Layout.garden(index)
	local inside = frame:PointToObjectSpace((root.CFrame * CFrame.new(0, 0, -2.5)).Position) -- (just in front of them)
	if not Layout.eggSpot(Vector3.new(inside.X, 0, inside.Z), data.pasture) then
		IslandService.notify(player, "Set your eggs down on your own garden's grass", "error")
		return
	end
	if eggsDown(data) >= data.incubators then
		IslandService.notify(player, ("Your garden hatches %d eggs at once: get +1 in 🎒 Bag → 🥚 Eggs"):format(data.incubators), "error")
		return
	end
	for _, egg in data.incubating do
		if egg.x and egg.z and (Vector3.new(egg.x, 0, egg.z) - Vector3.new(inside.X, 0, inside.Z)).Magnitude < Layout.NEST_SIZE then
			IslandService.notify(player, "Too close to another egg", "error")
			return
		end
	end
	local slot = 1
	while data.incubating[tostring(slot)] do
		slot += 1
	end
	local held = if golden then data.golden else data.eggs
	if (held[key] or 0) <= 0 then
		return
	end
	held[key] -= 1
	local least = if golden then WildConfig.GOLDEN_MUTATION else nil
	data.incubating[tostring(slot)] = { tier = tier, start = os.time(), m = least, w = if size ~= "Normal" then size else nil, s = species, x = inside.X, z = inside.Z }
	local egg = Hatch.egg(tier)
	IslandService.fx("SetEgg", frame:PointToWorldSpace(Vector3.new(inside.X, 0, inside.Z)), if least then Color3.fromRGB(255, 205, 70) elseif egg then egg.color else nil)
	IslandService.notify(player, ("%s set down: %s"):format(Hatch.name(tier, size, golden, species), Format.time(Hatch.seconds(tier))), "success")
	IslandService.render(player)
	IslandService.push(player)
end

setEggFrom = setEgg

-- Room for one more egg on the grass
local function buyEggRoom(player: Player)
	local data = DataService.get(player)
	if not data or not throttle(player) then
		return
	end
	local price = Earn.nextPrice(IslandConfig.INCUBATOR_PRICES, data.incubators, IslandConfig.INCUBATORS)
	if not price then
		IslandService.notify(player, "Your garden holds as many eggs as it can", "error")
		return
	end
	if data.coins < price then
		IslandService.notify(player, ("You need 🪙 %s"):format(Format.abbrev(price)), "error")
		return
	end
	data.coins -= price
	data.incubators += 1
	IslandService.notify(player, ("Room for %d eggs in your garden! 🥚"):format(data.incubators), "success")
	IslandService.push(player)
end

local function useIncubator(player: Player, slot: any)
	local data = DataService.get(player)
	if not data or type(slot) ~= "number" or slot ~= slot // 1 or slot < 1 or not throttle(player) then
		return
	end
	local key = tostring(slot)
	if not data.incubating[key] and not nearPad(player, slot) then -- (an egg hatches from anywhere: Growing Eggs)
		return
	end
	local machine = Hatch.isMachine(slot)
	if machine and slot - IslandConfig.MACHINE_SLOT > data.machines then
		-- Buy the next incubator
		local k = slot - IslandConfig.MACHINE_SLOT
		local price = IslandConfig.MACHINE_PRICES[k]
		if k ~= data.machines + 1 or not price then
			IslandService.notify(player, "Unlock the incubators in order", "error")
			return
		end
		if data.coins < price then
			IslandService.notify(player, ("You need 🪙 %s"):format(Format.abbrev(price)), "error")
			return
		end
		data.coins -= price
		data.machines += 1
		IslandService.notify(player, ("New incubator! Eggs hatch ×%d faster in it ⚡"):format(IslandConfig.MACHINE_SPEED), "success")
	elseif not machine and not data.incubating[key] then
		return -- (eggs go down on the grass with the Egg tool)
	else
		local egg = data.incubating[key]
		if egg then
			local done = math.ceil(Night.doneAt(egg.start, hatchTime(player, egg.tier, slot))) -- (nights hatch faster)
			local now = os.time()
			if now < done then
				IslandService.notify(player, ("Still incubating: %s left"):format(Format.time(done - now)))
				return
			end
			local weather = Weather.at(done)
			local function luck(): number
				return rng:NextNumber()
			end
			-- A Mystery Egg: something by luck (Config/Mystery): a rare creature, or coins, speed, eggs
			local shown = egg.s
			if shown == Mystery.ID then
				local reward = Hatch.mysteryReward(luck)
				local purple = Color3.fromRGB(210, 140, 255)
				shown = if reward.kind == "creature" then Hatch.ofRarity(egg.tier, reward.rarity or "Rare", luck) else nil
				if not shown then
					local text: string
					if reward.kind == "coins" then
						local coins = math.max(reward.min or 0, math.floor((reward.seconds or 0) * Earn.islandRate(data.creatures, data.placed)))
						data.coins += coins
						player:SetAttribute("Coins", data.coins)
						text = ("+🪙 %s"):format(Format.abbrev(coins))
					elseif reward.kind == "power" then
						data.power += reward.amount or 0
						IslandService.powerChanged(player)
						text = ("+⚡ %s speed"):format(Format.abbrev(reward.amount or 0))
					else
						local count = reward.count or 1
						local tierKey = tostring(egg.tier)
						data.eggs[tierKey] = (data.eggs[tierKey] or 0) + count
						text = ("+%d eggs"):format(count)
					end
					data.incubating[key] = nil
					DailyService.add(player, "hatch")
					IslandService.banner(player, "🎁 MYSTERY: " .. text, purple)
					local index = islandOf[player]
					if index and egg.x and egg.z then
						IslandService.fx("Hatch", Layout.garden(index):PointToWorldSpace(Vector3.new(egg.x, 0, egg.z)), purple)
					end
					IslandService.render(player)
					IslandService.push(player)
					return
				end
				IslandService.banner(player, ("🎁 MYSTERY: a %s %s!"):format(Creatures.byId[shown].rarity, shown), purple)
			end
			-- (the creature the egg showed, when it did; else by luck)
			local species, mutation = Hatch.roll(egg.tier, luck, Hatch.atLeast(weather.mutation, egg.m), shown)
			local id = IslandService.addCreature(player, data, species, mutation, egg.w)
			if not id then
				return
			end
			data.incubating[key] = nil
			DailyService.add(player, "hatch")
			Net.event("Hatched"):FireClient(player, id, species, mutation, nil, egg.w)
			-- Straight into the pen if there is room (the hatching field stays clear), else into the inventory
			if #data.placed < data.pens then
				table.insert(data.placed, id)
			else
				IslandService.notify(player, ("🐾 The pen is full: your %s is in your inventory"):format(species), "info")
			end
			local index = islandOf[player]
			if index then
				local at = if egg.x and egg.z then Layout.garden(index):PointToWorldSpace(Vector3.new(egg.x, 0, egg.z)) else Layout.incubator(index, slot, data.pasture)
				IslandService.fx("Hatch", at, if mutation ~= "Normal" then Mutations.byId[mutation].color else nil)
			end
			if Mutations.byId[mutation].order >= 3 or Creatures.byId[species].rarity == "Legendary" or Creatures.byId[species].rarity == "Mythic" then
				for _, other in Players:GetPlayers() do
					IslandService.notify(other, ("✨ %s hatched a %s%s!"):format(player.DisplayName, if mutation ~= "Normal" then mutation .. " " else "", species), "rare")
				end
			end
		else
			-- Put the best egg the player holds into the incubator
			local tier, least, size, species = takeEgg(data)
			if not tier then
				IslandService.notify(player, "You have no eggs: steal one from the Wild", "error")
				return
			end
			data.incubating[key] = { tier = tier, start = os.time(), m = least, w = if size ~= "Normal" then size else nil, s = species }
			IslandService.notify(player, ("%s incubating: %s"):format(Hatch.name(tier, size, least ~= nil, species), Format.time(hatchTime(player, tier, slot))), "success")
		end
	end
	IslandService.render(player)
	IslandService.push(player)
end

function IslandService.place(player: Player, id: any)
	local data = DataService.get(player)
	if not data or type(id) ~= "string" or not data.creatures[id] or table.find(data.placed, id) then
		return
	end
	if not IslandService.inOwnGarden(player) then
		IslandService.notify(player, "Go to your garden first", "error")
		return
	end
	if #data.placed >= data.pens then
		IslandService.notify(player, "No room in your garden: take a creature back or buy more room", "error")
		return
	end
	data.stored[id] = nil -- (out of the barn, if it was there)
	table.insert(data.placed, id)
	IslandService.render(player)
	IslandService.push(player)
end

local function take(player: Player, id: any)
	local data = DataService.get(player)
	if not data or type(id) ~= "string" then
		return
	end
	local at = table.find(data.placed, id)
	if not at then
		return
	end
	table.remove(data.placed, at)
	IslandService.render(player)
	IslandService.push(player)
end

-- A bigger pasture (it grows away from the square: Layout.pastureArea)
local function buyPasture(player: Player)
	local data = DataService.get(player)
	if not data or not throttle(player) then
		return
	end
	local price = IslandConfig.PASTURE_PRICES[data.pasture]
	if not price then
		IslandService.notify(player, "Your pasture is as big as it gets", "error")
		return
	end
	if data.coins < price then
		IslandService.notify(player, ("You need 🪙 %s"):format(Format.abbrev(price)), "error")
		return
	end
	data.coins -= price
	data.pasture += 1
	IslandService.notify(player, "Your pasture grew! 🌳", "success")
	IslandService.render(player)
	IslandService.push(player)
end

local function buyStorage(player: Player)
	local data = DataService.get(player)
	if not data or not throttle(player) then
		return
	end
	local price = IslandConfig.STORAGE_PRICES[data.storage]
	if not price then
		IslandService.notify(player, "Your barn is as big as it gets", "error")
		return
	end
	if data.coins < price then
		IslandService.notify(player, ("You need 🪙 %s"):format(Format.abbrev(price)), "error")
		return
	end
	data.coins -= price
	data.storage += 1
	IslandService.notify(player, ("Bigger barn! Room for %d creatures 📦"):format(IslandService.storage(data)), "success")
	IslandService.push(player)
end

-- Feeds the creatures at the trough with the best food the player holds
local function feed(player: Player)
	local data = DataService.get(player)
	local index = islandOf[player]
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not data or not index or not root or not throttle(player) then
		return
	end
	if (root.Position - Layout.garden(index):PointToWorldSpace(Layout.TROUGH)).Magnitude > REACH then
		return
	end
	local food = IslandService.bestFood(data)
	if not food then
		IslandService.notify(player, "No food: buy some at the Shop in town", "error")
		return
	end
	local now = os.time()
	if data.fedUntil >= now + FoodConfig.MAX_FED - 60 then
		IslandService.notify(player, "Your creatures are full!", "error")
		return
	end
	data.food[food.id] -= 1
	data.fedUntil = Food.feed(data.fedUntil, now, food)
	DailyService.add(player, "feed")
	IslandService.notify(player, ("%s Yum! Your creatures earn ×%d for %s"):format(food.icon, FoodConfig.BOOST, Format.time(data.fedUntil - now)), "success")
	IslandService.render(player)
	IslandService.push(player)
end

-- The Mutation Machine (Config/Mutate): a creature's mutation one step up, for coins, once the player is fast
-- enough
local function mutate(player: Player, id: any)
	local data = DataService.get(player)
	if not data or type(id) ~= "string" or not throttle(player) then
		return
	end
	local creature = data.creatures[id]
	if not creature then
		return
	end
	if not Mutate.open(data.power) then
		IslandService.notify(player, ("Locked: the Mutation Machine opens at ⚡ %s"):format(Format.abbrev(MutateConfig.UNLOCK)), "error")
		return
	end
	local nextMutation = Mutate.next(creature.m)
	if not nextMutation then
		IslandService.notify(player, "That's the best mutation there is", "error")
		return
	end
	local price = Mutate.price(creature)
	if data.coins < price then
		IslandService.notify(player, ("You need 🪙 %s"):format(Format.abbrev(price)), "error")
		return
	end
	data.coins -= price
	creature.m = nextMutation
	Net.event("Hatched"):FireClient(player, id, creature.s, creature.m, creature.g)
	IslandService.render(player)
	IslandService.push(player)
end

-- Cube Snap (Config/Snap): four matching creatures become one Mega, four Megas one Rainbow
local function snap(player: Player, id: any)
	local data = DataService.get(player)
	if not data or type(id) ~= "string" or not throttle(player) then
		return
	end
	local group, made = Snap.find(data.creatures, data.placed, id)
	if not group or not made then
		IslandService.notify(player, ("You need %d matching creatures to fuse"):format(SnapConfig.NEED), "error")
		return
	end
	local wasPlaced = false
	for _, other in group do
		data.creatures[other] = nil
		local at = table.find(data.placed, other)
		if at then
			table.remove(data.placed, at)
			wasPlaced = true
		end
	end
	local newId = tostring(data.nextId)
	data.nextId += 1
	data.creatures[newId] = { s = made.s, m = made.m, g = made.g }
	if wasPlaced then
		table.insert(data.placed, newId)
	end
	Net.event("Hatched"):FireClient(player, newId, made.s, made.m, made.g)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		IslandService.fx("Hatch", root.Position - Vector3.new(0, 3, 0), Mutations.byId[made.m] and Mutations.byId[made.m].color)
	end
	if made.g == "Rainbow" then
		for _, other in Players:GetPlayers() do
			IslandService.notify(other, ("🌈 %s fused a %s!"):format(player.DisplayName, Snap.name(made)), "rare")
		end
	end
	IslandService.render(player)
	IslandService.push(player)
end

-- The daily tasks' reward: eggs of the best tier the player has hatched
local function claimDaily(player: Player)
	local data = DataService.get(player)
	if not data or not throttle(player) then
		return
	end
	if not DailyService.claim(player) then
		IslandService.notify(player, "Finish today's tasks first", "error")
		return
	end
	local tier = IslandService.bestTier(data)
	local key = tostring(tier)
	data.eggs[key] = (data.eggs[key] or 0) + DailyConfig.REWARD_EGGS
	local egg = Hatch.egg(tier)
	IslandService.notify(player, ("🎁 Daily reward: a %s! Come back tomorrow for more"):format(if egg then egg.name else "egg"), "rare")
	IslandService.push(player)
end

local function buyPen(player: Player)
	local data = DataService.get(player)
	if not data or not throttle(player) then
		return
	end
	local price = Earn.nextPrice(IslandConfig.PEN_PRICES, data.pens, IslandConfig.PENS)
	if not price then
		IslandService.notify(player, "Your garden is as big as it gets", "error")
		return
	end
	if data.coins < price then
		IslandService.notify(player, ("You need 🪙 %s"):format(Format.abbrev(price)), "error")
		return
	end
	data.coins -= price
	data.pens += 1
	IslandService.notify(player, "Room for one more creature! 🐾", "success")
	IslandService.push(player)
end

function IslandService.init()
	-- Every garden drawn empty to start (its pasture at the first level)
	for index = 1, IslandConfig.ISLANDS do
		render(index, nil, nil)
	end
	DataService.onLoaded(assign)
	Net.event("Snap").OnServerEvent:Connect(snap)
	Net.event("Mutate").OnServerEvent:Connect(mutate)
	Net.event("ClaimDaily").OnServerEvent:Connect(claimDaily)
	Players.PlayerRemoving:Connect(function(player)
		release(player)
		busy[player] = nil
		fast[player] = nil
		friendsIn[player] = nil
		task.defer(countFriends)
	end)
	Players.PlayerAdded:Connect(function()
		task.spawn(countFriends)
	end)
	task.spawn(countFriends)
	Net.event("UseIncubator").OnServerEvent:Connect(useIncubator)
	Net.event("PlaceCreature").OnServerEvent:Connect(IslandService.place)
	Net.event("TakeCreature").OnServerEvent:Connect(take)
	Net.event("BuyPen").OnServerEvent:Connect(buyPen)
	Net.event("BuyStorage").OnServerEvent:Connect(buyStorage)
	Net.event("BuyPasture").OnServerEvent:Connect(buyPasture)
	Net.event("BuyIncubator").OnServerEvent:Connect(buyEggRoom)
	-- (the Bag's "Set down", for the egg tools' click)
	Net.event("SetEgg").OnServerEvent:Connect(function(player, ref, golden)
		-- (ref: the egg's key, Logic/Hatch.key, or a tier)
		local key = if type(ref) == "number" then tostring(ref) elseif type(ref) == "string" then ref else nil
		local tier = if key then Hatch.parse(key) else nil
		if key and tier and Hatch.egg(tier) and type(golden) == "boolean" then
			setEgg(player, key, golden)
		end
	end)
	Net.event("Feed").OnServerEvent:Connect(feed)
	-- Earning: every second, each island's creatures bring in their coins
	task.spawn(function()
		while true do
			task.wait(1)
			for player in islandOf do
				local data = DataService.get(player)
				if data then
					local rate = Earn.islandRate(data.creatures, data.placed)
					if Food.fed(data.fedUntil, os.time()) then
						rate *= FoodConfig.BOOST
					end
					rate *= 1 + (friendsIn[player] or 0) * IslandConfig.FRIEND_BOOST
					if rate > 0 then
						data.coins += rate
						data.stats.earned += rate
						player:SetAttribute("Coins", data.coins)
					end
					player:SetAttribute("Rate", rate)
				end
			end
		end
	end)
end

-- When the creature models arrive, the islands are drawn again with them
function IslandService.redraw()
	table.clear(drawnCreatures)
	for player in islandOf do
		IslandService.render(player)
	end
end

return IslandService
