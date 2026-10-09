-- Bigs that appear in zones (catch chance) and zone guardians (Titans) that appear at 100% restoration
-- (tame chance, 4 hour cooldown per player and zone).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FirstClearConfig = require(Shared.Config.FirstClear)
local FirstClear = require(Shared.Logic.FirstClear)
local Hunt = require(Shared.Config.Hunt)
local World1 = require(Shared.Config.World1)
local Boosts = require(Shared.Logic.Boosts)
local Effects = require(Shared.Logic.Effects)
local Gear = require(Shared.Logic.Gear)
local EggRoll = require(Shared.Logic.EggRoll)
local Format = require(Shared.Logic.Format)
local Inventory = require(Shared.Logic.Inventory)
local Pity = require(Shared.Logic.Pity)
local MapLayout = require(Shared.Logic.MapLayout)

local BreakableService = require(script.Parent.BreakableService)
local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local WorldBuilder = require(script.Parent.WorldBuilder)
local State = require(script.Parent.State)

local HuntService = {}

local rng = Random.new()
local nextBig: { [number]: number } = {}
local activeBig: { [number]: BreakableService.Source } = {}
local activeGuardian: { [number]: BreakableService.Source } = {}
-- After a guardian is beaten or leaves, the zone rests before the next one (os.clock())
local guardianRest: { [number]: number } = {}

local function playersInZone(zoneId: number): { Player }
	local out = {}
	for player, runtime in State.all() do
		if runtime.zoneId == zoneId and player.Parent then
			table.insert(out, player)
		end
	end
	return out
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

-- Bigs and guardians show up in the Egg Garden, on the lawn in front of their tier's egg
local function nearEgg(zoneId: number, spread: number): Vector3
	local egg = WorldBuilder.eggPositions[zoneId] or MapLayout.center(0)
	local inward = (WorldBuilder.gardenCenter() - egg) * Vector3.new(1, 0, 1)
	inward = if inward.Magnitude > 1 then inward.Unit else Vector3.new(0, 0, 1)
	local side = Vector3.new(inward.Z, 0, -inward.X)
	return Vector3.new(egg.X, 0, egg.Z) + inward * (16 + rng:NextNumber() * spread) + side * (rng:NextNumber(-1, 1) * spread)
end

local function randomSpot(zoneId: number): Vector3
	return nearEgg(zoneId, 8)
end

local function spawnBig(zoneId: number)
	local zone = World1.zonesById[zoneId]
	local roll = EggRoll.roll(zoneId, { luck = 1 }, function()
		return rng:NextNumber()
	end)
	local pet = { s = roll.s, v = roll.v, z = "Big" }
	local coins = zone.restoreGoal * Hunt.BIG_COINS
	activeBig[zoneId] = BreakableService.spawnSpecial(zoneId, "Big", pet, randomSpot(zoneId), coins, Hunt.BIG_LIFETIME)
	GameService.notifyZone(zoneId, ("A %s appeared! Collect from it to catch it."):format(describe(pet)), "rare")
end

local function spawnGuardian(zoneId: number, eligible: { Player })
	local zone = World1.zonesById[zoneId]
	-- The guardian is the zone's 1% creature (the Legendary stays an egg-only find)
	local speciesId = zone.species[math.min(4, #zone.species)]
	local pet = { s = speciesId, v = "Normal", z = "Titan" }
	local coins = zone.restoreGoal * Hunt.GUARDIAN_COINS
	local source = BreakableService.spawnSpecial(zoneId, "Guardian", pet, nearEgg(zoneId, 0), coins, Hunt.GUARDIAN_LIFETIME)
	for _, player in eligible do
		(source.special :: BreakableService.Special).eligible[player] = true
	end
	activeGuardian[zoneId] = source
	GameService.notifyZone(zoneId, ("The guardian of %s, %s, has appeared!"):format(zone.name, describe(pet)), "rare")
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
			local base = math.min(Hunt.BIG_CATCH_CAP, Hunt.BIG_CATCH_CHANCE * Effects.get(runtime.effects, "BigSpawn"))
			local chance = Pity.chance(base, data.pity.big, Hunt.BIG_PITY, 0)
			if Inventory.count(data) >= GameService.capacity(player) then
				-- Full storage doesn't count as a miss
				GameService.notify(player, "Your storage is full, the Big got away! Make room to catch the next one.", "error")
			elseif rng:NextNumber() < chance then
				data.pity.big = 0
				Inventory.add(data, special.pet, GameService.newId)
				GameService.progress(player, "BigCatch", 1)
				GameService.notify(player, ("You caught a %s!"):format(describe(special.pet)), "rare")
				GameService.refresh(player)
			else
				data.pity.big += 1
				local left = Pity.left(data.pity.big, Hunt.BIG_PITY)
				GameService.notify(
					player,
					if left == 1
						then "The Big ran away! The next one is a sure catch."
						else ("The Big ran away! Sure catch in %d tries."):format(left),
					"info"
				)
			end
		elseif special.type == "Guardian" then
			-- Rewards only for players whose fight counts; others helped but are on their cooldown
			if not special.eligible[player] then
				GameService.notify(player, "You helped! Your own guardian reward comes back after your cooldown.", "info")
				continue
			end
			GameService.progress(player, "Guardian", 1)
			data.gems += Hunt.GUARDIAN_GEMS * zoneId
			data.guardians[tostring(zoneId)] = os.time() + Hunt.GUARDIAN_COOLDOWN
			if FirstClear.mark(data.clears, FirstClear.guardianKey(zoneId)) then
				data.gems += FirstClearConfig.GUARDIAN_GEMS * zoneId
				GameService.notify(
					player,
					("⭐ First clear! Coins +%d%% forever (now +%d%%) and 💎 %d"):format(
						FirstClearConfig.GUARDIAN_COINS * 100,
						math.floor((FirstClear.coinMult(data.clears) - 1) * 100 + 0.5),
						FirstClearConfig.GUARDIAN_GEMS * zoneId
					),
					"rare"
				)
			end
			local chance = Pity.chance(Hunt.GUARDIAN_TAME_CHANCE, data.pity.titan, Hunt.TITAN_PITY, Hunt.TITAN_PITY_STEP)
			if Inventory.count(data) >= GameService.capacity(player) then
				GameService.notify(player, "Your storage is full, so the Titan couldn't join you. Make room first!", "error")
			elseif rng:NextNumber() < chance then
				data.pity.titan = 0
				Inventory.add(data, special.pet, GameService.newId)
				GameService.progress(player, "Titan", 1)
				GameService.notifyAll(("👑 %s TAMED %s!"):format(player.DisplayName, describe(special.pet)), "rare")
			else
				data.pity.titan += 1
				local nextChance = Pity.chance(Hunt.GUARDIAN_TAME_CHANCE, data.pity.titan, Hunt.TITAN_PITY, Hunt.TITAN_PITY_STEP)
				GameService.notify(
					player,
					("Guardian defeated! Next tame chance: %s (sure in %d). Back in %s."):format(
						Format.chance(nextChance),
						Pity.left(data.pity.titan, Hunt.TITAN_PITY),
						Format.time(Hunt.GUARDIAN_COOLDOWN)
					),
					"success"
				)
			end
			GameService.refresh(player)
		end
	end
	if activeBig[zoneId] == source then
		activeBig[zoneId] = nil
	end
	if activeGuardian[zoneId] == source then
		activeGuardian[zoneId] = nil
		guardianRest[zoneId] = os.clock() + Hunt.GUARDIAN_REST
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
			GameService.notifyZone(zoneId, "The Big ran away...", "info")
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
			GameService.notifyZone(zoneId, "The guardian left. It will be back in a minute.", "info")
			BreakableService.despawn(guardian)
			activeGuardian[zoneId] = nil
			guardianRest[zoneId] = now + Hunt.GUARDIAN_REST
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
		elseif #eligible > 0 and now >= (guardianRest[zoneId] or 0) then
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
