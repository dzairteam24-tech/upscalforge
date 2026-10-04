--!strict
-- Item counts in player data, plus elixir merge and mix rules.

local Items = require(script.Parent.Parent.Config.Items)

local Bag = {}

export type ItemMap = { [string]: number }

function Bag.count(items: ItemMap, id: string): number
	return items[id] or 0
end

function Bag.add(items: ItemMap, id: string, amount: number)
	if amount <= 0 or not Items.byId[id] then
		return
	end
	items[id] = (items[id] or 0) + amount
end

function Bag.take(items: ItemMap, id: string, amount: number): boolean
	local have = items[id] or 0
	if amount <= 0 or have < amount then
		return false
	end
	local left = have - amount
	if left > 0 then
		items[id] = left
	else
		(items :: any)[id] = nil
	end
	return true
end

-- Elixirs and cartridges: 3 of a tier -> 1 of the next tier. Key halves: 2 -> 1 key.
-- Returns the new item id.
function Bag.merge(items: ItemMap, id: string): (string?, string?)
	local item = Items.byId[id]
	local nextId = Items.nextTier(id)
	if not item or not nextId then
		return nil, "This can't be merged"
	end
	if not Bag.take(items, id, item.mergeCost) then
		return nil, ("You need %d of these"):format(item.mergeCost)
	end
	Bag.add(items, nextId, 1)
	return nextId, nil
end

-- Two different elixirs of the same tier -> one double elixir.
function Bag.mix(items: ItemMap, a: string, b: string): (string?, string?)
	if a == b then
		return nil, "Pick two different elixirs"
	end
	local result = Items.mixResult(a, b)
	if not result then
		return nil, "These two don't mix"
	end
	if Bag.count(items, a) < 1 or Bag.count(items, b) < 1 then
		return nil, "You don't have both elixirs"
	end
	Bag.take(items, a, 1)
	Bag.take(items, b, 1)
	Bag.add(items, result, 1)
	return result, nil
end

return Bag
