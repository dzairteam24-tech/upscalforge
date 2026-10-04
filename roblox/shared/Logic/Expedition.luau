--!strict
-- Expeditions: creatures that aren't on the team go on timed trips and come back with coins and items.
-- Pure logic so it can be tested; the server applies the rewards.

local Config = script.Parent.Parent.Config
local Expeditions = require(Config.Expeditions)
local Variants = require(Config.Variants)
local Achievements = require(script.Parent.Achievements)
local Loot = require(script.Parent.Loot)
local PetMath = require(script.Parent.PetMath)
local Types = require(script.Parent.Types)

type PlayerData = Types.PlayerData
type Pet = Types.Pet

export type Reward = {
	coins: number, -- raw coins, before the player's coin multipliers
	gems: number,
	tickets: number,
	items: { string },
}

local Expedition = {}

-- One more expedition slot every 2 Reloads, plus any Rank bonus.
function Expedition.slots(reloads: number, bonus: number?): number
	return math.min(Expeditions.MAX_SLOTS, Expeditions.BASE_SLOTS + math.floor(reloads / 2) + (bonus or 0))
end

function Expedition.slotsFor(data: PlayerData): number
	local _, perks = Achievements.forData(data)
	return Expedition.slots(data.reloads, perks.tripSlots)
end

-- True when every creature has the same variant and that variant is strong in some element (e.g. all Lava).
function Expedition.sharedElement(pets: { Pet }): boolean
	local first = pets[1]
	if not first then
		return false
	end
	local variant = Variants.byId[first.v]
	if not variant or not variant.strongIn then
		return false
	end
	for _, pet in pets do
		if pet.v ~= first.v then
			return false
		end
	end
	return true
end

function Expedition.validate(data: PlayerData, kindId: string, petIds: { string }): (boolean, string?)
	local kind = Expeditions.byId[kindId]
	if not kind then
		return false, "Unknown trip"
	end
	if #data.expeditions >= Expedition.slotsFor(data) then
		return false, "All trip slots are busy"
	end
	if #petIds ~= kind.pets then
		return false, ("This trip needs %d creatures"):format(kind.pets)
	end
	local seen: { [string]: boolean } = {}
	for _, petId in petIds do
		local pet = data.pets[petId]
		if not pet then
			return false, "You don't have that creature"
		end
		if seen[petId] then
			return false, "Each creature can only go once"
		end
		seen[petId] = true
		if pet.ex then
			return false, "That creature is already on a trip"
		end
		if table.find(data.equipped, petId) then
			return false, "Unequip a creature before sending it on a trip"
		end
	end
	return true, nil
end

-- Marks the creatures as away and stores the trip. Call `validate` first.
function Expedition.start(data: PlayerData, kindId: string, petIds: { string }, now: number): Types.Expedition
	local kind = Expeditions.byId[kindId]
	local pets: { Pet } = {}
	local power = 0
	for _, petId in petIds do
		local pet = data.pets[petId]
		pet.ex = true
		table.insert(pets, pet)
		power += PetMath.basePower(pet)
	end
	local trip: Types.Expedition = {
		kind = kindId,
		pets = table.clone(petIds),
		started = now,
		ends = now + kind.duration,
		power = power,
		element = Expedition.sharedElement(pets),
	}
	table.insert(data.expeditions, trip)
	return trip
end

-- What a finished trip brings back. `zoneId` is the player's best unlocked zone (scales gems and items).
function Expedition.rewards(trip: Types.Expedition, zoneId: number, rng: () -> number): Reward
	local kind = Expeditions.byId[trip.kind]
	local reward: Reward = { coins = 0, gems = 0, tickets = 0, items = {} }
	if not kind then
		return reward
	end
	local bonus = if trip.element then Expeditions.ELEMENT_BONUS else 1
	local tierBonus = Loot.zoneTierBonus(zoneId)

	reward.coins = trip.power * kind.duration * kind.coinFactor * bonus
	reward.gems = math.floor(kind.gemsPerZone * math.max(1, zoneId) * bonus)
	reward.tickets = math.floor(kind.tickets * bonus)
	for _ = 1, kind.elixirs do
		local maxTier = kind.elixirTiers[2] + tierBonus
		table.insert(reward.items, Loot.randomElixir(kind.elixirTiers[1], maxTier, rng))
	end
	if rng() < kind.cartridgeChance * bonus then
		table.insert(reward.items, Loot.randomCartridge(kind.cartridgeTiers[1], kind.cartridgeTiers[2], rng))
	end
	for _, half in kind.keyHalves do
		if rng() < half.chance * bonus then
			table.insert(reward.items, half.id)
		end
	end
	if rng() < kind.stickerChance * bonus then
		table.insert(reward.items, Loot.randomSticker(kind.stickerMaxTier, rng))
	end
	if rng() < kind.gadgetChance * bonus then
		table.insert(reward.items, Loot.randomGadget(rng))
	end
	return reward
end

-- Removes a finished trip and brings its creatures back. Returns the trip, or nil and a reason.
function Expedition.claim(data: PlayerData, index: number, now: number): (Types.Expedition?, string?)
	local trip = data.expeditions[index]
	if not trip then
		return nil, "That trip doesn't exist"
	end
	if now < trip.ends then
		return nil, "The creatures are still travelling"
	end
	table.remove(data.expeditions, index)
	for _, petId in trip.pets do
		local pet = data.pets[petId]
		if pet then
			pet.ex = nil
		end
	end
	return trip, nil
end

-- Clears `ex` from creatures that no trip refers to (old data, interrupted saves).
function Expedition.repair(data: PlayerData)
	local away: { [string]: boolean } = {}
	for _, trip in data.expeditions do
		for _, petId in trip.pets do
			away[petId] = true
		end
	end
	for petId, pet in data.pets do
		if pet.ex and not away[petId] then
			pet.ex = nil
		elseif away[petId] and not pet.ex then
			pet.ex = true
		end
	end
end

return Expedition
