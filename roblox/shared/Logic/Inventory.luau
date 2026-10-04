--!strict
-- Creature inventory operations on player data. Pure functions: ids come from `newId`.

local Config = script.Parent.Parent.Config
local Variants = require(Config.Variants)
local PetMath = require(script.Parent.PetMath)
local Types = require(script.Parent.Types)

type Pet = Types.Pet
type PetMap = Types.PetMap

export type Holder = {
	pets: PetMap,
	equipped: { string },
}

local Inventory = {}

function Inventory.count(holder: Holder): number
	local n = 0
	for _ in holder.pets do
		n += 1
	end
	return n
end

function Inventory.isEquipped(holder: Holder, petId: string): boolean
	return table.find(holder.equipped, petId) ~= nil
end

function Inventory.add(holder: Holder, pet: Pet, newId: () -> string): string
	local id = newId()
	while holder.pets[id] do
		id = newId()
	end
	holder.pets[id] = { s = pet.s, v = pet.v, z = pet.z, lk = pet.lk }
	return id
end

function Inventory.unequip(holder: Holder, petId: string)
	local index = table.find(holder.equipped, petId)
	if index then
		table.remove(holder.equipped, index)
	end
end

function Inventory.remove(holder: Holder, petId: string): Pet?
	local pet = holder.pets[petId]
	if not pet then
		return nil
	end
	Inventory.unequip(holder, petId)
	holder.pets[petId] = nil
	return pet
end

function Inventory.equip(holder: Holder, petId: string, maxSlots: number): (boolean, string?)
	if not holder.pets[petId] then
		return false, "You don't own that creature"
	end
	if Inventory.isEquipped(holder, petId) then
		return true, nil
	end
	if #holder.equipped >= maxSlots then
		return false, "Your team is full"
	end
	table.insert(holder.equipped, petId)
	return true, nil
end

-- Drops equipped ids that no longer exist and trims to the slot count.
function Inventory.sanitize(holder: Holder, maxSlots: number)
	local seen: { [string]: boolean } = {}
	local clean = {}
	for _, petId in holder.equipped do
		if holder.pets[petId] and not seen[petId] and #clean < maxSlots then
			seen[petId] = true
			table.insert(clean, petId)
		end
	end
	holder.equipped = clean
end

function Inventory.equipBest(holder: Holder, maxSlots: number)
	local ids = {}
	for petId in holder.pets do
		table.insert(ids, petId)
	end
	local ranked = PetMath.rankIds(holder.pets, ids)
	local equipped = {}
	for i = 1, math.min(maxSlots, #ranked) do
		equipped[i] = ranked[i]
	end
	holder.equipped = equipped
end

function Inventory.setLocked(holder: Holder, petId: string, locked: boolean): boolean
	local pet = holder.pets[petId]
	if not pet then
		return false
	end
	pet.lk = if locked then true else nil
	return true
end

-- Ids of unlocked creatures that can be used as fusion material for this species + variant.
-- Unequipped ones come first so the team is touched last.
function Inventory.fusionMaterial(holder: Holder, speciesId: string, variantId: string): { string }
	local free, equipped = {}, {}
	for petId, pet in holder.pets do
		if pet.s == speciesId and pet.v == variantId and pet.z == "Normal" and not pet.lk then
			table.insert(if Inventory.isEquipped(holder, petId) then equipped else free, petId)
		end
	end
	table.sort(free)
	table.sort(equipped)
	for _, petId in equipped do
		table.insert(free, petId)
	end
	return free
end

-- Fuses `cost` creatures of the same species + variant into one of the next variant.
function Inventory.fuse(
	holder: Holder,
	speciesId: string,
	variantId: string,
	cost: number,
	newId: () -> string
): (string?, string?)
	local variant = Variants.byId[variantId]
	if not variant or not variant.fuseInto then
		return nil, "This variant can't be fused"
	end
	local material = Inventory.fusionMaterial(holder, speciesId, variantId)
	if #material < cost then
		return nil, string.format("You need %d unlocked %s %s", cost, variantId, speciesId)
	end
	for i = 1, cost do
		Inventory.remove(holder, material[i])
	end
	local id = Inventory.add(holder, { s = speciesId, v = variant.fuseInto, z = "Normal" }, newId)
	return id, nil
end

return Inventory
