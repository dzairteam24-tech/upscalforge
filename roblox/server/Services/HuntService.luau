-- Bigs that appear in zones (catch chance) and zone guardians (Titans) that appear at 100% restoration
-- (tame chance, 4 hour cooldown per player and zone).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Hunt = require(Shared.Config.Hunt)
local World1 = require(Shared.Config.World1)
local Boosts = require(Shared.Logic.Boosts)
local Effects = require(Shared.Logic.Effects)
local Gear = require(Shared.Logic.Gear)
local EggRoll = require(Shared.Logic.EggRoll)
local Inventory = require(Shared.Logic.Inventory)
local MapLayout = require(Shared.Logic.MapLayout)

local BreakableService = require(script.Parent.BreakableService)
local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local State = require(script.Parent.State)

local HuntService = {}

local rng = Random.new()
local nextBig: { [number]: number } = {}
local activeBig: { [number]: BreakableService.Source } = {}
local activeGuardian: { [number]: BreakableService.Source } = {}

local function newId(): string
	return string.sub(HttpService:GenerateGUID(false):gsub("-", ""), 1, 16)
end

local function playersInZone(zoneId: number): { Player }
	local out = {}
	for player, runtime in State.all() do
		if runtime.zoneId == zoneId and player.Parent then
			table.insert(out, player)
		end
	end
	return out
end

local function notifyZone(zoneId: number, text: string, kind: string)
	for _, player in playersInZone(zoneId) do
		GameService.notify(player, text, kind)
	end
end

local function describe(pet: { s: string, v: string, z: string }): string
	local words = { pet.z }
	if pet.v ~= "Normal" then
		table.insert(words, pet.v)
	end
	table.insert(words, pet.s)
	return table.concat(words, " ")
end

-- Big appearances speed up with BigSpawn skills and Hunter elixirs of players in the zone.
local function bigInterval(zoneId: number): number
	local hunt = 1
	for _, player in playersInZone(zoneId) do
		local runtime = State.get(player)
		local data = DataService.get(player)
		if runtime and data then
			hunt = math.max(
				hunt,
				Effects.get(runtime.effects, "BigSpawn") * Boosts.active(data.boosts, "Hunter") * Gear.get(runtime.gear, "BigSpawn")
			)
		end
	end
	return math.max(Hunt.BIG_MIN_INTERVAL, Hunt.BIG_INTERVAL / hunt)
end

local function randomSpot(zoneId: number): Vector3
	local center = MapLayout.center(zoneId)
	local angle = rng:NextNumber() * math.pi * 2
	local radius = rng:NextNumber(18, MapLayout.PLATFORM / 2 - 20)
	return center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

local function spawnBig(zoneId: number)
	local zone = World1.zonesById[zoneId]
	local roll = EggRoll.roll(zoneId, { luck = 1 }, function()
		return rng:NextNumber()
	end)
	local pet = { s = roll.s, v = roll.v, z = "Big" }
	local coins = zone.restoreGoal * Hunt.BIG_COINS
	activeBig[zoneId] = BreakableService.spawnSpecial(zoneId, "Big", pet, randomSpot(zoneId), coins, Hunt.BIG_LIFETIME)
	notifyZone(zoneId, ("A %s appeared! Collect from it to catch it."):format(describe(pet)), "rare")
end

local function spawnGuardian(zoneId: number, eligible: { Player })
	local zone = World1.zonesById[zoneId]
	local speciesId = zone.species[#zone.species]
	local pet = { s = speciesId, v = "Normal", z = "Titan" }
	local coins = zone.restoreGoal * Hunt.GUARDIAN_COINS
	local center = MapLayout.center(zoneId) + Vector3.new(0, 0, -12)
	local source = BreakableService.spawnSpecial(zoneId, "Guardian", pet, center, coins, Hunt.GUARDIAN_LIFETIME)
	for _, player in eligible do
		(source.special :: BreakableService.Special).eligible[player] = true
	end
	activeGuardian[zoneId] = source
	notifyZone(zoneId, ("The guardian of %s, %s, has appeared!"):format(zone.name, describe(pet)), "rare")
end

local function guardianReady(player: Player, zoneId: number): boolean
	local data = DataService.get(player)
	local zone = World1.zonesById[zoneId]
	if not data or zone.restoreGoal <= 0 then
		return false
	end
	local restored = (data.zoneProgress[tostring(zoneId)] or 0) >= zone.restoreGoal
	return restored and os.time() >= (data.guardians[tostring(zoneId)] or 0)
end

local function onBroken(source: BreakableService.Source, contributors: { [Player]: number })
	local special = source.special
	if not special then
		return
	end
	local zoneId = source.zoneId
	for player, share in contributors do
		local data = DataService.get(player)
		local runtime = State.get(player)
		if not data or not runtime or share <= 0 then
			continue
		end
		if special.type == "Big" then
			GameService.progress(player, "Big", 1)
			local chance = math.min(Hunt.BIG_CATCH_CAP, Hunt.BIG_CATCH_CHANCE * Effects.get(runtime.effects, "BigSpawn"))
			if rng:NextNumber() < chance then
				if Inventory.count(data) >= GameService.capacity(player) then
					GameService.notify(player, "Your storage is full, the Big got away!", "error")
				else
					Inventory.add(data, special.pet, newId)
					GameService.progress(player, "BigCatch", 1)
					GameService.notifyAll(("%s caught a %s!"):format(player.DisplayName, describe(special.pet)), "rare")
					GameService.refresh(player)
				end
			else
				GameService.notify(player, "The Big dropped its loot and ran away!", "info")
			end
		elseif special.type == "Guardian" then
			GameService.progress(player, "Guardian", 1)
			data.gems += Hunt.GUARDIAN_GEMS * zoneId
			if special.eligible[player] then
				data.guardians[tostring(zoneId)] = os.time() + Hunt.GUARDIAN_COOLDOWN
				if rng:NextNumber() < Hunt.GUARDIAN_TAME_CHANCE then
					if Inventory.count(data) >= GameService.capacity(player) then
						GameService.notify(player, "Your storage is full, the Titan couldn't join you!", "error")
					else
						Inventory.add(data, special.pet, newId)
						GameService.progress(player, "Titan", 1)
						GameService.notifyAll(("👑 %s TAMED %s!"):format(player.DisplayName, describe(special.pet)), "rare")
					end
				else
					GameService.notify(player, "Guardian defeated! It will be back in 4 hours.", "success")
				end
			end
			GameService.refresh(player)
		end
	end
	if activeBig[zoneId] == source then
		activeBig[zoneId] = nil
	end
	if activeGuardian[zoneId] == source then
		activeGuardian[zoneId] = nil
	end
	BreakableService.despawn(source)
end

local function step()
	local now = os.clock()
	for _, zone in World1.zones do
		local zoneId = zone.id
		if zoneId == 0 then
			continue
		end
		local players = playersInZone(zoneId)

		-- Big
		local big = activeBig[zoneId]
		if big and big.alive and now > (big.special :: BreakableService.Special).expires then
			notifyZone(zoneId, "The Big ran away...", "info")
			BreakableService.despawn(big)
			activeBig[zoneId] = nil
			big = nil
		end
		if #players > 0 and not big then
			nextBig[zoneId] = nextBig[zoneId] or now + bigInterval(zoneId)
			if now >= nextBig[zoneId] then
				spawnBig(zoneId)
				nextBig[zoneId] = now + bigInterval(zoneId)
			end
		end

		-- Guardian
		local guardian = activeGuardian[zoneId]
		if guardian and guardian.alive and now > (guardian.special :: BreakableService.Special).expires then
			notifyZone(zoneId, "The guardian left. It will come back when you return.", "info")
			BreakableService.despawn(guardian)
			activeGuardian[zoneId] = nil
			guardian = nil
		end
		local eligible = {}
		for _, player in players do
			if guardianReady(player, zoneId) then
				table.insert(eligible, player)
			end
		end
		if guardian then
			for _, player in eligible do
				(guardian.special :: BreakableService.Special).eligible[player] = true
			end
		elseif #eligible > 0 then
			spawnGuardian(zoneId, eligible)
		end
	end
end

-- Titan Key: lets a player fight a guardian again right away.
function HuntService.resetGuardian(player: Player, zoneId: number)
	local data = DataService.get(player)
	if data then
		data.guardians[tostring(zoneId)] = 0
	end
end

function HuntService.init()
	BreakableService.Broken:Connect(onBroken)
	task.spawn(function()
		while true do
			task.wait(2)
			local ok, err = pcall(step)
			if not ok then
				warn("[Hunt] step error", err)
			end
		end
	end)
end

return HuntService
