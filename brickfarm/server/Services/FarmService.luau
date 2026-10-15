--!strict
-- The farms on the server: gives each player a farm of the village when they join (and frees it when they
-- leave), shows their land and crops on its tiles (as attributes the phones build from), and checks every plant,
-- harvest, purchase and sale against the rules (Logic/Farm) and where the player really is.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crops = require(Shared.Config.Crops)
local FarmConfig = require(Shared.Config.Farm)
local Format = require(Shared.Logic.Format)
local Game = require(Shared.Config.Game)
local Farm = require(Shared.Logic.Farm)
local Land = require(Shared.Logic.Land)
local Layout = require(Shared.Logic.Layout)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local Village = require(script.Parent.Parent.Village)

local FarmService = {}

local farms: { Model } = {}
local owners: { [number]: Player } = {} -- farm index -> its farmer
local farmOf: { [Player]: number } = {}

local function notify(player: Player, text: string, kind: string)
	Net.event("Notify"):FireClient(player, text, kind)
end

function FarmService.farmOf(player: Player): number?
	return farmOf[player]
end

function FarmService.model(index: number): Model?
	return farms[index]
end

-- The tile part of a farm
function FarmService.tile(index: number, n: number): BasePart?
	local model = farms[index]
	local folder = model and model:FindFirstChild("Tiles")
	return folder and folder:FindFirstChild("Tile" .. n) :: BasePart?
end

-- Puts a player's land and crops on their farm's tiles
function FarmService.show(player: Player)
	local data = DataService.get(player)
	local index = farmOf[player]
	if not data or not index then
		return
	end
	for n = 1, Land.MAX do
		local tile = FarmService.tile(index, n)
		if tile then
			local owned = n <= data.tiles
			local planted = data.plots[tostring(n)]
			tile:SetAttribute("Owned", owned)
			tile:SetAttribute("Crop", if planted then planted.c else "")
			tile:SetAttribute("Planted", if planted then planted.t else 0)
			tile.Color = if owned then Village.SOIL else Village.FOR_SALE
		end
	end
end

local function clear(index: number)
	for n = 1, Land.MAX do
		local tile = FarmService.tile(index, n)
		if tile then
			tile:SetAttribute("Owned", false)
			tile:SetAttribute("Crop", "")
			tile:SetAttribute("Planted", 0)
			tile.Color = Village.FOR_SALE
		end
	end
	local model = farms[index]
	if model then
		model:SetAttribute("Owner", 0)
		Village.setOwner(model, nil)
	end
end

-- Gives a player the first free farm
function FarmService.assign(player: Player): number?
	if farmOf[player] then
		return farmOf[player]
	end
	for index = 1, FarmConfig.FARMS do
		if not owners[index] then
			owners[index] = player
			farmOf[player] = index
			local model = farms[index]
			if model then
				model:SetAttribute("Owner", player.UserId)
				Village.setOwner(model, player.DisplayName or player.Name)
			end
			return index
		end
	end
	return nil
end

function FarmService.release(player: Player)
	local index = farmOf[player]
	if index then
		owners[index] = nil
		farmOf[player] = nil
		clear(index)
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Their farmer stands at the front of their farm
function FarmService.goHome(player: Player)
	local index = farmOf[player]
	local character = player.Character
	if index and character then
		character:PivotTo(Layout.spawn(index))
	end
end

-- A broke farmer (no seeds, nothing growing, nothing to sell, no coins for a seed) gets a few seeds free
function FarmService.rescue(data: any): boolean
	local cheapest = Crops.LIST[1]
	if next(data.plots) == nil and next(data.seeds) == nil and next(data.barn) == nil and data.coins < cheapest.seed then
		data.seeds[cheapest.key] = 4
		return true
	end
	return false
end

-- A tap on a tile of their farm: harvest it if it's ready, plant `key` if it's empty
function FarmService.tap(player: Player, n: any, key: any): string?
	local data = DataService.get(player)
	local index = farmOf[player]
	if not data or not index or type(n) ~= "number" then
		return nil
	end
	local tile = FarmService.tile(index, n)
	local root = rootOf(player)
	if not tile or not root or (root.CFrame.Position - tile.CFrame.Position).Magnitude > Game.REACH then
		return nil
	end
	local now = os.time()
	if data.plots[tostring(n)] then
		local before = Farm.level(data)
		local crop, amount, xp, up = Farm.harvest(data, n, now)
		if not crop then
			return nil
		end
		Net.event("Harvested"):FireClient(player, n, crop.key, amount, xp)
		if up then
			local level = Farm.level(data)
			local unlocked = {}
			for _, c in Crops.LIST do
				if c.level > before and c.level <= level then
					table.insert(unlocked, c.key)
				end
			end
			Net.event("LevelUp"):FireClient(player, level, unlocked)
		end
		FarmService.show(player)
		DataService.push(player)
		return "harvest"
	end
	local ok, why = Farm.plant(data, n, key, now)
	if not ok then
		if why == "seeds" then
			notify(player, "No seeds of that left: buy more in Seeds", "bad")
		end
		return nil
	end
	FarmService.show(player)
	DataService.push(player)
	return "plant"
end

function FarmService.buySeeds(player: Player, key: any, amount: any): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	local ok, why = Farm.buySeeds(data, key, amount)
	if not ok then
		if why == "coins" then
			notify(player, "Not enough coins yet", "bad")
		elseif why == "level" then
			notify(player, "Unlocks at a higher level", "bad")
		end
		return false
	end
	DataService.push(player)
	return true
end

function FarmService.sell(player: Player, key: any): number
	local data = DataService.get(player)
	if not data or (key ~= "all" and (type(key) ~= "string" or not Crops.byKey[key])) then
		return 0
	end
	local coins = Farm.sell(data, key)
	if coins > 0 then
		notify(player, ("Sold for %s coins!"):format(Format.short(coins)), "gold")
		DataService.push(player)
	end
	return coins
end

function FarmService.expand(player: Player): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	local ok, why = Farm.expand(data)
	if not ok then
		notify(player, why or "Not yet", "bad")
		return false
	end
	notify(player, "More land!", "good")
	FarmService.show(player)
	DataService.push(player)
	return true
end

function FarmService.init()
	farms = Village.build(workspace)
	DataService.farmOf = FarmService.farmOf

	Net.event("Tile").OnServerEvent:Connect(FarmService.tap)
	Net.event("BuySeeds").OnServerEvent:Connect(FarmService.buySeeds)
	Net.event("Sell").OnServerEvent:Connect(FarmService.sell)
	Net.event("Expand").OnServerEvent:Connect(FarmService.expand)
	Net.event("GuideDone").OnServerEvent:Connect(function(player, step)
		local data = DataService.get(player)
		if data and type(step) == "number" and step == math.floor(step) and step >= 0 and step <= 20 then
			data.guide = math.max(data.guide, step)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt.Name == "BarnPrompt" then
			Net.event("OpenBarn"):FireClient(player)
		end
	end)

	DataService.onLoaded(function(player, data)
		local index = FarmService.assign(player)
		if not index then
			notify(player, "This village is full", "bad")
			return
		end
		if FarmService.rescue(data) then
			notify(player, "A neighbour left you some seeds!", "good")
		end
		local ready = Farm.readyCount(data, os.time())
		if ready > 0 and data.stats.planted > 0 then
			notify(player, ("Welcome back! %d crops are ready to harvest."):format(ready), "gold")
		end
		FarmService.show(player)
		FarmService.goHome(player)
		DataService.push(player)
	end)
	DataService.onPushed(function(player, data)
		if FarmService.rescue(data) then
			notify(player, "A neighbour left you some seeds!", "good")
			DataService.push(player)
		end
	end)
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			task.defer(FarmService.goHome, player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	DataService.onLeaving(FarmService.release)
end

return FarmService
