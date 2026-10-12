--!strict
-- The Sell stall in town: the player sells their creatures and the eggs they hold for coins, or buys eggs in
-- stock (Logic/Stock, the same in every server, restocked every few minutes). Creatures can also be sold at the
-- Sell pad (CarryService). When a restock brings a rare egg, the whole server hears about it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FoodConfig = require(Shared.Config.Food)
local Earn = require(Shared.Logic.Earn)
local Food = require(Shared.Logic.Food)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Stock = require(Shared.Logic.Stock)
local Net = require(Shared.Net)

local DailyService = require(script.Parent.DailyService)
local DataService = require(script.Parent.DataService)
local IslandService = require(script.Parent.IslandService)

local ShopService = {}

local RARE_TIER = 9 -- eggs from this tier up are announced when they come in stock

local function buyEgg(player: Player, tier: any)
	local data = DataService.get(player)
	local egg = if type(tier) == "number" then Hatch.egg(tier) else nil
	if not data or not egg then
		return
	end
	if not Hatch.open(egg.tier) then
		IslandService.notify(player, "Coming soon! 🛠️", "info")
		return
	end
	-- The player's buys count against the current restock only
	local window = Stock.window(os.time())
	if data.shop.window ~= window then
		data.shop = { window = window, bought = {} }
	end
	local key = tostring(egg.tier)
	local left = Stock.count(window, egg.tier) - (data.shop.bought[key] or 0)
	if left <= 0 then
		IslandService.notify(player, "Out of stock! Wait for the next restock", "error")
		return
	end
	if data.coins < egg.price then
		IslandService.notify(player, ("You need 🪙 %s"):format(Format.abbrev(egg.price)), "error")
		return
	end
	data.coins -= egg.price
	data.shop.bought[key] = (data.shop.bought[key] or 0) + 1
	data.eggs[key] = (data.eggs[key] or 0) + 1
	DailyService.add(player, "buy")
	IslandService.notify(player, ("Bought a %s! Put it in an incubator in your garden"):format(egg.name), "success")
	IslandService.push(player)
end

-- Sells one of the player's creatures (not one living in the garden) at the Sell stall
local function sellCreature(player: Player, id: any)
	local data = DataService.get(player)
	local creature = if type(id) == "string" and data then data.creatures[id] else nil
	if not data or not creature then
		return
	end
	if table.find(data.placed, id) then
		IslandService.notify(player, "Take it out of the garden first (in your Bag)", "error")
		return
	end
	local price = Earn.sellPrice(creature)
	data.creatures[id] = nil
	data.coins += price
	IslandService.notify(player, ("Sold %s for 🪙 %s"):format(creature.s, Format.abbrev(price)), "success")
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
	IslandService.notify(player, ("Sold %d× %s%s for 🪙 %s"):format(count, if golden == true then "Golden " else "", egg.name, Format.abbrev(price)), "success")
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
	Net.event("BuyEgg").OnServerEvent:Connect(buyEgg)
	Net.event("SellCreature").OnServerEvent:Connect(sellCreature)
	Net.event("SellEgg").OnServerEvent:Connect(sellEgg)
	-- Rare eggs in the new stock, told to everyone
	task.spawn(function()
		local seen = Stock.window(os.time())
		while true do
			task.wait(1)
			local window = Stock.window(os.time())
			if window ~= seen then
				seen = window
				for tier = 11, RARE_TIER, -1 do
					local count = if Hatch.open(tier) then Stock.count(window, tier) else 0
					local egg = Hatch.egg(tier)
					if count > 0 and egg then
						for _, player in Players:GetPlayers() do
							IslandService.notify(player, ("🌟 %s IN STOCK at the Sell Shop! (%d)"):format(string.upper(egg.name), count), "rare")
						end
					end
				end
			end
		end
	end)
end

return ShopService
