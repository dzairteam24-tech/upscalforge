--!strict
-- Power = coins a creature collects per hit. Every creature hits once per second.

local Config = script.Parent.Parent.Config
local Constants = require(Config.Constants)
local Sizes = require(Config.Sizes)
local Variants = require(Config.Variants)
local World1 = require(Config.World1)
local Items = require(Config.Items)
local Effects = require(script.Parent.Effects)
local Types = require(script.Parent.Types)

type Pet = Types.Pet

export type Boosts = {
	Power: number?, -- temporary team power multiplier
	Element: number?, -- temporary element bonus
	CloneCount: number?, -- temporary clones of the strongest creature
}

local PetMath = {}

-- Power of one creature on neutral ground, including its own DoubleHit skill.
function PetMath.basePower(pet: Pet): number
	local species = World1.species[pet.s]
	local variant = Variants.byId[pet.v]
	local size = Sizes.byId[pet.z]
	if not species or not variant or not size then
		return 0
	end
	local power = species.power * variant.mult * size.mult
	local skill = Effects.skillFor(pet)
	if skill and skill.passive and skill.passive.type == "DoubleHit" then
		power *= skill.passive.value
	end
	local sticker = if pet.st then Items.byId[pet.st] else nil
	local effect = sticker and sticker.sticker
	if effect and effect.scope == "pet" and effect.stat == "Power" then
		power *= effect.value
	end
	return power
end

function PetMath.elementBonus(effects: Effects.Effects, boosts: Boosts?): number
	local bonus = Constants.ELEMENT_BONUS
	local fromSkill = effects.values.ElementBonus
	if fromSkill then
		bonus = math.max(bonus, fromSkill)
	end
	if boosts and boosts.Element then
		bonus = math.max(bonus, boosts.Element)
	end
	return bonus
end

function PetMath.petPower(pet: Pet, zoneElement: string, elementBonus: number): number
	local power = PetMath.basePower(pet)
	local variant = Variants.byId[pet.v]
	if variant and variant.strongIn == zoneElement then
		power *= elementBonus
	end
	return power
end

-- Total coins per second of the equipped team in a zone with the given element.
function PetMath.teamPower(
	pets: { [string]: Pet },
	equipped: { string },
	zoneElement: string,
	effects: Effects.Effects,
	boosts: Boosts?
): (number, number)
	local bonus = PetMath.elementBonus(effects, boosts)
	local powers: { number } = {}
	local strongest = 0
	for _, petId in equipped do
		local pet = pets[petId]
		if pet then
			local power = PetMath.petPower(pet, zoneElement, bonus)
			table.insert(powers, power)
			strongest = math.max(strongest, power)
		end
	end

	local copyStrongest = Effects.get(effects, "CopyStrongest") > 0
	local total = 0
	for _, power in powers do
		total += if copyStrongest then strongest else power
	end

	if boosts and boosts.CloneCount then
		total += boosts.CloneCount * strongest
	end

	total *= Effects.get(effects, "TeamPower")
	if zoneElement == "Dark" then
		total *= Effects.get(effects, "DarkPower")
	end
	if boosts and boosts.Power then
		total *= boosts.Power
	end
	return total, strongest
end

-- Sort helper: strongest first, ties broken by id for stable results.
function PetMath.rankIds(pets: { [string]: Pet }, ids: { string }): { string }
	local sorted = table.clone(ids)
	table.sort(sorted, function(a: string, b: string): boolean
		local pa, pb = PetMath.basePower(pets[a]), PetMath.basePower(pets[b])
		if pa == pb then
			return a < b
		end
		return pa > pb
	end)
	return sorted
end

return PetMath
