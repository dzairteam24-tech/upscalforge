--!strict
-- A farm's stand: its farmer puts harvested crops out at a price of their choosing (within limits), and anyone
-- visiting buys them; the coins go to the farmer even while they're away from their farm.

local Crops = require(script.Parent.Parent.Config.Crops)

export type Lot = { n: number, p: number } -- how many, coins each
export type Holder = { coins: number, barn: { [string]: number }, stand: { [string]: Lot }, stats: any }

local Stand = {}

Stand.KINDS = 6 -- different crops on a stand at once
Stand.MIN = 0.5 -- a price can be from half...
Stand.MAX = 3 -- ...to three times what the barn sells it for

function Stand.priceRange(key: string): (number, number)
	local crop = Crops.byKey[key]
	return math.max(1, math.floor(crop.sell * Stand.MIN)), math.max(1, math.floor(crop.sell * Stand.MAX))
end

local function count(t: { [string]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- Puts n of a crop from the barn on the stand at a price (the price applies to all of that crop on it)
function Stand.put(data: Holder, key: any, n: any, price: any): (boolean, string?)
	if type(key) ~= "string" or not Crops.byKey[key] then
		return false, "crop"
	end
	if type(n) ~= "number" or n ~= math.floor(n) or n < 1 then
		return false, "amount"
	end
	if type(price) ~= "number" or price ~= math.floor(price) then
		return false, "price"
	end
	local low, high = Stand.priceRange(key)
	if price < low or price > high then
		return false, "price"
	end
	if (data.barn[key] or 0) < n then
		return false, "barn"
	end
	if not data.stand[key] and count(data.stand) >= Stand.KINDS then
		return false, "full"
	end
	data.barn[key] -= n
	if data.barn[key] <= 0 then
		data.barn[key] = nil
	end
	local lot = data.stand[key] or { n = 0, p = price }
	lot.n += n
	lot.p = price
	data.stand[key] = lot
	return true, nil
end

-- Takes a crop off the stand, back to the barn
function Stand.take(data: Holder, key: any): boolean
	local lot = type(key) == "string" and data.stand[key]
	if not lot then
		return false
	end
	data.barn[key] = (data.barn[key] or 0) + lot.n
	data.stand[key] = nil
	return true
end

-- A visitor buys n of a crop: coins from the buyer to the farmer, the crops into the buyer's barn. Returns the cost
function Stand.buy(seller: Holder, buyer: Holder, key: any, n: any): (number?, string?)
	if seller == buyer then
		return nil, "self"
	end
	if type(key) ~= "string" or type(n) ~= "number" or n ~= math.floor(n) or n < 1 then
		return nil, "amount"
	end
	local lot = seller.stand[key]
	if not lot or lot.n < n then
		return nil, "stock"
	end
	local cost = lot.p * n
	if buyer.coins < cost then
		return nil, "coins"
	end
	buyer.coins -= cost
	seller.coins += cost
	lot.n -= n
	if lot.n <= 0 then
		seller.stand[key] = nil
	end
	buyer.barn[key] = (buyer.barn[key] or 0) + n
	seller.stats.standSold = (seller.stats.standSold or 0) + n
	seller.stats.standEarned = (seller.stats.standEarned or 0) + cost
	return cost, nil
end

return Stand
