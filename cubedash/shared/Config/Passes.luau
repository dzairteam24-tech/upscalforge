--!strict
-- What Robux buys, and ONLY convenience: every one of these can also be had for free by running. (Roblox shows
-- the live price from the pass or product itself; the numbers here are placeholders for the shop's labels.)
-- Paste each id in after making the pass or developer product in Creator Hub (Monetization). id = 0: not set up
-- yet; in Studio the shop then gives it to you for testing without Robux.

export type Pass = { key: string, id: number, name: string, price: number, desc: string }
export type Product = {
	key: string,
	id: number,
	name: string,
	price: number,
	desc: string,
	boostMinutes: number?, -- a double-coins boost
	incomeMinutes: number?, -- that many minutes of their own coin income, right now
	wall: boolean?, -- the speed their current wall needs, right now
}

return {
	PASSES = {
		{ key = "Orbs2", id = 0, name = "2x Speed", price = 399, desc = "Every orb gives double speed." },
		{ key = "Coins2", id = 0, name = "2x Coins", price = 349, desc = "Every coin you earn is doubled." },
		{ key = "Magnet", id = 0, name = "Super Magnet", price = 199, desc = "Orbs fly to you from twice as far." },
		{ key = "Vip", id = 0, name = "VIP", price = 499, desc = "+25% coins, a golden trail and the VIP tag." },
	} :: { Pass },
	PRODUCTS = {
		{ key = "Wall", id = 0, name = "Wall Breaker", price = 99, desc = "Get the speed your next wall needs, now.", wall = true },
		{ key = "Boost30", id = 0, name = "2x Coins, 30 min", price = 79, desc = "A double-coins boost for half an hour.", boostMinutes = 30 },
		{ key = "CoinsS", id = 0, name = "Coin Pack S", price = 49, desc = "30 minutes of your coins, right now.", incomeMinutes = 30 },
		{ key = "CoinsL", id = 0, name = "Coin Pack L", price = 199, desc = "3 hours of your coins, right now.", incomeMinutes = 180 },
	} :: { Product },
}
