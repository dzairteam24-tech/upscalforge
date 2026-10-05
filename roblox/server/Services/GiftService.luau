-- Gifts between friends: once a day you can send a free elixir to a Roblox friend in your server.
-- They get a tier II-III elixir, you get a few gems for being nice. A player can receive 3 gifts a day.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Loot = require(Shared.Logic.Loot)
local Progress = require(Shared.Logic.Progress)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local State = require(script.Parent.State)

local GiftService = {}

local SENDER_GEMS = 5
local MAX_RECEIVED = 3
local rng = Random.new()

local function rollover(data)
	local day = Progress.day(os.time())
	if data.gifts.day ~= day then
		data.gifts.day = day
		data.gifts.sent = false
		data.gifts.received = 0
	end
end

local function send(player: Player, targetId: any)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or type(targetId) ~= "number" or not State.throttle(runtime, "Gift", 2) then
		return
	end
	local target = Players:GetPlayerByUserId(targetId)
	local targetData = target and DataService.get(target)
	if not target or not targetData or target == player then
		return
	end
	rollover(data)
	rollover(targetData)
	if data.gifts.sent then
		GameService.notify(player, "You already sent today's gift. One a day!", "error")
		return
	end
	local ok, friends = pcall(function()
		return player:IsFriendsWith(target.UserId)
	end)
	if not ok or not friends then
		GameService.notify(player, "Gifts are for your Roblox friends", "error")
		return
	end
	if targetData.gifts.received >= MAX_RECEIVED then
		GameService.notify(player, ("%s already got %d gifts today"):format(target.DisplayName, MAX_RECEIVED), "error")
		return
	end
	data.gifts.sent = true
	targetData.gifts.received += 1
	local elixir = Loot.randomElixir(2, 3, function()
		return rng:NextNumber()
	end)
	GameService.giveItem(target, elixir, 1, false)
	data.gems += SENDER_GEMS
	GameService.notify(target, ("🎁 %s sent you a %s!"):format(player.DisplayName, Items.byId[elixir].name), "rare")
	GameService.notify(player, ("🎁 Gift sent to %s! +💎 %d"):format(target.DisplayName, SENDER_GEMS), "success")
	GameService.refresh(player)
	GameService.refresh(target)
end

function GiftService.init()
	Net.event("SendGift").OnServerEvent:Connect(send)
end

return GiftService
