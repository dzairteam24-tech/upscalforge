--!strict
-- What Robux buys, and ONLY convenience: every one of these can also be earned for free with time. (Roblox
-- shows the live price from the pass or product itself; the numbers here are placeholders for the shop's labels.)
-- Paste each id in after making the pass or developer product in Creator Hub (Monetization). id = 0: not set up
-- yet; in Studio the shop then gives it to you for testing without Robux.

export type Pass = { key: string, id: number, name: string, price: number, desc: string }
export type Product = { key: string, id: number, name: string, price: number, desc: string, boostMinutes: number?, incomeMinutes: number? }

return {
	PASSES = {
		{ key = "Coins2", id = 0, name = "2x Coins", price = 399, desc = "Everything you sell is worth double." },
		{ key = "AutoDig", id = 0, name = "Auto Dig", price = 299, desc = "Keeps digging for you: no need to hold the button." },
		{ key = "RemoteSell", id = 0, name = "Sell Anywhere", price = 249, desc = "Sell your gems from anywhere, no trip to town." },
		{ key = "Offline", id = 0, name = "Long Offline Miner", price = 199, desc = "Your drone works up to 12 hours while you're away (free: 2)." },
		{ key = "Vip", id = 0, name = "VIP", price = 499, desc = "Golden name, +25% coins and the VIP badge." },
	} :: { Pass },
	PRODUCTS = {
		{ key = "Boost30", id = 0, name = "2x Coins, 30 min", price = 79, desc = "A double-coins boost for half an hour.", boostMinutes = 30 },
		{ key = "CoinsS", id = 0, name = "Coin Pack S", price = 49, desc = "30 minutes of your income, right now.", incomeMinutes = 30 },
		{ key = "CoinsM", id = 0, name = "Coin Pack M", price = 99, desc = "90 minutes of your income, right now.", incomeMinutes = 90 },
		{ key = "CoinsL", id = 0, name = "Coin Pack L", price = 249, desc = "4 hours of your income, right now.", incomeMinutes = 240 },
	} :: { Product },
}
