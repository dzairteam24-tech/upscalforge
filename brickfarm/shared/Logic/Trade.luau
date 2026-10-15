--!strict
-- A trade between two farmers standing together: each puts in harvested crops and coins; when both say ready,
-- everything changes hands at once. Any change to an offer takes both readies away (so nobody is tricked).

local Crops = require(script.Parent.Parent.Config.Crops)

export type Offer = { items: { [string]: number }, coins: number }
export type Holder = { coins: number, barn: { [string]: number }, stats: any }
export type Session = { a: any, b: any, offers: { [any]: Offer }, ready: { [any]: boolean } }

local Trade = {}

Trade.KINDS = 6

function Trade.new(a: any, b: any): Session
	return { a = a, b = b, offers = { [a] = { items = {}, coins = 0 }, [b] = { items = {}, coins = 0 } }, ready = {} }
end

-- Whether someone can give what they've offered
function Trade.covered(offer: Offer, data: Holder): boolean
	if data.coins < offer.coins then
		return false
	end
	for key, n in offer.items do
		if (data.barn[key] or 0) < n then
			return false
		end
	end
	return true
end

-- Sets one side's offer (checked against what they have); both readies go
function Trade.offer(session: Session, who: any, items: any, coins: any, data: Holder): (boolean, string?)
	if not session.offers[who] then
		return false, "who"
	end
	if type(items) ~= "table" or type(coins) ~= "number" or coins ~= math.floor(coins) or coins < 0 then
		return false, "offer"
	end
	local clean: { [string]: number } = {}
	local kinds = 0
	for key, n in items do
		if type(key) ~= "string" or not Crops.byKey[key] or type(n) ~= "number" or n ~= math.floor(n) or n < 0 then
			return false, "offer"
		end
		if n > 0 then
			clean[key] = n
			kinds += 1
		end
	end
	if kinds > Trade.KINDS then
		return false, "offer"
	end
	local offer = { items = clean, coins = coins }
	if not Trade.covered(offer, data) then
		return false, "short"
	end
	session.offers[who] = offer
	table.clear(session.ready)
	return true, nil
end

function Trade.setReady(session: Session, who: any, ready: boolean)
	if session.offers[who] then
		session.ready[who] = ready
	end
end

function Trade.bothReady(session: Session): boolean
	return session.ready[session.a] == true and session.ready[session.b] == true
end

-- Everything changes hands (if both are ready and can still give what they offered)
function Trade.complete(session: Session, dataA: Holder, dataB: Holder): (boolean, string?)
	if not Trade.bothReady(session) then
		return false, "ready"
	end
	local offerA, offerB = session.offers[session.a], session.offers[session.b]
	if not Trade.covered(offerA, dataA) or not Trade.covered(offerB, dataB) then
		table.clear(session.ready)
		return false, "short"
	end
	local function move(offer: Offer, from: Holder, to: Holder)
		from.coins -= offer.coins
		to.coins += offer.coins
		for key, n in offer.items do
			from.barn[key] -= n
			if from.barn[key] <= 0 then
				from.barn[key] = nil
			end
			to.barn[key] = (to.barn[key] or 0) + n
		end
	end
	move(offerA, dataA, dataB)
	move(offerB, dataB, dataA)
	dataA.stats.trades = (dataA.stats.trades or 0) + 1
	dataB.stats.trades = (dataB.stats.trades or 0) + 1
	return true, nil
end

return Trade
