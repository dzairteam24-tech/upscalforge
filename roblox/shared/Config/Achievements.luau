--!strict
-- Achievements (tiered goals with gems and titles) and Rank (permanent perks from achievement stars).
-- Every completed tier gives 1 star; every 3 stars is one Rank.

export type Achievement = {
	id: string,
	name: string,
	icon: string,
	text: string, -- "{goal}" is replaced with the tier's goal
	stat: string, -- see Logic/Achievements.value
	goals: { number },
	gems: { number }, -- one per tier
	titles: { [number]: string }?, -- tier -> title id
}

export type RankPerk = {
	rank: number,
	text: string,
	storage: number?,
	tripSlots: number?,
	cartridgeSlots: number?,
	title: string?,
	ride: string?,
	gems: number?,
}

local list: { Achievement } = {
	{
		id = "Hatcher",
		name = "Egg Cracker",
		icon = "🥚",
		text = "Hatch {goal} eggs",
		stat = "hatches",
		goals = { 50, 500, 5000, 50000 },
		gems = { 10, 30, 100, 300 },
		titles = { [4] = "A_EggMaster" },
	},
	{
		id = "Coins",
		name = "Coin Collector",
		icon = "🪙",
		text = "Collect {goal} coins",
		stat = "coinsEarned",
		goals = { 10000, 1e6, 1e8, 1e10 },
		gems = { 10, 30, 100, 300 },
		titles = { [4] = "A_Rich" },
	},
	{
		id = "Breaker",
		name = "Block Breaker",
		icon = "💥",
		text = "Break {goal} coin sources",
		stat = "breaks",
		goals = { 500, 5000, 50000 },
		gems = { 10, 40, 150 },
	},
	{
		id = "Golden",
		name = "Golden Touch",
		icon = "🟨",
		text = "Hatch {goal} Golden creatures",
		stat = "goldens",
		goals = { 1, 25, 250 },
		gems = { 10, 40, 150 },
	},
	{
		id = "Pixel",
		name = "Pixel Hunter",
		icon = "🟪",
		text = "Hatch {goal} Pixel creatures",
		stat = "pixels",
		goals = { 1, 10, 100 },
		gems = { 50, 150, 500 },
		titles = { [2] = "A_PixelHunter" },
	},
	{
		id = "BigCatch",
		name = "Big Game",
		icon = "🟠",
		text = "Catch {goal} Bigs",
		stat = "bigsCaught",
		goals = { 1, 10, 50 },
		gems = { 20, 60, 200 },
	},
	{
		id = "Titan",
		name = "Titan Whisperer",
		icon = "👑",
		text = "Get {goal} Titan",
		stat = "titans",
		goals = { 1, 5 },
		gems = { 500, 2000 },
		titles = { [1] = "A_Whisperer" },
	},
	{
		id = "Guardian",
		name = "Guardian Breaker",
		icon = "🛡️",
		text = "Defeat {goal} zone guardians",
		stat = "guardians",
		goals = { 1, 10, 50 },
		gems = { 20, 60, 200 },
	},
	{
		id = "Fusion",
		name = "Fusion Lab",
		icon = "⚗️",
		text = "Fuse {goal} times",
		stat = "fusions",
		goals = { 1, 25, 250 },
		gems = { 10, 40, 150 },
	},
	{
		id = "Explorer",
		name = "Explorer",
		icon = "🗺️",
		text = "Unlock zone {goal}",
		stat = "bestZone",
		goals = { 3, 6, 10 },
		gems = { 15, 40, 100 },
	},
	{
		id = "Restorer",
		name = "Restorer",
		icon = "🌈",
		text = "Restore {goal} zones to 100%",
		stat = "restores",
		goals = { 1, 5, 20 },
		gems = { 20, 60, 200 },
	},
	{
		id = "Combo",
		name = "Combo King",
		icon = "🔥",
		text = "Reach a {goal} combo",
		stat = "bestCombo",
		goals = { 25, 50, 100 },
		gems = { 10, 40, 150 },
	},
	{
		id = "Traveller",
		name = "Traveller",
		icon = "🧭",
		text = "Send creatures on {goal} trips",
		stat = "trips",
		goals = { 1, 25, 100 },
		gems = { 10, 40, 150 },
	},
	{
		id = "Reload",
		name = "Reloaded",
		icon = "🔄",
		text = "Reload {goal} times",
		stat = "reloads",
		goals = { 1, 3, 10 },
		gems = { 50, 150, 500 },
		titles = { [1] = "A_Reloaded" },
	},
	{
		id = "Loyal",
		name = "Loyal",
		icon = "📅",
		text = "Reach a {goal}-day login streak",
		stat = "bestStreak",
		goals = { 3, 7, 30 },
		gems = { 10, 40, 300 },
		titles = { [3] = "A_Loyal" },
	},
	{
		id = "Trader",
		name = "Trader",
		icon = "🔁",
		text = "Finish {goal} trades",
		stat = "trades",
		goals = { 1, 10, 100 },
		gems = { 10, 40, 150 },
	},
	{
		id = "Collector",
		name = "Collector",
		icon = "📖",
		text = "Discover {goal} creatures (species x variant)",
		stat = "discovered",
		goals = { 10, 40, 100, 240 },
		gems = { 10, 40, 150, 1000 },
		titles = { [4] = "A_Collector" },
	},
}

local byId: { [string]: Achievement } = {}
for _, achievement in list do
	byId[achievement.id] = achievement
end

-- Permanent perks. Each one applies from its rank on.
local rankPerks: { RankPerk } = {
	{ rank = 2, text = "Storage +25", storage = 25 },
	{ rank = 3, text = "+1 trip slot", tripSlots = 1 },
	{ rank = 4, text = "Title: Explorer", title = "R_Explorer" },
	{ rank = 5, text = "Storage +50", storage = 50 },
	{ rank = 6, text = "+1 Boost Card slot", cartridgeSlots = 1 },
	{ rank = 7, text = "Ride: Skateboard", ride = "Skateboard" },
	{ rank = 8, text = "+1 trip slot", tripSlots = 1 },
	{ rank = 10, text = "Storage +100 and title: Veteran", storage = 100, title = "R_Veteran" },
	{ rank = 12, text = "+1 Boost Card slot", cartridgeSlots = 1 },
	{ rank = 15, text = "Title: Cube Legend", title = "R_Legend" },
}

return {
	list = list,
	byId = byId,
	rankPerks = rankPerks,
	STARS_PER_RANK = 3,
}
