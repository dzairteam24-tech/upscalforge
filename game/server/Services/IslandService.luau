--!strict
-- The heart of the game. Each player in the server gets one of the islands (WorldService) while they play.
-- On it, incubators hatch eggs in real time, even while the player is away; an egg that finishes in a special
-- weather (Logic/Weather) hatches at least that mutation. Hatched creatures live on the island and earn coins
-- every second, and for up to OFFLINE_HOURS while their owner is away.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared.Config.Creatures)
local FoodConfig = require(Shared.Config.Food)
local IslandConfig = require(Shared.Config.Island)
local Mutations = require(Shared.Config.Mutations)
local Earn = require(Shared.Logic.Earn)
local Food = require(Shared.Logic.Food)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Layout = require(Shared.Logic.Layout)
local Weather = require(Shared.Logic.Weather)
local PetModel = require(Shared.PetModel)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)

type Data = DataService.Data

local IslandService = {}

local REACH = 14 -- how close to an incubator a player has to stand to use it

local owners: { [number]: Player } = {}
-- Incubators whose egg a thief is carrying off right now (RaidService): owner -> slot -> true
IslandService.carried = {} :: { [Player]: { [number]: boolean } }
local islandOf: { [Player]: number } = {}
local rng = Random.new()

function IslandService.notify(player: Player, text: string, kind: string?)
	Net.event("Notify"):FireClient(player, text, kind or "info")
end

-- Sends the player their data (the client shows it; the server's copy is the truth)
function IslandService.push(player: Player)
	local data = DataService.get(player)
	if data then
		Net.event("Data"):FireClient(player, data, islandOf[player])
		player:SetAttribute("Coins", data.coins)
		player:SetAttribute("FedUntil", data.fedUntil)
	end
end

function IslandService.islandOf(player: Player): number?
	return islandOf[player]
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
		if species and species.tier <= 10 and species.tier > best then
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

-- Adds a hatched creature (it moves onto the island if there's room); nil when the player's storage is full
function IslandService.addCreature(player: Player, data: Data, species: string, mutation: string): string?
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
	data.creatures[id] = { s = species, m = mutation }
	data.stats.hatched += 1
	if #data.placed < data.pens then
		table.insert(data.placed, id)
	end
	return id
end

---------------------------------------------------------------------------------------------------------------
-- Drawing an island

local function render(index: number, player: Player?, data: Data?)
	local island = WorldService.island(index)
	if not island then
		return
	end
	island:SetAttribute("Owner", if player then player.UserId else 0)
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
	for _, pad in island:GetChildren() do
		local slot = pad:GetAttribute("Slot")
		if type(slot) ~= "number" then
			continue
		end
		local egg = if data then data.incubating[tostring(slot)] else nil
		pad:SetAttribute("Owner", if player then player.UserId else 0)
		pad:SetAttribute("Open", if data then slot <= data.incubators else false)
		pad:SetAttribute("Price", if data and slot == data.incubators + 1 then Earn.nextPrice(IslandConfig.INCUBATOR_PRICES, data.incubators, IslandConfig.INCUBATORS) or 0 else 0)
		pad:SetAttribute("Tier", if egg then egg.tier else 0)
		local marks = if player then IslandService.carried[player] else nil
		pad:SetAttribute("Carried", marks ~= nil and marks[slot] == true)
		pad:SetAttribute("Start", if egg then egg.start else 0)
		pad:SetAttribute("Duration", if egg then Hatch.seconds(egg.tier) else 0)
	end
	-- The creatures living there
	local folder = island:FindFirstChild("Creatures")
	if folder then
		folder:ClearAllChildren()
		if data then
			for slot, id in data.placed do
				local creature = data.creatures[id]
				if not creature then
					continue
				end
				local at = Layout.pen(index, slot)
				local built = PetModel.build({ s = creature.s, v = creature.m, z = "Normal" })
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
				built.model:SetAttribute("Mutation", creature.m)
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
	IslandService.push(player)
	-- Start on the island
	task.spawn(function()
		local character = player.Character or player.CharacterAdded:Wait()
		local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		local index = islandOf[player]
		if root and index then
			local frame = Layout.garden(index)
			root.CFrame = frame * CFrame.new(0, 4, -10) * CFrame.Angles(0, math.pi, 0)
		end
	end)
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
	for _, pad in island:GetChildren() do
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

local function useIncubator(player: Player, slot: any)
	local data = DataService.get(player)
	if not data or type(slot) ~= "number" or slot ~= slot // 1 or slot < 1 or not throttle(player) then
		return
	end
	if not nearPad(player, slot) then
		return
	end
	local key = tostring(slot)
	if slot > data.incubators then
		-- Buy the next incubator
		local price = Earn.nextPrice(IslandConfig.INCUBATOR_PRICES, data.incubators, IslandConfig.INCUBATORS)
		if slot ~= data.incubators + 1 or not price then
			IslandService.notify(player, "Unlock the incubators in order", "error")
			return
		end
		if data.coins < price then
			IslandService.notify(player, ("You need 🪙 %s"):format(Format.abbrev(price)), "error")
			return
		end
		data.coins -= price
		data.incubators += 1
		IslandService.notify(player, "New incubator! 🥚", "success")
	else
		local egg = data.incubating[key]
		if egg and IslandService.carried[player] and IslandService.carried[player][slot] then
			IslandService.notify(player, "A thief is running off with that egg! Catch them!", "error")
			return
		end
		if egg then
			local done = egg.start + Hatch.seconds(egg.tier)
			local now = os.time()
			if now < done then
				IslandService.notify(player, ("Still incubating: %s left"):format(Format.time(done - now)))
				return
			end
			local weather = Weather.at(done)
			local species, mutation = Hatch.roll(egg.tier, function()
				return rng:NextNumber()
			end, weather.mutation)
			local id = IslandService.addCreature(player, data, species, mutation)
			if not id then
				return
			end
			data.incubating[key] = nil
			Net.event("Hatched"):FireClient(player, id, species, mutation)
			if Mutations.byId[mutation].order >= 3 or Creatures.byId[species].rarity == "Legendary" then
				for _, other in Players:GetPlayers() do
					IslandService.notify(other, ("✨ %s hatched a %s%s!"):format(player.DisplayName, if mutation ~= "Normal" then mutation .. " " else "", species), "rare")
				end
			end
		else
			-- Put in the best egg the player holds
			local tier = 0
			for key2, count in data.eggs do
				local t = tonumber(key2)
				if t and count > 0 and t > tier then
					tier = t
				end
			end
			if tier == 0 then
				IslandService.notify(player, "You have no eggs: buy some at the Egg Shop in town", "error")
				return
			end
			data.eggs[tostring(tier)] -= 1
			data.incubating[key] = { tier = tier, start = os.time() }
			local egg2 = Hatch.egg(tier)
			IslandService.notify(player, ("%s incubating: %s"):format(if egg2 then egg2.name else "Egg", Format.time(Hatch.seconds(tier))), "success")
		end
	end
	IslandService.render(player)
	IslandService.push(player)
end

local function place(player: Player, id: any)
	local data = DataService.get(player)
	if not data or type(id) ~= "string" or not data.creatures[id] or table.find(data.placed, id) then
		return
	end
	if #data.placed >= data.pens then
		IslandService.notify(player, "No room in your garden: take a creature back or buy more room", "error")
		return
	end
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
		IslandService.notify(player, "No food: buy some at the Food Shop in town", "error")
		return
	end
	local now = os.time()
	if data.fedUntil >= now + FoodConfig.MAX_FED - 60 then
		IslandService.notify(player, "Your creatures are full!", "error")
		return
	end
	data.food[food.id] -= 1
	data.fedUntil = Food.feed(data.fedUntil, now, food)
	IslandService.notify(player, ("%s Yum! Your creatures earn ×%d for %s"):format(food.icon, FoodConfig.BOOST, Format.time(data.fedUntil - now)), "success")
	IslandService.render(player)
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
	DataService.onLoaded(assign)
	Players.PlayerRemoving:Connect(function(player)
		release(player)
		busy[player] = nil
	end)
	Net.event("UseIncubator").OnServerEvent:Connect(useIncubator)
	Net.event("PlaceCreature").OnServerEvent:Connect(place)
	Net.event("TakeCreature").OnServerEvent:Connect(take)
	Net.event("BuyPen").OnServerEvent:Connect(buyPen)
	Net.event("BuyStorage").OnServerEvent:Connect(buyStorage)
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
	for player in islandOf do
		IslandService.render(player)
	end
end

return IslandService
