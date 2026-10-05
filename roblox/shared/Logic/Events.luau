--!strict
-- Which event is running, its tokens, bonus and shop.

local Config = require(script.Parent.Parent.Config.Events)

export type EventState = { tokens: number, bought: { [string]: boolean } }

local Events = {}

-- The running event, or nil. `forced` makes an event run now (Studio testing).
function Events.active(now: number, forced: string?): Config.Event?
	if forced and Config.byId[forced] then
		return Config.byId[forced]
	end
	for _, event in Config.list do
		if now >= event.starts and now < event.ends then
			return event
		end
	end
	return nil
end

-- Tokens for breaking a source. Fractional values are a chance of 1.
function Events.tokensFor(event: Config.Event, kind: string, rng: () -> number): number
	local value = event.tokens[kind] or 0
	local whole = math.floor(value)
	if rng() < value - whole then
		whole += 1
	end
	return whole
end

function Events.bonus(event: Config.Event?, stat: string): number
	if event and event.bonus and event.bonus.stat == stat then
		return event.bonus.mult
	end
	return 1
end

function Events.offer(event: Config.Event, offerId: string): Config.Offer?
	for _, offer in event.shop do
		if offer.id == offerId then
			return offer
		end
	end
	return nil
end

function Events.canBuy(event: Config.Event, state: EventState, offerId: string): (boolean, string?)
	local offer = Events.offer(event, offerId)
	if not offer then
		return false, "Unknown offer"
	end
	if offer.once and state.bought[offerId] then
		return false, "You already have it"
	end
	if state.tokens < offer.price then
		return false, ("Not enough %s"):format(event.token)
	end
	return true, nil
end

-- Takes the tokens and records the purchase. Call canBuy first.
function Events.buy(event: Config.Event, state: EventState, offerId: string): Config.Offer
	local offer = Events.offer(event, offerId) :: Config.Offer
	state.tokens -= offer.price
	state.bought[offerId] = true
	return offer
end

return Events
