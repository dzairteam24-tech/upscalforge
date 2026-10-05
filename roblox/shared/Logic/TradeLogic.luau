--!strict
-- Trade session state machine. Safety rules from the player research:
--   * any change to an offer resets both "ready" flags and locks the Ready button for TRADE_LOCK_SECONDS
--   * after both are ready, a separate confirm step shows exactly what each side gives and gets
--   * the server re-validates ownership, locks and storage right before swapping

local Config = script.Parent.Parent.Config
local Constants = require(Config.Constants)
local Sizes = require(Config.Sizes)
local Variants = require(Config.Variants)
local Inventory = require(script.Parent.Inventory)
local Types = require(script.Parent.Types)

type PetMap = Types.PetMap

export type Session = {
	a: number,
	b: number,
	offers: { [number]: { string } },
	ready: { [number]: boolean },
	confirmed: { [number]: boolean },
	stage: string, -- "Offer" | "Confirm" | "Done" | "Cancelled"
	lockUntil: number,
	version: number,
}

export type Side = {
	pets: PetMap,
	equipped: { string },
	capacity: number,
	index: { [string]: boolean }?, -- the receiver's creature index
}

local TradeLogic = {}

function TradeLogic.new(a: number, b: number, now: number): Session
	return {
		a = a,
		b = b,
		offers = { [a] = {}, [b] = {} },
		ready = { [a] = false, [b] = false },
		confirmed = { [a] = false, [b] = false },
		stage = "Offer",
		lockUntil = now,
		version = 0,
	}
end

function TradeLogic.other(session: Session, userId: number): number
	return if userId == session.a then session.b else session.a
end

function TradeLogic.isMember(session: Session, userId: number): boolean
	return userId == session.a or userId == session.b
end

local function resetAgreement(session: Session, now: number)
	session.ready[session.a] = false
	session.ready[session.b] = false
	session.confirmed[session.a] = false
	session.confirmed[session.b] = false
	session.stage = "Offer"
	session.lockUntil = now + Constants.TRADE_LOCK_SECONDS
	session.version += 1
end

function TradeLogic.setOffer(session: Session, userId: number, petIds: { string }, now: number): (boolean, string?)
	if not TradeLogic.isMember(session, userId) then
		return false, "Not in this trade"
	end
	if session.stage ~= "Offer" and session.stage ~= "Confirm" then
		return false, "Trade is over"
	end
	local unique: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, petId in petIds do
		if type(petId) == "string" and not seen[petId] then
			seen[petId] = true
			table.insert(unique, petId)
		end
	end
	if #unique > Constants.TRADE_MAX_PETS then
		return false, "You can offer up to " .. Constants.TRADE_MAX_PETS .. " creatures"
	end
	session.offers[userId] = unique
	resetAgreement(session, now)
	return true, nil
end

function TradeLogic.setReady(session: Session, userId: number, now: number): (boolean, string?)
	if not TradeLogic.isMember(session, userId) then
		return false, "Not in this trade"
	end
	if session.stage ~= "Offer" then
		return false, "Not in the offer step"
	end
	if now < session.lockUntil then
		return false, "Wait for the countdown"
	end
	if #session.offers[session.a] + #session.offers[session.b] == 0 then
		return false, "Nothing to trade"
	end
	session.ready[userId] = true
	if session.ready[session.a] and session.ready[session.b] then
		session.stage = "Confirm"
	end
	session.version += 1
	return true, nil
end

-- Returns true when both players confirmed and the swap should run.
function TradeLogic.confirm(session: Session, userId: number): (boolean, string?)
	if not TradeLogic.isMember(session, userId) then
		return false, "Not in this trade"
	end
	if session.stage ~= "Confirm" then
		return false, "Both players must be ready first"
	end
	session.confirmed[userId] = true
	session.version += 1
	return session.confirmed[session.a] and session.confirmed[session.b], nil
end

function TradeLogic.validate(session: Session, sideA: Side, sideB: Side): (boolean, string?)
	local offerA, offerB = session.offers[session.a], session.offers[session.b]
	local function checkOffer(offer: { string }, side: Side): (boolean, string?)
		for _, petId in offer do
			local pet = side.pets[petId]
			if not pet then
				return false, "A creature in the trade is gone"
			end
			if pet.lk then
				return false, "Locked creatures can't be traded"
			end
			if pet.ex then
				return false, "Creatures on an expedition can't be traded"
			end
		end
		return true, nil
	end
	local okA, errA = checkOffer(offerA, sideA)
	if not okA then
		return false, errA
	end
	local okB, errB = checkOffer(offerB, sideB)
	if not okB then
		return false, errB
	end
	local countA = Inventory.count(sideA)
	local countB = Inventory.count(sideB)
	if countA - #offerA + #offerB > sideA.capacity then
		return false, "Not enough storage"
	end
	if countB - #offerB + #offerA > sideB.capacity then
		return false, "Not enough storage"
	end
	return true, nil
end

-- Moves the creatures. Ids are kept (they are unique GUIDs). Call validate first.
function TradeLogic.execute(session: Session, sideA: Side, sideB: Side): ({ Types.Pet }, { Types.Pet })
	local movedA, movedB = {}, {}
	local fromA: { [string]: Types.Pet } = {}
	local fromB: { [string]: Types.Pet } = {}
	for _, petId in session.offers[session.a] do
		local pet = Inventory.remove(sideA, petId)
		if pet then
			fromA[petId] = pet
			table.insert(movedA, pet)
		end
	end
	for _, petId in session.offers[session.b] do
		local pet = Inventory.remove(sideB, petId)
		if pet then
			fromB[petId] = pet
			table.insert(movedB, pet)
		end
	end
	for petId, pet in fromA do
		sideB.pets[petId] = pet
		if sideB.index then
			sideB.index[pet.s .. "|" .. pet.v] = true
		end
	end
	for petId, pet in fromB do
		sideA.pets[petId] = pet
		if sideA.index then
			sideA.index[pet.s .. "|" .. pet.v] = true
		end
	end
	session.stage = "Done"
	session.version += 1
	return movedA, movedB
end

-- What one side of a trade is worth, shown in the trade window. `rarity` is how many hatches it takes on
-- average to get each creature (a Golden is 50, a Titan 2M), summed. It's only for the scam warning.
export type Worth = { count: number, titans: number, bigs: number, rare: number, rarity: number }

function TradeLogic.worth(pets: { { s: string, v: string, z: string } }): Worth
	local worth = { count = 0, titans = 0, bigs = 0, rare = 0, rarity = 0 }
	for _, pet in pets do
		local variant = Variants.byId[pet.v]
		local size = Sizes.byId[pet.z]
		worth.count += 1
		if pet.z == "Titan" then
			worth.titans += 1
		elseif pet.z == "Big" then
			worth.bigs += 1
		end
		if variant and variant.order >= 4 then -- Lava, Neon, Pixel
			worth.rare += 1
		end
		local variantOdds = if variant and variant.chance > 0 then 1 / variant.chance else 1
		local sizeOdds = if size and size.chance > 0 then 1 / size.chance else 1
		worth.rarity += variantOdds * sizeOdds
	end
	return worth
end

-- True when you give much rarer creatures than you get back (3x or more), so the window warns you.
function TradeLogic.lopsided(give: Worth, get: Worth): boolean
	return give.rarity >= 50 and give.rarity >= 3 * get.rarity
end

return TradeLogic
