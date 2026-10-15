--!strict
-- The rules of a farm, on its data: plant, harvest, buy seeds, sell from the barn, buy land. Pure functions, so
-- they are tested without the engine. Each returns what happened, or nil and why not.

local Config = script.Parent.Parent.Config
local Crops = require(Config.Crops)
local Growth = require(script.Parent.Growth)
local Land = require(script.Parent.Land)
local Level = require(script.Parent.Level)

export type Planted = { c: string, t: number } -- the crop, and when it was planted
export type Data = {
	coins: number,
	xp: number,
	lots: { [string]: boolean }, -- the lots of land they have ("cx,cz", Logic/Land)
	plots: { [string]: Planted }, -- what grows where (by tile, "x,z")
	seeds: { [string]: number },
	barn: { [string]: number }, -- harvested, waiting to be sold
	stats: { planted: number, harvested: number, sold: number, earned: number },
}

local Farm = {}

function Farm.level(data: Data): number
	return (Level.of(data.xp))
end

-- Whether they may plant a crop yet
function Farm.unlocked(data: Data, key: string): boolean
	local crop = Crops.byKey[key]
	return crop ~= nil and Farm.level(data) >= crop.level
end

local function validTile(data: Data, tile: any): boolean
	return Land.owns(data.lots, tile)
end

function Farm.plant(data: Data, tile: any, key: any, now: number): (boolean, string?)
	if not validTile(data, tile) then
		return false, "tile"
	end
	if type(key) ~= "string" or not Crops.byKey[key] then
		return false, "crop"
	end
	if data.plots[tile] then
		return false, "taken"
	end
	if (data.seeds[key] or 0) <= 0 then
		return false, "seeds"
	end
	data.seeds[key] -= 1
	if data.seeds[key] <= 0 then
		data.seeds[key] = nil
	end
	data.plots[tile] = { c = key, t = now }
	data.stats.planted += 1
	return true, nil
end

-- Harvests a ready crop into the barn. Returns the crop, how many, the XP, and whether that was a level up
function Farm.harvest(data: Data, tile: any, now: number): (Crops.Crop?, number, number, boolean)
	if not validTile(data, tile) then
		return nil, 0, 0, false
	end
	local planted = data.plots[tile]
	if not planted then
		return nil, 0, 0, false
	end
	local crop = Crops.byKey[planted.c]
	if not crop or not Growth.ready(planted.t, crop.grow, now) then
		return nil, 0, 0, false
	end
	data.plots[tile] = nil
	data.barn[crop.key] = (data.barn[crop.key] or 0) + crop.yield
	local before = Farm.level(data)
	data.xp += crop.xp
	data.stats.harvested += crop.yield
	return crop, crop.yield, crop.xp, Farm.level(data) > before
end

function Farm.buySeeds(data: Data, key: any, amount: any): (boolean, string?)
	if type(key) ~= "string" or not Crops.byKey[key] then
		return false, "crop"
	end
	if type(amount) ~= "number" or amount ~= math.floor(amount) or amount < 1 or amount > 99 then
		return false, "amount"
	end
	if not Farm.unlocked(data, key) then
		return false, "level"
	end
	local cost = Crops.byKey[key].seed * amount
	if data.coins < cost then
		return false, "coins"
	end
	data.coins -= cost
	data.seeds[key] = (data.seeds[key] or 0) + amount
	return true, nil
end

-- Sells one kind from the barn (or everything with "all"). Returns the coins
function Farm.sell(data: Data, key: any): number
	local coins = 0
	for k, count in data.barn do
		if (key == "all" or key == k) and count > 0 then
			local crop = Crops.byKey[k]
			if crop then
				coins += crop.sell * count
				data.stats.sold += count
			end
			data.barn[k] = nil
		end
	end
	data.coins += coins
	data.stats.earned += coins
	return coins
end

-- Buys the lot cx, cz (next to land they have)
function Farm.expand(data: Data, cx: any, cz: any): (boolean, string?)
	if type(cx) ~= "number" or type(cz) ~= "number" or cx ~= math.floor(cx) or cz ~= math.floor(cz) then
		return false, "lot"
	end
	if not Land.buyable(data.lots, cx, cz) then
		return false, "Buy land next to yours"
	end
	local cost = Land.cost(Land.count(data.lots))
	if data.coins < cost then
		return false, "Not enough coins yet"
	end
	data.coins -= cost
	data.lots[Land.key(cx, cz)] = true
	return true, nil
end

-- How many tiles of land they have
function Farm.tiles(data: Data): number
	return Land.count(data.lots) * Land.LOT * Land.LOT
end

-- How many tiles are ready now
function Farm.readyCount(data: Data, now: number): number
	local n = 0
	for _, planted in data.plots do
		local crop = Crops.byKey[planted.c]
		if crop and Growth.ready(planted.t, crop.grow, now) then
			n += 1
		end
	end
	return n
end

return Farm
