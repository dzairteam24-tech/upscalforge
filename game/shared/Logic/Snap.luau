--!strict
-- Cube Snap (Config/Snap): which creatures can snap together, what they make, and a creature's full name.

local Mutations = require(script.Parent.Parent.Config.Mutations)
local SnapConfig = require(script.Parent.Parent.Config.Snap)

local Snap = {}

export type Creature = { s: string, m: string, g: string? }

-- What a creature of this grade snaps into, if anything
function Snap.next(grade: string?): SnapConfig.Grade?
	for _, candidate in SnapConfig.LIST do
		if candidate.from == (grade or "") then
			return candidate
		end
	end
	return nil
end

-- Whether two creatures can snap together
local function matches(a: Creature, b: Creature): boolean
	if a.s ~= b.s or (a.g or "") ~= (b.g or "") then
		return false
	end
	-- Plain ones need the same mutation too; Megas can be any
	return a.g ~= nil or a.m == b.m
end

-- The creatures that would snap with `id` (it first, then those not in the garden before those in it), and the
-- creature they'd make; nil when there aren't enough
function Snap.find(creatures: { [string]: Creature }, placed: { string }, id: string): ({ string }?, Creature?)
	local first = creatures[id]
	local grade = first and Snap.next(first.g)
	if not first or not grade then
		return nil, nil
	end
	local loose, inGarden = {}, {}
	for other, creature in creatures do
		if other ~= id and matches(first, creature) then
			table.insert(if table.find(placed, other) then inGarden else loose, other)
		end
	end
	table.sort(loose)
	table.sort(inGarden)
	local group = { id }
	for _, list in { loose, inGarden } do
		for _, other in list do
			if #group < SnapConfig.NEED then
				table.insert(group, other)
			end
		end
	end
	if #group < SnapConfig.NEED then
		return nil, nil
	end
	-- The best mutation of the group
	local best = first.m
	for _, other in group do
		local m = creatures[other].m
		if (Mutations.byId[m] or Mutations.byId.Normal).order > (Mutations.byId[best] or Mutations.byId.Normal).order then
			best = m
		end
	end
	return group, { s = first.s, m = best, g = grade.id }
end

-- "Mega Golden Cubby", "Rainbow Neon Bear", "Cubby"...
function Snap.name(creature: Creature): string
	local parts = {}
	if creature.g then
		table.insert(parts, creature.g)
	end
	if creature.m ~= "Normal" then
		table.insert(parts, creature.m)
	end
	table.insert(parts, creature.s)
	return table.concat(parts, " ")
end

return Snap
