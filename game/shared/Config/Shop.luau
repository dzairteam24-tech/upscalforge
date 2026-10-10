--!strict
-- The Egg Shop's stock: it restocks every few minutes, the same in every server (Logic/Stock). Each egg is in
-- stock with a chance, and then with a few to buy (each player can buy that many).

return {
	RESTOCK = 300, -- seconds
	-- Per egg tier: the chance it's in stock, and how many at most
	STOCK = {
		[1] = { chance = 1, most = 6 },
		[2] = { chance = 1, most = 5 },
		[3] = { chance = 0.85, most = 4 },
		[4] = { chance = 0.75, most = 4 },
		[5] = { chance = 0.6, most = 3 },
		[6] = { chance = 0.5, most = 3 },
		[7] = { chance = 0.4, most = 2 },
		[8] = { chance = 0.3, most = 2 },
		[9] = { chance = 0.2, most = 2 },
		[10] = { chance = 0.12, most = 1 },
		[11] = { chance = 0.05, most = 1 },
	} :: { [number]: { chance: number, most: number } },
}
