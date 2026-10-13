--!strict
-- A player's gems and what they can do with them: pick one up (if the backpack has room), sell them all, and
-- the small picture of them the client shows. Works on the saved data's `items` table.

local Gear = require(script.Parent.Parent.Config.Gear)
local Gem = require(script.Parent.Gem)

type Item = Gem.Item
type Holder = { items: { [string]: Item }, nextId: number, pack: number, coins: number, found: { [string]: boolean }, stats: { dug: number, sold: number, earned: number } }

local Backpack = {}

function Backpack.capacity(data: Holder): number
	local pack = Gear.PACKS[data.pack] or Gear.PACKS[1]
	return pack.slots
end

function Backpack.used(data: Holder): number
	local total = 0
	for _, item in data.items do
		total += Gem.slots(item)
	end
	return total
end

function Backpack.fits(data: Holder, item: Item): boolean
	return Backpack.used(data) + Gem.slots(item) <= Backpack.capacity(data)
end

-- Whether all of these gems fit together
function Backpack.fitsAll(data: Holder, items: { Item }): boolean
	local slots = 0
	for _, item in items do
		slots += Gem.slots(item)
	end
	return Backpack.used(data) + slots <= Backpack.capacity(data)
end

-- Adds a gem; false if it doesn't fit
function Backpack.add(data: Holder, item: Item): boolean
	if not Backpack.fits(data, item) then
		return false
	end
	data.items[tostring(data.nextId)] = item
	data.nextId += 1
	data.found[item.g] = true
	return true
end

-- Sells every gem at `multiplier` times its value (Logic/Multiplier): how many and how many coins
function Backpack.sellAll(data: Holder, multiplier: number?): (number, number)
	local count, base = 0, 0
	for id, item in data.items do
		base += Gem.value(item)
		count += 1
		data.items[id] = nil
	end
	local coins = math.floor(base * (multiplier or 1) + 0.5)
	data.coins += coins
	data.stats.sold += count
	data.stats.earned += coins
	return count, coins
end

-- The backpack as the client sees it: the gems grouped (key, how many), the rarest value first
function Backpack.groups(data: Holder): { { key: string, count: number, value: number } }
	local counts: { [string]: number } = {}
	for _, item in data.items do
		local key = Gem.key(item)
		counts[key] = (counts[key] or 0) + 1
	end
	local list = {}
	for key, count in counts do
		table.insert(list, { key = key, count = count, value = Gem.value(Gem.parseKey(key)) })
	end
	table.sort(list, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.key < b.key
	end)
	return list
end

return Backpack
