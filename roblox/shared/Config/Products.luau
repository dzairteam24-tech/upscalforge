--!strict
-- Everything that earns money: Robux game passes, developer products, Roblox Premium perks and
-- rewarded video ads.
--
-- Rule: eggs, luck, creatures and currencies are never sold for Robux. We sell time, comfort and looks.
-- (Selling eggs would also make them "paid random items" under Roblox rules.)
--
-- Create the products in the Creator Dashboard and paste the IDs here. An ID of 0 shows "Soon".
-- `price` is only what the UI shows: keep it the same as the price set in the dashboard.
--
-- Rewarded video ads: Roblox grants an ad reward through a developer product (it arrives in
-- ProcessReceipt with PurchaseChannel = AdReward). Those products are `adOnly` and never sold.
-- Ads only show to players 13+ in some countries, and only once the game is ads-eligible, so every
-- ad reward that matters also has a Robux version.

export type GamePass = {
	key: string,
	id: number,
	price: number,
	name: string,
	description: string,
}

export type DevProduct = {
	key: string,
	id: number,
	price: number,
	name: string,
	description: string,
	adOnly: boolean?,
	reward: string?, -- handler key for rewards that need a service (trips, streak, quests...)
	boost: { stat: string, mult: number, seconds: number }?,
	inShop: boolean?, -- listed in the shop's Robux tab
	cosmetic: { kind: string, id: string }?, -- a look bought once and kept forever ("aura" or "hatchFx")
}

export type AdReward = {
	key: string, -- matches an adOnly DevProduct key
	label: string,
	reward: string?, -- handler key, shared with the Robux version
	boost: { stat: string, mult: number, seconds: number }?,
	freeEggs: number?,
	inShop: boolean?, -- listed in the shop's Free tab
	dailyLimit: number?, -- watches per UTC day
	cooldown: number?, -- seconds between watches
}

local gamePasses: { GamePass } = {
	{ key = "VIP", id = 0, price = 199, name = "VIP", description = "+1 team slot now (max stays 12), +4h offline earnings, VIP title" },
	{ key = "AutoTap", id = 0, price = 149, name = "Auto Tap", description = "You tap by yourself twice a second, forever" },
	{ key = "TeamSlots", id = 0, price = 299, name = "+2 Team Slots", description = "Two team slots right away, before you buy them with coins (max stays 12)" },
	{ key = "Storage", id = 0, price = 99, name = "Big Storage", description = "+500 creature storage" },
	{ key = "Teleport", id = 0, price = 79, name = "Teleport", description = "Jump to any zone you unlocked" },
	{ key = "TripSlot", id = 0, price = 149, name = "Extra Trip", description = "+1 trip slot (that trip brings back coins and gems)" },
}

local devProducts: { DevProduct } = {
	-- Cosmetic
	{ key = "SupporterTitle", id = 0, price = 49, name = "Supporter Title", description = "A golden 'Supporter' title above your head. Cosmetic only.", inShop = true },
	{ key = "PassPremium", id = 0, price = 399, name = "Battle Pass Premium", description = "Premium track of this season: titles, trails and rides. Cosmetic only." },
	{ key = "Aura_Sparkle", id = 0, price = 79, name = "Sparkle Aura", description = "Sparkles float around you. Everyone sees it. Cosmetic only.", inShop = true, cosmetic = { kind = "aura", id = "Sparkle" } },
	{ key = "Aura_Frost", id = 0, price = 79, name = "Frost Aura", description = "Ice sparkles float around you. Cosmetic only.", inShop = true, cosmetic = { kind = "aura", id = "Frost" } },
	{ key = "Aura_Flame", id = 0, price = 99, name = "Flame Aura", description = "You're on fire! Cosmetic only.", inShop = true, cosmetic = { kind = "aura", id = "Flame" } },
	{ key = "Aura_Toxic", id = 0, price = 99, name = "Toxic Aura", description = "Green flames around you. Cosmetic only.", inShop = true, cosmetic = { kind = "aura", id = "Toxic" } },
	{ key = "Aura_Pixel", id = 0, price = 129, name = "Pixel Aura", description = "Tiny glowing cubes orbit you. Cosmetic only.", inShop = true, cosmetic = { kind = "aura", id = "Pixel" } },
	{ key = "Aura_Galaxy", id = 0, price = 149, name = "Galaxy Aura", description = "A ring of stars around your feet. Cosmetic only.", inShop = true, cosmetic = { kind = "aura", id = "Galaxy" } },
	{ key = "Hatch_Confetti", id = 0, price = 79, name = "Confetti Hatch", description = "Your hatches burst with confetti. Same odds, just prettier.", inShop = true, cosmetic = { kind = "hatchFx", id = "Confetti" } },
	{ key = "Hatch_Gold", id = 0, price = 99, name = "Golden Hatch", description = "Golden rays behind every hatch. Same odds, just prettier.", inShop = true, cosmetic = { kind = "hatchFx", id = "Gold" } },
	{ key = "Hatch_Pixel", id = 0, price = 99, name = "Pixel Hatch", description = "Pixel confetti on every hatch. Same odds, just prettier.", inShop = true, cosmetic = { kind = "hatchFx", id = "Pixel" } },
	{ key = "Hatch_Galaxy", id = 0, price = 129, name = "Galaxy Hatch", description = "Galaxy rays behind every hatch. Same odds, just prettier.", inShop = true, cosmetic = { kind = "hatchFx", id = "Galaxy" } },
	-- Time and comfort (the Robux side of the ad rewards)
	{ key = "CoinBoost", id = 0, price = 49, name = "Coins x2 · 30 min", description = "Double coins for 30 minutes of play", boost = { stat = "Coins", mult = 2, seconds = 1800 }, inShop = true },
	{ key = "PowerBoost", id = 0, price = 49, name = "Power x2 · 30 min", description = "Double team power for 30 minutes of play", boost = { stat = "Power", mult = 2, seconds = 1800 }, inShop = true },
	{ key = "ServerBoost", id = 0, price = 149, name = "Server Boost", description = "Coins x2 for EVERYONE in the server for 15 minutes", reward = "ServerBoost", inShop = true },
	{ key = "TripSkip", id = 0, price = 25, name = "Finish a trip now", description = "Your creatures come back right away (coins and gems only)", reward = "TripSkip" },
	{ key = "TripDouble", id = 0, price = 35, name = "Double trip coins", description = "Claim a trip with its coins x2", reward = "TripDouble" },
	-- No Robux streak save: day 7 gives Luck elixirs, and luck is never sold. The ad version stays.
	{ key = "QuestSwap", id = 0, price = 10, name = "Swap a quest", description = "Get a different daily quest", reward = "QuestSwap" },
	-- Rewarded video ads (never sold)
	{ key = "AdCoins", id = 0, price = 0, name = "Ad: Coins x2", description = "", adOnly = true },
	{ key = "AdLuck", id = 0, price = 0, name = "Ad: Luck x2", description = "", adOnly = true },
	{ key = "AdPower", id = 0, price = 0, name = "Ad: Power x2", description = "", adOnly = true },
	{ key = "AdEggs", id = 0, price = 0, name = "Ad: 3 free eggs", description = "", adOnly = true },
	{ key = "AdElixir", id = 0, price = 0, name = "Ad: free elixir", description = "", adOnly = true },
	{ key = "AdTripSkip", id = 0, price = 0, name = "Ad: finish a trip now", description = "", adOnly = true },
	{ key = "AdTripDouble", id = 0, price = 0, name = "Ad: double trip rewards", description = "", adOnly = true },
	{ key = "AdStreak", id = 0, price = 0, name = "Ad: save the daily streak", description = "", adOnly = true },
	{ key = "AdReroll", id = 0, price = 0, name = "Ad: new quest", description = "", adOnly = true },
	{ key = "AdSpin", id = 0, price = 0, name = "Ad: Lucky Spin", description = "", adOnly = true },
}

local adRewards: { AdReward } = {
	{ key = "AdCoins", label = "Coins x2 · 30 min", boost = { stat = "Coins", mult = 2, seconds = 1800 }, inShop = true },
	{ key = "AdLuck", label = "Luck x2 · 15 min", boost = { stat = "Luck", mult = 2, seconds = 900 }, inShop = true },
	{ key = "AdPower", label = "Power x2 · 15 min", boost = { stat = "Power", mult = 2, seconds = 900 }, inShop = true },
	{ key = "AdEggs", label = "3 free eggs", freeEggs = 3, inShop = true },
	{ key = "AdElixir", label = "Free elixir (tier II–III)", reward = "Elixir", inShop = true, cooldown = 3600 },
	{ key = "AdTripSkip", label = "Finish a trip now", reward = "TripSkip", dailyLimit = 5 },
	{ key = "AdTripDouble", label = "Double a trip's rewards", reward = "TripDouble", dailyLimit = 10 },
	{ key = "AdStreak", label = "Save your daily streak", reward = "StreakSave", dailyLimit = 1 },
	{ key = "AdReroll", label = "Swap a daily quest", reward = "QuestSwap", dailyLimit = 3 },
	{ key = "AdSpin", label = "Lucky Spin", reward = "Spin", dailyLimit = 3 },
}

local passByKey: { [string]: GamePass } = {}
for _, pass in gamePasses do
	passByKey[pass.key] = pass
end

local productByKey: { [string]: DevProduct } = {}
local productById: { [number]: DevProduct } = {}
for _, product in devProducts do
	productByKey[product.key] = product
	if product.id ~= 0 then
		productById[product.id] = product
	end
end

local adByKey: { [string]: AdReward } = {}
for _, reward in adRewards do
	adByKey[reward.key] = reward
end

return {
	gamePasses = gamePasses,
	devProducts = devProducts,
	adRewards = adRewards,
	passByKey = passByKey,
	productByKey = productByKey,
	productById = productById,
	adByKey = adByKey,
	VIP_EXTRA_SLOTS = 1,
	VIP_EXTRA_OFFLINE_HOURS = 4,
	PASS_TEAM_SLOTS = 2,
	PASS_STORAGE = 500,
	PASS_TRIP_SLOTS = 1,
	PREMIUM_COINS = 1.1,
	SERVER_BOOST = { stat = "Coins", mult = 2, seconds = 900 },
}
