-- Hatching, team management, locking, deleting and fusion.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Variants = require(Shared.Config.Variants)
local World1 = require(Shared.Config.World1)
local Effects = require(Shared.Logic.Effects)
local Gear = require(Shared.Logic.Gear)
local EggRoll = require(Shared.Logic.EggRoll)
local Inventory = require(Shared.Logic.Inventory)
local Types = require(Shared.Logic.Types)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local State = require(script.Parent.State)
local WorldBuilder = require(script.Parent.WorldBuilder)

type PlayerData = Types.PlayerData

local PetService = {}

-- TradeService sets this so inventory can't change mid-trade.
PetService.isTrading = function(_player: Player): boolean
	return false
end

local HatchResult = Net.event("HatchResult")
local rng = Random.new()

local function newId(): string
	return string.sub(HttpService:GenerateGUID(false):gsub("-", ""), 1, 16)
end

local function random(): number
	return rng:NextNumber()
end

local function isRare(roll: Types.Roll): boolean
	return roll.z ~= "Normal" or Variants.byId[roll.v].order >= Variants.byId.Neon.order
end

local function describe(roll: Types.Roll): string
	local parts = {}
	if roll.z ~= "Normal" then
		table.insert(parts, roll.z)
	end
	if roll.v ~= "Normal" then
		table.insert(parts, roll.v)
	end
	table.insert(parts, roll.s)
	return table.concat(parts, " ")
end

-- Rolls and adds creatures. Used by egg stands (paid) and EggDrop skills (free).
local function grant(
	player: Player,
	data: PlayerData,
	zoneId: number,
	eggs: number,
	extraLuck: number,
	minVariant: string?,
	free: boolean
): { { id: string, s: string, v: string, z: string } }
	local runtime = State.get(player)
	if not runtime then
		return {}
	end
	local results = {}
	local luck = GameService.luck(player) * extraLuck
	local perEgg = 1 + math.floor(Effects.get(runtime.effects, "EggExtra"))
	local doubleChance = Gear.get(runtime.gear, "EggExtraChance")
	for _ = 1, eggs do
		local count = perEgg + (if rng:NextNumber() < doubleChance then 1 else 0)
		for _ = 1, count do
			local forceGolden = not data.flags.gotGolden
				and (data.stats.hatches or 0) + 1 >= Constants.GUARANTEED_GOLDEN_BY_HATCH
			local roll = EggRoll.roll(zoneId, {
				luck = luck,
				variantChance = GameService.variantChance(player, zoneId),
				forceGolden = forceGolden,
				minVariant = minVariant,
			}, random)
			local id = Inventory.add(data, roll, newId)
			data.stats.hatches = (data.stats.hatches or 0) + 1
			if Variants.byId[roll.v].order >= 2 then
				data.flags.gotGolden = true
			end
			table.insert(results, { id = id, s = roll.s, v = roll.v, z = roll.z })
			if isRare(roll) then
				GameService.notifyAll(("%s hatched a %s!"):format(player.DisplayName, describe(roll)), "rare")
			end
		end
	end
	GameService.progress(player, "Hatch", eggs)
	if data.settings.autoEquipBest then
		Inventory.equipBest(data, GameService.maxSlots(player))
	end
	GameService.refresh(player)
	HatchResult:FireClient(player, results, free)
	return results
end

local function hatch(player: Player, zoneId: any, amount: any)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or type(zoneId) ~= "number" or type(amount) ~= "number" then
		return
	end
	local zone = World1.zonesById[zoneId]
	if not zone or zone.eggPrice <= 0 then
		return
	end
	if amount ~= 1 and amount ~= 3 and amount ~= 8 then
		return
	end
	if amount == 3 and (data.upgrades.Hatch3 or 0) < 1 then
		GameService.notify(player, "Buy Triple Hatch in the shop first", "error")
		return
	end
	if amount == 8 and (data.upgrades.Hatch8 or 0) < 1 then
		GameService.notify(player, "Buy Octo Hatch in the shop first", "error")
		return
	end
	if not data.unlockedZones[tostring(zoneId)] then
		return
	end
	local now = os.clock()
	if now - runtime.lastHatch < Constants.HATCH_COOLDOWN / Gear.get(runtime.gear, "HatchSpeed") then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local eggPos = WorldBuilder.eggPositions[zoneId]
	if not root or not eggPos or (root.Position - eggPos).Magnitude > Constants.EGG_RANGE + 6 then
		GameService.notify(player, "Walk up to the egg", "error")
		return
	end

	local perEgg = 1 + math.floor(Effects.get(runtime.effects, "EggExtra"))
	if Inventory.count(data) + amount * perEgg > GameService.capacity(player) then
		GameService.notify(player, "Your storage is full. Delete or fuse some creatures.", "error")
		return
	end
	local cost = zone.eggPrice * amount
	if data.coins < cost then
		GameService.notify(player, "Not enough coins", "error")
		return
	end
	runtime.lastHatch = now

	-- FreeHatch skill: each egg has a chance to cost nothing
	local freeChance = Effects.get(runtime.effects, "FreeHatch")
	local paid = 0
	for _ = 1, amount do
		if rng:NextNumber() >= freeChance then
			paid += zone.eggPrice
		end
	end
	data.coins -= paid
	grant(player, data, zoneId, amount, 1, nil, false)
end

function PetService.init()
	GameService.setHatcher(function(player, zoneId, count, luck, minVariant)
		local data = DataService.get(player)
		if not data then
			return
		end
		local perEgg = 1 + math.floor(Effects.get((State.get(player) :: State.Runtime).effects, "EggExtra"))
		local room = GameService.capacity(player) - Inventory.count(data)
		local eggs = math.min(count, room // perEgg)
		if eggs <= 0 then
			GameService.notify(player, "Free eggs skipped: storage is full", "error")
			return
		end
		grant(player, data, zoneId, eggs, luck, minVariant, true)
	end)

	Net.event("Hatch").OnServerEvent:Connect(hatch)

	Net.event("EquipPet").OnServerEvent:Connect(function(player, petId)
		local data = DataService.get(player)
		if not data or type(petId) ~= "string" then
			return
		end
		local ok, err = Inventory.equip(data, petId, GameService.maxSlots(player))
		if not ok and err then
			GameService.notify(player, err, "error")
		end
		GameService.refresh(player)
	end)

	Net.event("UnequipPet").OnServerEvent:Connect(function(player, petId)
		local data = DataService.get(player)
		if not data or type(petId) ~= "string" then
			return
		end
		Inventory.unequip(data, petId)
		GameService.refresh(player)
	end)

	Net.event("EquipBest").OnServerEvent:Connect(function(player)
		local data = DataService.get(player)
		if not data then
			return
		end
		Inventory.equipBest(data, GameService.maxSlots(player))
		GameService.refresh(player)
	end)

	Net.event("LockPet").OnServerEvent:Connect(function(player, petId, locked)
		local data = DataService.get(player)
		if not data or type(petId) ~= "string" or type(locked) ~= "boolean" then
			return
		end
		if PetService.isTrading(player) then
			GameService.notify(player, "Finish your trade first", "error")
			return
		end
		Inventory.setLocked(data, petId, locked)
		GameService.markDirty(player)
	end)

	Net.event("DeletePets").OnServerEvent:Connect(function(player, petIds)
		local data = DataService.get(player)
		if not data or type(petIds) ~= "table" then
			return
		end
		if PetService.isTrading(player) then
			GameService.notify(player, "Finish your trade first", "error")
			return
		end
		local removed = 0
		for _, petId in petIds do
			local pet = type(petId) == "string" and data.pets[petId]
			if pet and not pet.lk and not pet.ex then
				Inventory.remove(data, petId)
				removed += 1
			end
		end
		if removed > 0 then
			GameService.notify(player, ("Deleted %d creature%s"):format(removed, if removed == 1 then "" else "s"))
		end
		GameService.refresh(player)
	end)

	Net.event("FusePets").OnServerEvent:Connect(function(player, speciesId, variantId)
		local data = DataService.get(player)
		local runtime = State.get(player)
		if not data or not runtime or type(speciesId) ~= "string" or type(variantId) ~= "string" then
			return
		end
		if PetService.isTrading(player) then
			GameService.notify(player, "Finish your trade first", "error")
			return
		end
		local cost = Constants.FUSION_COST
		local fromSkill = runtime.effects.values.FusionCost
		if fromSkill and fromSkill < cost then
			cost = fromSkill
		end
		local id, err = Inventory.fuse(data, speciesId, variantId, cost, newId)
		if not id then
			GameService.notify(player, err or "Can't fuse", "error")
			return
		end
		local pet = data.pets[id]
		GameService.notify(player, ("Fused a %s %s!"):format(pet.v, pet.s), "success")
		GameService.progress(player, "Fuse", 1)
		HatchResult:FireClient(player, { { id = id, s = pet.s, v = pet.v, z = pet.z } }, true)
		GameService.refresh(player)
	end)
end

return PetService
