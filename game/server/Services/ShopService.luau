--!strict
-- The Sell stall in town: the player sells their creatures and the eggs they hold for coins. The Food Shop is
-- here too.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FoodConfig = require(Shared.Config.Food)
local Earn = require(Shared.Logic.Earn)
local Food = require(Shared.Logic.Food)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local IslandService = require(script.Parent.IslandService)

local ShopService = {}

-- Sells one of the player's creatures (not one living in the garden) at the Sell stall
local function sellCreature(player: Player, id: any)
	local data = DataService.get(player)
	local creature = if type(id) == "string" and data then data.creatures[id] else nil
	if not data or not creature then
		return
	end
	if table.find(data.placed, id) or data.stored[id] then
		IslandService.notify(player, "Take it out of the garden or the barn first (in your Bag)", "error")
		return
	end
	local price = Earn.sellPrice(creature)
	data.creatures[id] = nil
	data.coins += price
	IslandService.push(player)
end

-- Sells eggs the player holds: one of a kind, or all of them
local function sellEgg(player: Player, tier: any, golden: any, all: any)
	local data = DataService.get(player)
	local egg = if type(tier) == "number" then Hatch.egg(tier) else nil
	if not data or not egg then
		return
	end
	local key = tostring(egg.tier)
	local bag = if golden == true then data.golden else data.eggs
	local have = bag[key] or 0
	if have <= 0 then
		return
	end
	local count = if all == true then have else 1
	local price = Earn.eggSellPrice(egg.price, golden == true) * count
	bag[key] = if have - count > 0 then have - count else nil
	data.coins += price
	IslandService.push(player)
end

-- The Food Shop: food for the trough, priced on what the player's garden earns
local function buyFood(player: Player, id: any)
	local data = DataService.get(player)
	local food = if type(id) == "string" then FoodConfig.byId[id] else nil
	if not data or not food then
		return
	end
	local price = Food.price(food, Earn.islandRate(data.creatures, data.placed))
	if data.coins < price then
		IslandService.notify(player, ("You need 🪙 %s"):format(Format.abbrev(price)), "error")
		return
	end
	data.coins -= price
	data.food[food.id] = (data.food[food.id] or 0) + 1
	IslandService.notify(player, ("Bought %s %s! Feed your creatures at the trough"):format(food.icon, food.name), "success")
	IslandService.render(player)
	IslandService.push(player)
end

function ShopService.init()
	Net.event("BuyFood").OnServerEvent:Connect(buyFood)
	Net.event("SellCreature").OnServerEvent:Connect(sellCreature)
	Net.event("SellEgg").OnServerEvent:Connect(sellEgg)
end

return ShopService
