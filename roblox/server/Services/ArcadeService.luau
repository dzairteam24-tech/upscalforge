-- Lucky Spin: a free spin every day, more for tickets or a video. The server rolls and gives the prize,
-- then tells the client which slice to stop on.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Config.Cosmetics)
local Items = require(Shared.Config.Items)
local Progression = require(Shared.Config.Progression)
local WheelConfig = require(Shared.Config.Wheel)
local World1 = require(Shared.Config.World1)
local Loot = require(Shared.Logic.Loot)
local Progress = require(Shared.Logic.Progress)
local Types = require(Shared.Logic.Types)
local Wheel = require(Shared.Logic.Wheel)
local Net = require(Shared.Net)

local RewardService = require(script.Parent.RewardService)
local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local ProgressionService = require(script.Parent.ProgressionService)
local State = require(script.Parent.State)

type PlayerData = Types.PlayerData

local ArcadeService = {}

local rng = Random.new()

local function random(): number
	return rng:NextNumber()
end

local function bestZone(data: PlayerData): number
	local best = 1
	for _, zone in World1.zones do
		if zone.eggPrice > 0 and data.unlockedZones[tostring(zone.id)] then
			best = math.max(best, zone.id)
		end
	end
	return best
end

local KEY_HALVES = { { id = "KeyHalf_Zone", weight = 6 }, { id = "KeyHalf_Golden", weight = 3 }, { id = "KeyHalf_Titan", weight = 1 } }

local function randomKeyHalf(): string
	local pick = random() * 10
	for _, entry in KEY_HALVES do
		pick -= entry.weight
		if pick < 0 then
			return entry.id
		end
	end
	return KEY_HALVES[1].id
end

-- Turns a slice into a concrete reward.
local function prizeFor(data: PlayerData, sliceId: string): Progression.Reward
	if sliceId == "Coins" then
		return { coinsInEggs = 3 }
	elseif sliceId == "Elixir" then
		local bonus = Loot.zoneTierBonus(bestZone(data))
		return { items = { { id = Loot.randomElixir(2 + bonus, 3 + bonus, random), amount = 1 } } }
	elseif sliceId == "Gems" then
		return { gems = 25 }
	elseif sliceId == "KeyHalf" then
		return { items = { { id = randomKeyHalf(), amount = 1 } } }
	elseif sliceId == "Tickets" then
		return { tickets = 5 }
	elseif sliceId == "Sticker" then
		return { items = { { id = Loot.randomSticker(2, random), amount = 1 } } }
	elseif sliceId == "Gadget" then
		return { items = { { id = Loot.randomGadget(random), amount = 1 } } }
	elseif sliceId == "Eggs" then
		return { freeEggs = 3, freeEggLuck = 2 }
	end
	-- Jackpot: the Pixel Board ride (or gems if owned) and a Holo sticker
	local families = Items.stickerFamilies
	local holo = Items.stickerId(families[1 + math.floor(random() * #families)].id, 3)
	if data.rides[WheelConfig.JACKPOT_RIDE] then
		return { gems = WheelConfig.JACKPOT_GEMS_IF_OWNED, items = { { id = holo, amount = 1 } } }
	end
	return { ride = WheelConfig.JACKPOT_RIDE, items = { { id = holo, amount = 1 } } }
end

local function spin(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local index = Wheel.spin(random)
	local slice = WheelConfig.slices[index]
	local summary = ProgressionService.grant(player, prizeFor(data, slice.id))
	Net.event("WheelResult"):FireClient(player, index, summary)
	if slice.id == "Jackpot" then
		local ride = Cosmetics.rideById[WheelConfig.JACKPOT_RIDE]
		GameService.notifyAll(("👑 %s hit the Lucky Spin JACKPOT! (%s)"):format(player.DisplayName, ride and ride.name or "ride"), "rare")
	end
	GameService.markDirty(player)
end

local function spinRequest(player: Player, mode: any)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or not State.throttle(runtime, "SpinWheel", 2.5) then
		return
	end
	local today = Progress.day(os.time())
	if mode == "free" then
		if not Wheel.freeReady(data.wheel.lastFree, today) then
			GameService.notify(player, "Your free spin is back tomorrow", "error")
			return
		end
		data.wheel.lastFree = today
	elseif mode == "ticket" then
		if data.tickets < WheelConfig.TICKET_COST then
			GameService.notify(player, ("You need %d tickets"):format(WheelConfig.TICKET_COST), "error")
			return
		end
		data.tickets -= WheelConfig.TICKET_COST
	else
		return
	end
	spin(player)
end

function ArcadeService.init()
	Net.event("SpinWheel").OnServerEvent:Connect(spinRequest)
	RewardService.register("Spin", {
		canUse = function()
			return true, nil
		end,
		grant = function(player)
			spin(player)
			return true
		end,
	})
end

return ArcadeService
