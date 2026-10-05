-- Expeditions: send creatures that aren't on the team on timed trips, then claim what they bring back.
-- Trips use os.time(), so they keep going while the player is offline.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Expeditions = require(Shared.Config.Expeditions)
local Items = require(Shared.Config.Items)
local World1 = require(Shared.Config.World1)
local Expedition = require(Shared.Logic.Expedition)
local Format = require(Shared.Logic.Format)
local Unlocks = require(Shared.Logic.Unlocks)
local Types = require(Shared.Logic.Types)
local Net = require(Shared.Net)

local RewardService = require(script.Parent.RewardService)
local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local State = require(script.Parent.State)

type PlayerData = Types.PlayerData

local ExpeditionService = {}

local rng = Random.new()

local function bestZone(data: PlayerData): number
	local best = 1
	for _, zone in World1.zones do
		if zone.eggPrice > 0 and data.unlockedZones[tostring(zone.id)] then
			best = math.max(best, zone.id)
		end
	end
	return best
end

local function startExpedition(player: Player, kindId: any, petIds: any)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or type(kindId) ~= "string" or type(petIds) ~= "table" then
		return
	end
	if not State.throttle(runtime, "StartExpedition", 0.5) then
		return
	end
	if not Unlocks.has(data, "Trips") then
		GameService.notify(player, Unlocks.lockedText("Trips"), "error")
		return
	end
	local ids: { string } = {}
	for i, petId in petIds do
		if type(i) ~= "number" or type(petId) ~= "string" or i > 16 then
			return
		end
		ids[i] = petId
	end
	local ok, err = Expedition.validate(data, kindId, ids, GameService.extraTripSlots(player))
	if not ok then
		GameService.notify(player, err or "Can't start this trip", "error")
		return
	end
	local trip = Expedition.start(data, kindId, ids, os.time())
	local kind = Expeditions.byId[kindId]
	local note = if trip.element then " Same element: +50%!" else ""
	GameService.notify(player, ("%s started! Back in %s.%s"):format(kind.name, Format.time(kind.duration), note), "success")
	GameService.progress(player, "Expedition", 1)
	GameService.refresh(player)
end

-- Finds a trip by its start time (the client's id for it), or the first one matching `fallback`.
local function findTrip(data: PlayerData, started: any, fallback: (Types.Expedition) -> boolean): number?
	for index, trip in data.expeditions do
		if trip.started == started then
			return index
		end
	end
	for index, trip in data.expeditions do
		if fallback(trip) then
			return index
		end
	end
	return nil
end

-- Claims a finished trip. `mult` doubles everything for the ad reward.
local function claim(player: Player, data: PlayerData, index: number, mult: number): boolean
	local trip, err = Expedition.claim(data, index, os.time())
	if not trip then
		GameService.notify(player, err or "Can't claim this trip", "error")
		return false
	end
	local reward = Expedition.rewards(trip, bestZone(data), function()
		return rng:NextNumber()
	end)
	local coins = GameService.rewardCoins(player, reward.coins * mult, nil)
	data.gems += reward.gems * mult
	data.tickets += reward.tickets * mult
	for _, itemId in reward.items do
		GameService.giveItem(player, itemId, mult, false)
	end

	local parts = { "🪙 " .. Format.abbrev(coins) }
	if reward.gems > 0 then
		table.insert(parts, "💎 " .. Format.abbrev(reward.gems * mult))
	end
	if reward.tickets > 0 then
		table.insert(parts, "🎟️ " .. reward.tickets * mult)
	end
	for _, itemId in reward.items do
		table.insert(parts, Items.byId[itemId].name .. (if mult > 1 then " x" .. mult else ""))
	end
	local heading = if mult > 1 then "Double trip rewards: " else "Trip rewards: "
	GameService.notify(player, heading .. table.concat(parts, ", "), "success")
	GameService.refresh(player)
	return true
end

-- `started` identifies the trip, so a double tap can't claim the next one in the list.
local function claimExpedition(player: Player, index: any, started: any)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or type(index) ~= "number" or index ~= math.floor(index) then
		return
	end
	if not State.throttle(runtime, "ClaimExpedition", 0.3) then
		return
	end
	local listed = data.expeditions[index]
	if not listed or (type(started) == "number" and listed.started ~= started) then
		return
	end
	claim(player, data, index, 1)
end

local function isAway(trip: Types.Expedition): boolean
	return os.time() < trip.ends
end

local function isBack(trip: Types.Expedition): boolean
	return os.time() >= trip.ends
end

function ExpeditionService.init()
	DataService.Loaded:Connect(function(player: Player, data: PlayerData)
		Expedition.repair(data)
		GameService.markDirty(player)
	end)
	Net.event("StartExpedition").OnServerEvent:Connect(startExpedition)
	Net.event("ClaimExpedition").OnServerEvent:Connect(claimExpedition)

	-- Ad or Robux: the creatures come back right away
	RewardService.register("TripSkip", {
		canUse = function(player, started)
			local data = DataService.get(player)
			local index = data and findTrip(data, started, isAway)
			if not data or not index or not isAway(data.expeditions[index]) then
				return false, "No trip is on its way"
			end
			return true, nil
		end,
		grant = function(player, started)
			local data = DataService.get(player)
			local index = data and findTrip(data, started, isAway)
			if not data or not index or not isAway(data.expeditions[index]) then
				return false
			end
			data.expeditions[index].ends = os.time()
			GameService.notify(player, "Your creatures are back! Claim the trip.", "success")
			GameService.refresh(player)
			return true
		end,
	})

	-- Ad or Robux: claim a finished trip with double rewards
	RewardService.register("TripDouble", {
		canUse = function(player, started)
			local data = DataService.get(player)
			local index = data and findTrip(data, started, isBack)
			if not data or not index or not isBack(data.expeditions[index]) then
				return false, "No trip is back yet"
			end
			return true, nil
		end,
		grant = function(player, started)
			local data = DataService.get(player)
			local index = data and findTrip(data, started, isBack)
			if not data or not index or not isBack(data.expeditions[index]) then
				return false
			end
			return claim(player, data, index, 2)
		end,
	})
end

return ExpeditionService
