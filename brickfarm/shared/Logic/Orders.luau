--!strict
-- The town's orders board: each farmer has three orders, "bring 6 Corn: 300 coins". Some ask for a crop they
-- can't grow yet: those pay the most, and are why neighbours buy from each other's stands. Done orders are
-- replaced at once; one order can be swapped for free every so often.

local Crops = require(script.Parent.Parent.Config.Crops)
local Level = require(script.Parent.Level)

export type Order = { c: string, n: number, coins: number, xp: number }
export type Holder = { xp: number, barn: { [string]: number }, coins: number, orders: { Order }, swapAt: number, stats: any }

local Orders = {}

Orders.COUNT = 3
Orders.PAY = 1.6 -- an order pays this many times the crops' worth...
Orders.PAY_LOCKED = 2.3 -- ...or this for a crop they can't grow yet
Orders.AHEAD = 3 -- orders may ask for crops up to this many levels above theirs
Orders.SWAP_EVERY = 600 -- seconds between free swaps

-- One new order (`rand(a, b)` gives a whole number from a to b)
function Orders.make(level: number, rand: (number, number) -> number): Order
	local choices: { Crops.Crop } = {}
	for _, crop in Crops.LIST do
		if crop.level <= level then
			table.insert(choices, crop)
			table.insert(choices, crop) -- (the ones they grow come up more)
		elseif crop.level <= level + Orders.AHEAD then
			table.insert(choices, crop)
		end
	end
	local crop = choices[rand(1, #choices)]
	local n = crop.yield * rand(2, 5)
	local locked = crop.level > level
	local coins = math.floor(n * crop.sell * (if locked then Orders.PAY_LOCKED else Orders.PAY) / 5 + 0.5) * 5
	local xp = math.max(1, math.floor(crop.xp * n / crop.yield * 0.8))
	return { c = crop.key, n = n, coins = coins, xp = xp }
end

-- Fills up to three
function Orders.fill(data: Holder, rand: (number, number) -> number)
	local level = (Level.of(data.xp))
	while #data.orders < Orders.COUNT do
		table.insert(data.orders, Orders.make(level, rand))
	end
end

-- Delivers order i from the barn. Returns the coins and XP, or nil and why not
function Orders.deliver(data: Holder, i: any, rand: (number, number) -> number): (number?, number | string)
	if type(i) ~= "number" then
		return nil, "order"
	end
	local order = data.orders[i]
	if not order then
		return nil, "order"
	end
	if (data.barn[order.c] or 0) < order.n then
		return nil, "crops"
	end
	data.barn[order.c] -= order.n
	if data.barn[order.c] <= 0 then
		data.barn[order.c] = nil
	end
	data.coins += order.coins
	data.xp += order.xp
	data.stats.orders = (data.stats.orders or 0) + 1
	table.remove(data.orders, i)
	Orders.fill(data, rand)
	return order.coins, order.xp
end

-- Swaps order i for a new one (free, every SWAP_EVERY seconds)
function Orders.swap(data: Holder, i: any, now: number, rand: (number, number) -> number): (boolean, string?)
	if type(i) ~= "number" or not data.orders[i] then
		return false, "order"
	end
	if now < data.swapAt then
		return false, "wait"
	end
	table.remove(data.orders, i)
	Orders.fill(data, rand)
	data.swapAt = now + Orders.SWAP_EVERY
	return true, nil
end

return Orders
