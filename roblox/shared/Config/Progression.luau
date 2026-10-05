--!strict
-- Daily reward cycle, quest templates and the Battle Pass.
-- Coin rewards are written as "eggs": the price of the player's best unlocked egg, so they stay useful.

export type Reward = {
	coinsInEggs: number?,
	gems: number?,
	items: { { id: string, amount: number } }?,
	freeEggs: number?,
	freeEggLuck: number?,
	title: string?,
	trail: string?,
	ride: string?,
	tickets: number?,
	xp: number?,
}

export type QuestTemplate = {
	id: string,
	event: string, -- GameService.progress event
	text: string, -- {goal} is replaced
	goal: number,
	scaleWithEgg: boolean?, -- goal x best egg price (coin quests)
	max: boolean?, -- progress keeps the best value instead of adding (combo)
}


-- 7-day login cycle. Missing a day resets the streak to day 1.
local DAILY: { Reward } = {
	{ coinsInEggs = 10 },
	{ items = { { id = "Elixir_Coins_1", amount = 2 } } },
	{ gems = 50 },
	{ items = { { id = "Elixir_Luck_2", amount = 1 } } },
	{ coinsInEggs = 50 },
	{ gems = 100, items = { { id = "Elixir_Power_3", amount = 1 } } },
	{
		items = { { id = "Elixir_Pixel_2", amount = 1 }, { id = "Elixir_Luck_3", amount = 1 } },
		freeEggs = 3,
		freeEggLuck = 5,
	},
}

local DAILY_QUESTS = 3
local WEEKLY_QUESTS = 5
local DAILY_QUEST_REWARD: Reward = { xp = 100, coinsInEggs = 5, tickets = 1 }
local WEEKLY_QUEST_REWARD: Reward = { xp = 400, gems = 60, tickets = 5 }

local DAILY_TEMPLATES: { QuestTemplate } = {
	{ id = "d_coins", event = "Coins", text = "Collect {goal} coins", goal = 150, scaleWithEgg = true },
	{ id = "d_break", event = "Break", text = "Break {goal} coin sources", goal = 150 },
	{ id = "d_hatch", event = "Hatch", text = "Hatch {goal} eggs", goal = 30 },
	{ id = "d_combo", event = "Combo", text = "Reach a {goal} combo", goal = 20, max = true },
	{ id = "d_fuse", event = "Fuse", text = "Fuse {goal} times", goal = 2 },
	{ id = "d_big", event = "Big", text = "Defeat {goal} Big", goal = 1 },
	{ id = "d_rift", event = "Rift", text = "Break {goal} sources in the Pixel Rift", goal = 50 },
	{ id = "d_trip", event = "Expedition", text = "Send creatures on {goal} trip", goal = 1 },
}

local WEEKLY_TEMPLATES: { QuestTemplate } = {
	{ id = "w_coins", event = "Coins", text = "Collect {goal} coins", goal = 1500, scaleWithEgg = true },
	{ id = "w_break", event = "Break", text = "Break {goal} coin sources", goal = 1500 },
	{ id = "w_hatch", event = "Hatch", text = "Hatch {goal} eggs", goal = 300 },
	{ id = "w_big", event = "Big", text = "Defeat {goal} Bigs", goal = 5 },
	{ id = "w_guardian", event = "Guardian", text = "Defeat {goal} zone guardian", goal = 1 },
	{ id = "w_boss", event = "Boss", text = "Defeat {goal} World Bosses", goal = 3 },
	{ id = "w_restore", event = "Restore", text = "Fully restore {goal} zone", goal = 1 },
	{ id = "w_rift", event = "Rift", text = "Break {goal} sources in the Pixel Rift", goal = 500 },
	{ id = "w_trip", event = "Expedition", text = "Send creatures on {goal} trips", goal = 5 },
}

-- Battle Pass: 30-day seasons, 50 levels.
local PASS_LEVELS = 50
local PASS_XP_PER_LEVEL = 300
local SEASON_DAYS = 30
local SEASON_START_DAY = 20730 -- UTC day number of season 1's first day (2026-10-04)

-- Free track: something every level. Premium track: cosmetics every 5 levels (titles, trails and rides only).
local function passReward(level: number, premium: boolean): Reward?
	if premium then
		local cosmetics: { [number]: Reward } = {
			[5] = { title = "S1_Rookie" },
			[10] = { trail = "S1_Sky" },
			[15] = { title = "S1_Collector" },
			[20] = { trail = "S1_Lava", ride = "S1_Hoverboard" },
			[25] = { title = "S1_Hunter" },
			[30] = { trail = "S1_Neon" },
			[35] = { title = "S1_Tamer" },
			[40] = { trail = "S1_Pixel" },
			[45] = { title = "S1_Pixel" },
			[50] = { title = "S1_Champion", trail = "S1_Rainbow", ride = "S1_Cloud" },
		}
		return cosmetics[level]
	end
	local tier = math.clamp(1 + level // 12, 1, 5)
	local cycle = level % 5
	if level % 10 == 0 then
		return { gems = 25 * level, items = { { id = ("Elixir_Luck_%d"):format(tier), amount = 1 } } }
	elseif cycle == 1 then
		return { coinsInEggs = 5 + level }
	elseif cycle == 2 then
		return { items = { { id = ("Elixir_Coins_%d"):format(tier), amount = 1 } } }
	elseif cycle == 3 then
		return { gems = 10 + level * 2 }
	elseif cycle == 4 then
		return { items = { { id = ("Elixir_Power_%d"):format(tier), amount = 1 } } }
	end
	return { freeEggs = 2, freeEggLuck = 2 }
end

-- Playtime gifts: one every 15 minutes played today, bigger as the day goes on.
local GIFT_SECONDS = 15 * 60
local PLAYTIME_GIFTS: { Reward } = {
	{ coinsInEggs = 2 },
	{ items = { { id = "Elixir_Luck_2", amount = 1 } } },
	{ gems = 20 },
	{ coinsInEggs = 4, items = { { id = "KeyHalf_Zone", amount = 1 } } },
	{ freeEggs = 3, freeEggLuck = 1.5 },
	{ tickets = 3, items = { { id = "Elixir_Fortune_2", amount = 1 } } },
	{ gems = 50, items = { { id = "KeyHalf_Golden", amount = 1 } } },
	{ coinsInEggs = 10, items = { { id = "Cart_Coins_2", amount = 1 } } },
}

-- An ad can save a broken daily streak if at most this many days were missed.
local STREAK_SAVE_DAYS = 3

-- Pixel Rift: today's zone gets coins x1.5 and Pixel chance x3.
local RIFT_COINS = 1.5
local RIFT_PIXEL_CHANCE = 3

return {
	DAILY = DAILY,
	DAILY_QUESTS = DAILY_QUESTS,
	WEEKLY_QUESTS = WEEKLY_QUESTS,
	DAILY_QUEST_REWARD = DAILY_QUEST_REWARD,
	WEEKLY_QUEST_REWARD = WEEKLY_QUEST_REWARD,
	DAILY_TEMPLATES = DAILY_TEMPLATES,
	WEEKLY_TEMPLATES = WEEKLY_TEMPLATES,
	PASS_LEVELS = PASS_LEVELS,
	PASS_XP_PER_LEVEL = PASS_XP_PER_LEVEL,
	SEASON_DAYS = SEASON_DAYS,
	SEASON_START_DAY = SEASON_START_DAY,
	passReward = passReward,
	RIFT_COINS = RIFT_COINS,
	RIFT_PIXEL_CHANCE = RIFT_PIXEL_CHANCE,
	GIFT_SECONDS = GIFT_SECONDS,
	PLAYTIME_GIFTS = PLAYTIME_GIFTS,
	STREAK_SAVE_DAYS = STREAK_SAVE_DAYS,
}
