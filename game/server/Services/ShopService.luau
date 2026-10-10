--!strict
-- The Egg Shop in town: eggs in stock (Logic/Stock, the same in every server, restocked every few minutes)
-- to buy with coins, and creatures to sell back for coins.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Earn = require(Shared.Logic.Earn)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Stock = require(Shared.Logic.Stock)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local IslandService = require(script.Parent.IslandService)

local ShopService = {}

local function buyEgg(player: Player, tier: any)
	local data = DataService.get(player)
	local egg = if type(tier) == "number" then Hatch.egg(tier) else nil
	if not data or not egg then
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
	IslandService.notify(player, ("Bought a %s! Put it in an incubator in your garden"):format(egg.name), "success")
	IslandService.push(player)
end

local function sell(player: Player, id: any)
	local data = DataService.get(player)
	if not data or type(id) ~= "string" then
		return
	end
	local creature = data.creatures[id]
	if not creature then
		return
	end
	local price = Earn.sellPrice(creature)
	data.creatures[id] = nil
	local at = table.find(data.placed, id)
	if at then
		table.remove(data.placed, at)
		IslandService.render(player)
	end
	data.coins += price
	IslandService.notify(player, ("Sold %s for 🪙 %s"):format(creature.s, Format.abbrev(price)), "success")
	IslandService.push(player)
end

function ShopService.init()
	Net.event("BuyEgg").OnServerEvent:Connect(buyEgg)
	Net.event("SellCreature").OnServerEvent:Connect(sell)
end

return ShopService
