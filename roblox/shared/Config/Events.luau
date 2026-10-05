--!strict
-- Limited-time events. Add one by copying an entry: dates are UTC. During an event, breaking sources
-- gives event tokens, a bonus may apply, and the event shop sells looks and items for tokens.
-- Rule: events never sell stronger creatures, so nobody loses power for missing one.
-- In Studio, set TEST_EVENT to an event id to play it right now.

export type Offer = {
	id: string,
	price: number, -- tokens
	title: string?,
	trail: string?,
	ride: string?,
	itemId: string?,
	amount: number?,
	once: boolean?, -- titles, trails and rides can be bought once
}

export type Event = {
	id: string,
	name: string,
	starts: number, -- os.time() UTC
	ends: number,
	color: Color3,
	token: string, -- "Candy"
	tokenIcon: string, -- "🍬"
	tokens: { [string]: number }, -- source kind -> tokens per break (Pile can be fractional = chance)
	bonus: { stat: string, mult: number }?, -- whole-game bonus while it runs
	shop: { Offer },
}

-- Midnight UTC of a date as a unix time (doesn't depend on the server's time zone).
local function utc(year: number, month: number, day: number): number
	local y = if month <= 2 then year - 1 else year
	local era = (if y >= 0 then y else y - 399) // 400
	local yoe = y - era * 400
	local mp = (month + 9) % 12
	local doy = (153 * mp + 2) // 5 + day - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return (era * 146097 + doe - 719468) * 86400
end

local TOKENS = { Pile = 0.15, Chest = 1, Safe = 2, Vault = 5, Big = 10, Guardian = 25 }

local list: { Event } = {
	{
		id = "Spooky26",
		name = "Spooky Fest",
		starts = utc(2026, 10, 24),
		ends = utc(2026, 11, 7),
		color = Color3.fromRGB(255, 140, 40),
		token = "Candy",
		tokenIcon = "🍬",
		tokens = TOKENS,
		bonus = { stat = "Gem", mult = 2 },
		shop = {
			{ id = "Title", price = 300, title = "E_Spooky", once = true },
			{ id = "Trail", price = 600, trail = "E_Pumpkin", once = true },
			{ id = "Ride", price = 1200, ride = "E_Broom", once = true },
			{ id = "Elixir", price = 60, itemId = "Elixir_Luck_2", amount = 1 },
			{ id = "Sticker", price = 150, itemId = "Sticker_Star_1", amount = 1 },
			{ id = "Key", price = 200, itemId = "KeyHalf_Golden", amount = 1 },
		},
	},
	{
		id = "Snow26",
		name = "Snow Fest",
		starts = utc(2026, 12, 19),
		ends = utc(2027, 1, 2),
		color = Color3.fromRGB(150, 220, 255),
		token = "Snowflakes",
		tokenIcon = "❄️",
		tokens = TOKENS,
		bonus = { stat = "Coins", mult = 1.25 },
		shop = {
			{ id = "Title", price = 300, title = "E_Frosty", once = true },
			{ id = "Trail", price = 600, trail = "E_Snow", once = true },
			{ id = "Ride", price = 1200, ride = "E_Sled", once = true },
			{ id = "Elixir", price = 60, itemId = "Elixir_Coins_3", amount = 1 },
			{ id = "Sticker", price = 150, itemId = "Sticker_Coin_2", amount = 1 },
			{ id = "Gadget", price = 120, itemId = "Gadget_CoinTotem", amount = 1 },
		},
	},
}

local byId: { [string]: Event } = {}
for _, event in list do
	byId[event.id] = event
end

return {
	list = list,
	byId = byId,
	utc = utc,
	TEST_EVENT = nil :: string?,
}
