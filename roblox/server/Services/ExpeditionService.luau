-- Expeditions: send creatures that aren't on the team on timed trips, then claim what they bring back.
-- Trips use os.time(), so they keep going while the player is offline.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Expeditions = require(Shared.Config.Expeditions)
local Items = require(Shared.Config.Items)
local World1 = require(Shared.Config.World1)
local Expedition = require(Shared.Logic.Expedition)
local Format = require(Shared.Logic.Format)
local Types = require(Shared.Logic.Types)
local Net = require(Shared.Net)

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
	local ids: { string } = {}
	for i, petId in petIds do
		if type(i) ~= "number" or type(petId) ~= "string" or i > 16 then
			return
		end
		ids[i] = petId
	end
	local ok, err = Expedition.validate(data, kindId, ids)
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
	local trip, err = Expedition.claim(data, index, os.time())
	if not trip then
		GameService.notify(player, err or "Can't claim this trip", "error")
		return
	end
	local reward = Expedition.rewards(trip, bestZone(data), function()
		return rng:NextNumber()
	end)
	local coins = GameService.rewardCoins(player, reward.coins, nil)
	data.gems += reward.gems
	for _, itemId in reward.items do
		GameService.giveItem(player, itemId, 1, false)
	end

	local parts = { "🪙 " .. Format.abbrev(coins) }
	if reward.gems > 0 then
		table.insert(parts, "💎 " .. Format.abbrev(reward.gems))
	end
	for _, itemId in reward.items do
		table.insert(parts, Items.byId[itemId].name)
	end
	GameService.notify(player, "Trip rewards: " .. table.concat(parts, ", "), "success")
	GameService.refresh(player)
end

function ExpeditionService.init()
	DataService.Loaded:Connect(function(player: Player, data: PlayerData)
		Expedition.repair(data)
		GameService.markDirty(player)
	end)
	Net.event("StartExpedition").OnServerEvent:Connect(startExpedition)
	Net.event("ClaimExpedition").OnServerEvent:Connect(claimExpedition)
end

return ExpeditionService
