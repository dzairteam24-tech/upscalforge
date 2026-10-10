--!strict
-- The Egg Shop's stock (Config/Shop): which eggs are in, and how many, in each restock window. It follows the
-- clock, so it's the same in every server.

local ShopConfig = require(script.Parent.Parent.Config.Shop)
local Hash = require(script.Parent.Hash)

local Stock = {}

function Stock.window(t: number): number
	return t // ShopConfig.RESTOCK
end

-- When the window after `t`'s starts
function Stock.restockAt(t: number): number
	return (Stock.window(t) + 1) * ShopConfig.RESTOCK
end

-- How many of a tier's eggs are in stock in a window (0 when it isn't)
function Stock.count(window: number, tier: number): number
	local rule = ShopConfig.STOCK[tier]
	if not rule then
		return 0
	end
	if tier > 1 and Hash.unit(window, tier, 1) >= rule.chance then
		return 0
	end
	return 1 + math.floor(Hash.unit(window, tier, 2) * rule.most)
end

return Stock
