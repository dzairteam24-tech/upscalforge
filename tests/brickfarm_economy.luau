-- Brick Farm's pacing: simulated players. One plays an hour straight; one plays two 15-minute sessions a day for
-- two weeks (crops grow while they're away). Both harvest, sell, buy land when they can, and plant the best crop
-- that will be ready by the time they look again. Run from the repo root:  lune run tests/brickfarm_economy.luau

local process = require("@lune/process")
local Loader = require("./loader")
local Shared = Loader.root("brickfarm/shared", "Shared")
local Crops = Loader.require(Shared.Config.Crops)
local Farm = Loader.require(Shared.Logic.Farm)
local Land = Loader.require(Shared.Logic.Land)
local Growth = Loader.require(Shared.Logic.Growth)

local passed, failed = 0, 0
local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (if detail then " (" .. detail .. ")" else ""))
	end
end

local START_SEEDS = 6 -- (a new farm gets this many carrot seeds; DataService)
local START_COINS = 20
local function newData(): any
	return { coins = START_COINS, xp = 0, tiles = Land.START, plots = {}, seeds = { carrot = START_SEEDS }, barn = {}, stats = { planted = 0, harvested = 0, sold = 0, earned = 0 } }
end

-- the best crop to plant now if they'll look again in `away` seconds: the most profit a second of the time
-- until they're back (a crop ready sooner just waits)
local function choose(data: any, away: number): any
	local best, bestScore = nil, -1
	for _, crop in Crops.LIST do
		if Farm.unlocked(data, crop.key) then
			local wait = math.max(crop.grow, away)
			local score = (crop.sell * crop.yield - crop.seed) / wait + crop.xp / wait * 2
			if score > bestScore and crop.seed <= data.coins + (data.seeds[crop.key] or 0) * crop.seed then
				best, bestScore = crop, score
			end
		end
	end
	return best
end

-- one look at the farm: harvest, sell, buy land, plant every empty tile
local function tend(data: any, now: number, away: number)
	for tile = 1, data.tiles do
		Farm.harvest(data, tile, now)
	end
	Farm.sell(data, "all")
	-- (land, but not with the money for seeds)
	local reserve = 0
	local crop = choose(data, away)
	if crop then
		reserve = crop.seed * data.tiles
	end
	while data.tiles < Land.MAX and data.coins - Land.cost(data.tiles + 1) >= reserve and Farm.expand(data) do
		reserve = if crop then crop.seed * data.tiles else 0
	end
	for tile = 1, data.tiles do
		if not data.plots[tostring(tile)] then
			local crop = choose(data, away)
			if not crop then
				break
			end
			if (data.seeds[crop.key] or 0) == 0 then
				if not Farm.buySeeds(data, crop.key, 1) then
					break
				end
			end
			Farm.plant(data, tile, crop.key, now)
		end
	end
end

-- an hour of play, looking at the farm every 5 seconds
do
	local data = newData()
	local firstSale, level2, level5 = nil, nil, nil
	for t = 0, 3600, 5 do
		tend(data, t, 5)
		if not firstSale and data.stats.earned > 0 then
			firstSale = t
		end
		local level = Farm.level(data)
		if not level2 and level >= 2 then
			level2 = t
		end
		if not level5 and level >= 5 then
			level5 = t
		end
	end
	print(string.format("an hour straight: first sale %ss, level 2 at %.1f min, level 5 at %s min, after an hour level %d, %d tiles, %d coins",
		tostring(firstSale), (level2 or 0) / 60, if level5 then string.format("%.1f", level5 / 60) else "never", Farm.level(data), data.tiles, data.coins))
	check("the first sale comes within a minute", firstSale ~= nil and firstSale <= 60, tostring(firstSale))
	check("level 2 within 3 minutes", level2 ~= nil and level2 <= 180, tostring(level2))
	check("level 5 in 15 to 45 minutes", level5 ~= nil and level5 >= 900 and level5 <= 2700, tostring(level5))
	check("more land within the hour", data.tiles > Land.START + 2)
	check("but nowhere near all of it", data.tiles < Land.MAX - 10, tostring(data.tiles))
end

-- two 15-minute sessions a day, for two weeks
do
	local data = newData()
	local day = 86400
	local log = {}
	for d = 0, 13 do
		for _, session in { 8 * 3600, 19 * 3600 } do
			local start = d * day + session
			for t = start, start + 900, 10 do
				local leaving = t + 10 > start + 900
				local away = if leaving then (if session == 8 * 3600 then 11 * 3600 - 900 else 13 * 3600 - 900) else 10
				tend(data, t, away)
			end
		end
		table.insert(log, string.format("day %d: level %d, %d tiles", d + 1, Farm.level(data), data.tiles))
	end
	print("two sessions a day: " .. log[1] .. " | " .. log[3] .. " | " .. log[7] .. " | " .. log[14])
	check("a week in: past level 10", Farm.level(data) >= 10, tostring(Farm.level(data)))
	check("two weeks in: still something to buy (land)", data.tiles < Land.MAX, tostring(data.tiles))
	check("two weeks in: the slowest crop is unlocked or nearly", Farm.level(data) >= Crops.LIST[#Crops.LIST].level - 4, tostring(Farm.level(data)))
	local _ = Growth
end

print(("%d passed, %d failed"):format(passed, failed))
process.exit(if failed > 0 then 1 else 0)
