--!strict
-- Equipped cartridges: their bonuses and set bonuses. One cartridge per family.

local Items = require(script.Parent.Parent.Config.Items)
local Bag = require(script.Parent.Bag)

export type Gear = {
	values: { [string]: number },
	sets: { string }, -- completed sets
	fighter: boolean, -- Fighter set: periodic power burst
}

local ADDITIVE = {
	Jackpot = true,
	ComboHold = true,
	GoldenSources = true,
	AutoTap = true,
	EggExtraChance = true,
	OfflineHours = true,
}

local Gear = {
	BASE_SLOTS = 2,
	MAX_SLOTS = 6,
	FIGHTER_EVERY = 20,
	FIGHTER_DURATION = 5,
	FIGHTER_MULT = 2,
	LOADOUTS = 3,
}

-- Slots from Reloads plus any Rank bonus, up to 6.
function Gear.slots(reloads: number, bonus: number?): number
	return math.min(Gear.MAX_SLOTS, Gear.BASE_SLOTS + reloads + (bonus or 0))
end

function Gear.empty(): Gear
	return { values = {}, sets = {}, fighter = false }
end

function Gear.compute(equipped: { string }): Gear
	local values: { [string]: number } = {}
	local families: { [string]: boolean } = {}
	for _, id in equipped do
		local item = Items.byId[id]
		if item and item.kind == "Cartridge" then
			families[item.family] = true
			for _, effect in item.gear do
				if ADDITIVE[effect.stat] then
					values[effect.stat] = (values[effect.stat] or 0) + effect.value
				else
					values[effect.stat] = (values[effect.stat] or 1) * effect.value
				end
			end
		end
	end

	local sets: { string } = {}
	local fighter = false
	for setId, set in Items.sets do
		local complete = true
		for _, member in set.members do
			if not families[member] then
				complete = false
				break
			end
		end
		if complete then
			table.insert(sets, setId)
			if setId == "Rich" then
				values.Coins = (values.Coins or 1) * 1.25
			elseif setId == "Hatcher" then
				values.HatchSpeed = 2
			elseif setId == "Fighter" then
				fighter = true
			elseif setId == "Idle" then
				values.OfflineHours = (values.OfflineHours or 0) + 4
			end
		end
	end
	table.sort(sets)
	return { values = values, sets = sets, fighter = fighter }
end

function Gear.get(gear: Gear, stat: string): number
	local value = gear.values[stat]
	if value ~= nil then
		return value
	end
	return if ADDITIVE[stat] then 0 else 1
end

-- Checks whether a cartridge can go in: free slot and no other cartridge of the same family.
function Gear.canEquip(equipped: { string }, id: string, slots: number): (boolean, string?)
	local item = Items.byId[id]
	if not item or item.kind ~= "Cartridge" then
		return false, "That's not a Boost Card"
	end
	if #equipped >= slots then
		return false, "All card slots are full"
	end
	for _, other in equipped do
		local otherItem = Items.byId[other]
		if otherItem and otherItem.family == item.family then
			return false, "You already have a " .. item.family .. " card in"
		end
	end
	return true, nil
end

-- Loadouts: swaps the equipped cards for a saved set in one tap. Every equipped card goes back to the bag,
-- then each saved card is taken out again if it's still there and fits. Returns the cards that were missing.
function Gear.applyLoadout(items: { [string]: number }, equipped: { string }, wanted: { string }, slots: number): { string }
	for _, id in equipped do
		Bag.add(items, id, 1)
	end
	table.clear(equipped)
	local missing = {}
	for _, id in wanted do
		if Bag.count(items, id) > 0 and Gear.canEquip(equipped, id, slots) then
			Bag.take(items, id, 1)
			table.insert(equipped, id)
		else
			table.insert(missing, id)
		end
	end
	return missing
end

return Gear
