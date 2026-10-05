--!strict
-- Gem shop rules: prices, the daily deals (same for everyone each UTC day) and buying.

local GemShop = require(script.Parent.Parent.Config.GemShop)
local Unlocks = require(script.Parent.Unlocks)

export type State = {
	day: number, -- UTC day the deal purchases belong to
	deals: { [string]: boolean }, -- deals bought today
	storage: number, -- Storage upgrades bought
}

export type Holder = {
	gems: number,
	gemShop: State,
	stats: { [string]: number },
	unlockedZones: { [string]: boolean },
}

local Logic = {}

function Logic.refresh(state: State, today: number)
	if state.day ~= today then
		state.day = today
		state.deals = {}
	end
end

-- Offers that can be bought (not deals-only), in shop order.
function Logic.visible(holder: Holder): { GemShop.Offer }
	local out = {}
	for _, offer in GemShop.offers do
		if offer.feature == nil or Unlocks.has(holder, offer.feature) then
			table.insert(out, offer)
		end
	end
	return out
end

-- Today's deals: item offers picked from the day number, so every server shows the same ones.
function Logic.deals(today: number): { string }
	local pool = {}
	for _, offer in GemShop.offers do
		if offer.itemId then
			table.insert(pool, offer.id)
		end
	end
	local picked = {}
	local state = (today * 7919 + 17) % 2147483647
	for _ = 1, math.min(GemShop.DEALS_PER_DAY, #pool) do
		state = (state * 48271) % 2147483647
		table.insert(picked, table.remove(pool, (state % #pool) + 1) :: string)
	end
	return picked
end

function Logic.isDeal(id: string, today: number): boolean
	return table.find(Logic.deals(today), id) ~= nil
end

-- Price of an offer: Storage gets dearer each time; deals are cheaper.
function Logic.price(holder: Holder, id: string, asDeal: boolean): number
	local offer = GemShop.byId[id]
	if not offer then
		return math.huge
	end
	local price = offer.price
	if offer.upgrade == "Storage" then
		price += holder.gemShop.storage * GemShop.STORAGE_PRICE_STEP
	end
	if asDeal then
		price = math.floor(price * (1 - GemShop.DEAL_DISCOUNT) + 0.5)
	end
	return price
end

function Logic.canBuy(holder: Holder, id: string, asDeal: boolean, today: number): (boolean, string?)
	local offer = GemShop.byId[id]
	if not offer then
		return false, "Unknown offer"
	end
	if offer.feature and not Unlocks.has(holder, offer.feature) then
		return false, Unlocks.lockedText(offer.feature)
	end
	Logic.refresh(holder.gemShop, today)
	if asDeal then
		if not Logic.isDeal(id, today) then
			return false, "That deal is over"
		end
		if holder.gemShop.deals[id] then
			return false, "You already got this deal today"
		end
	end
	if offer.upgrade == "Storage" and holder.gemShop.storage >= GemShop.STORAGE_MAX then
		return false, "Storage is maxed out"
	end
	if holder.gems < Logic.price(holder, id, asDeal) then
		return false, "Not enough gems"
	end
	return true, nil
end

-- Takes the gems and records the purchase. Returns the offer to give. Call canBuy first.
function Logic.buy(holder: Holder, id: string, asDeal: boolean, today: number): GemShop.Offer
	local offer = GemShop.byId[id]
	holder.gems -= Logic.price(holder, id, asDeal)
	Logic.refresh(holder.gemShop, today)
	if asDeal then
		holder.gemShop.deals[id] = true
	end
	if offer.upgrade == "Storage" then
		holder.gemShop.storage += 1
	end
	return offer
end

function Logic.storageBonus(state: State?): number
	return if state then state.storage * GemShop.STORAGE_STEP else 0
end

return Logic
