--!strict
-- First clears: the first time you beat each zone guardian, and the World Boss, you get a bonus that
-- lasts forever (Reload keeps it). Repeat fights give their normal rewards.

return {
	GUARDIAN_COINS = 0.05, -- +5% coins forever per zone guardian (all 10 = +50%)
	GUARDIAN_GEMS = 100, -- one time, x zone id
	BOSS_LUCK = 0.1, -- first World Boss win (full reward): Luck +10% forever
	BOSS_GEMS = 500, -- one time
}
