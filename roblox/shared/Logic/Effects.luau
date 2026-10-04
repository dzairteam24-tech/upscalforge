--!strict
-- Collects the passive and periodic skills of equipped Big and Titan creatures.
-- Rule from the design: the same skill type from several pets does not stack, the strongest one counts.

local Config = script.Parent.Parent.Config
local World1 = require(Config.World1)
local Types = require(script.Parent.Types)

type Pet = Types.Pet

-- Types whose neutral value is 0 (additive chances or counts). Everything else is a multiplier (neutral 1).
local ADDITIVE = {
	Gem = true,
	FreeHatch = true,
	EggExtra = true,
	ComboHold = true,
	GoldenSources = true,
	InstantRespawn = true,
	CopyStrongest = true,
}

-- DoubleHit only affects the pet that owns it, so PetMath reads it per pet instead of team-wide.
local PER_PET = {
	DoubleHit = true,
}

export type PeriodicEntry = {
	key: string, -- unique per pet + skill index, used for timers
	petId: string,
	spec: World1.Periodic,
}

export type Effects = {
	values: { [string]: number },
	variantChance: { [string]: number },
	periodic: { PeriodicEntry },
}

local Effects = {}

function Effects.skillFor(pet: Pet): World1.Skill?
	local species = World1.species[pet.s]
	if not species then
		return nil
	end
	if pet.z == "Titan" then
		return species.titan
	elseif pet.z == "Big" then
		return species.big
	end
	return nil
end

function Effects.collect(pets: { [string]: Pet }, equipped: { string }): Effects
	local values: { [string]: number } = {}
	local variantChance: { [string]: number } = {}
	local periodic: { PeriodicEntry } = {}

	for _, petId in equipped do
		local pet = pets[petId]
		if not pet then
			continue
		end
		local skill = Effects.skillFor(pet)
		if not skill then
			continue
		end
		local p = skill.passive
		if p and not PER_PET[p.type] then
			if p.type == "VariantChance" and p.variant then
				variantChance[p.variant] = math.max(variantChance[p.variant] or 1, p.value)
			else
				local current = values[p.type]
				values[p.type] = if current then math.max(current, p.value) else p.value
			end
		end
		if skill.periodic then
			for index, spec in skill.periodic do
				table.insert(periodic, {
					key = petId .. ":" .. index,
					petId = petId,
					spec = spec,
				})
			end
		end
	end

	return {
		values = values,
		variantChance = variantChance,
		periodic = periodic,
	}
end

function Effects.get(effects: Effects, effectType: string): number
	local value = effects.values[effectType]
	if value ~= nil then
		return value
	end
	return if ADDITIVE[effectType] then 0 else 1
end

function Effects.empty(): Effects
	return { values = {}, variantChance = {}, periodic = {} }
end

return Effects
