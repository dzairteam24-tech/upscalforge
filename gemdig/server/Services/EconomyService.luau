--!strict
-- Coins: selling the backpack (at the Sell stand, or from anywhere with the Sell Anywhere pass), buying shovels and
-- backpacks one level at a time, rebirth, the daily reward, and what the drone earned while the player was away.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Backpack = require(Shared.Logic.Backpack)
local Daily = require(Shared.Logic.Daily)
local Economy = require(Shared.Logic.Economy)
local Gear = require(Shared.Config.Gear)
local Multiplier = require(Shared.Logic.Multiplier)
local Net = require(Shared.Net)
local Offline = require(Shared.Logic.Offline)
local OfflineConfig = require(Shared.Config.Offline)
local Rebirth = require(Shared.Logic.Rebirth)

local DataService = require(script.Parent.DataService)
local MineService = require(script.Parent.MineService)

local EconomyService = {}

local function notify(player: Player, text: string, kind: string)
	Net.event("Notify"):FireClient(player, text, kind)
end

-- What the player earns digging by hand, per minute, at their best layer (before the sell multiplier)
function EconomyService.perMinute(data: DataService.Data): number
	local _, rate = Economy.best(data.shovel, data.pack, math.max(1, data.deepest))
	return rate
end

-- Sells the whole backpack. `remote`: from anywhere (needs the pass)
function EconomyService.sell(player: Player, remote: boolean?)
	local data = DataService.get(player)
	if not data then
		return
	end
	if remote and not data.passes.RemoteSell then
		notify(player, "Sell Anywhere is a pass in the Store", "bad")
		return
	end
	local count, coins = Backpack.sellAll(data, Multiplier.sell(data, os.time()))
	if count == 0 then
		notify(player, "Your backpack is empty: go dig!", "info")
		return
	end
	notify(player, ("Sold %d gems for %s coins"):format(count, tostring(coins)), "good")
	DataService.push(player)
end

-- Buys the next shovel or backpack (kind "shovel" or "pack"; `index` must be the one after the player's own)
function EconomyService.buy(player: Player, kind: any, index: any): boolean
	local data = DataService.get(player)
	if not data or type(index) ~= "number" or (kind ~= "shovel" and kind ~= "pack") then
		return false
	end
	local list = if kind == "shovel" then Gear.SHOVELS else Gear.PACKS
	local owned = if kind == "shovel" then data.shovel else data.pack
	if index ~= owned + 1 or not list[index] then
		return false
	end
	local item = list[index]
	if data.coins < item.price then
		notify(player, "Not enough coins", "bad")
		return false
	end
	data.coins -= item.price
	if kind == "shovel" then
		data.shovel = index
	else
		data.pack = index
	end
	notify(player, "Bought " .. item.name, "good")
	DataService.push(player)
	return true
end

function EconomyService.rebirth(player: Player): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	local ok, why = Rebirth.can(data)
	if not ok then
		notify(player, why or "Not yet", "bad")
		return false
	end
	data.coins -= Rebirth.cost(data.rebirths)
	Rebirth.apply(data)
	MineService.resetMine(player, true)
	notify(player, ("REBIRTH %d! Everything you sell is now worth x%s"):format(data.rebirths, tostring(Multiplier.sell(data, os.time()))), "Legendary")
	DataService.push(player)
	return true
end

-- Today's reward, once a day
function EconomyService.claimDaily(player: Player): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	local now = os.time()
	local coins, boost = Daily.claim(data, now, EconomyService.perMinute(data) * Multiplier.sell(data, now))
	if coins <= 0 then
		notify(player, "Come back tomorrow for the next reward", "info")
		return false
	end
	data.coins += coins
	if boost > 0 then
		data.boostUntil = math.max(now, data.boostUntil) + boost * 60
	end
	notify(player, ("Daily reward: %d coins%s"):format(coins, if boost > 0 then (" and a %d minute double-coins boost"):format(boost) else ""), "good")
	DataService.push(player)
	return true
end

-- The drone's earnings for time away: paid when the player's data loads
function EconomyService.welcomeBack(player: Player, data: DataService.Data)
	local now = os.time()
	local away = now - data.lastSeen
	data.lastSeen = now
	local coins = Offline.coins(away, data.passes.Offline == true, EconomyService.perMinute(data), Multiplier.sell(data, now))
	if coins > 0 then
		data.coins += coins
		local capped = away > (if data.passes.Offline then OfflineConfig.PASS_HOURS else OfflineConfig.FREE_HOURS) * 3600
		Net.event("Offline"):FireClient(player, coins, Offline.counted(away, data.passes.Offline == true), capped)
		DataService.push(player)
	end
end

function EconomyService.init()
	Net.event("Buy").OnServerEvent:Connect(function(player, kind, index)
		EconomyService.buy(player, kind, index)
	end)
	Net.event("Rebirth").OnServerEvent:Connect(function(player)
		EconomyService.rebirth(player)
	end)
	Net.event("Daily").OnServerEvent:Connect(function(player)
		EconomyService.claimDaily(player)
	end)
	Net.event("RemoteSell").OnServerEvent:Connect(function(player)
		EconomyService.sell(player, true)
	end)
end

return EconomyService
